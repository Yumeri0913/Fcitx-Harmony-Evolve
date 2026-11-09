#include "fcitx.h"
#include <fcitx-utils/event.h>
#include <fcitx-utils/i18n.h>
#include <fcitx-utils/eventdispatcher.h>
#include <fcitx-utils/standardpath.h>
#include <fcitx-utils/standardpaths.h>
#include <fstream>
#include <iterator>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/rawconfig.h>
#include <fcitx/action.h>
#include <fcitx/addonmanager.h>
#include <fcitx/globalconfig.h>
#include <fcitx/inputmethodmanager.h>
#include <fcitx/instance.h>
#include <fcitx/userinterfacemanager.h>
#include <thread>
#include <clocale>
#include <libintl.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <filesystem>
#include "nativestreambuf.h"
#include "keycode.h"
#include "util.h"
#include "../harmonyfrontend/harmonyfrontend.h"
#include "../webkeyboard/webkeyboard.h"
#include "inputmethod.h"
#include "googlepinyin_public.h"
#include "quickphrase_public.h"
#include "unicode_public.h"
#include "googlepinyin_userdata.h"

// Native library directory names in the bundle, as nativeLibraryPath "libs/arm64".
#ifdef __x86_64__
#define ARCH "x86_64"
#elif defined(__aarch64__)
#define ARCH "arm64"
#endif

namespace fs = std::filesystem;
using json = nlohmann::json;

FCITX_DEFINE_STATIC_ADDON_REGISTRY(getStaticAddon)

napi_threadsafe_function tsfn;

void notify_main_async(std::string str) {
    auto pStr = new std::string(std::move(str));
    napi_call_threadsafe_function_with_priority(tsfn, pStr, napi_priority_high, true);
}

namespace fcitx {
std::unique_ptr<Instance> instance;
std::unique_ptr<fcitx::EventDispatcher> dispatcher;
HarmonyFrontend *frontend;
WebKeyboard *ui;

static native_streambuf log_streambuf;
static std::ostream stream(&log_streambuf);

static std::thread fcitx_thread;

void setupLog() {
    fcitx::Log::setLogStream(stream);
    fcitx::Log::setLogRule("*=5,notimedate");
}

// Where shared addons like libpinyin.so are: next to this library. HarmonyOS names the
// directory libs/arm64, not after the ABI arm64-v8a, so ask the loader instead of guessing.
static std::string nativeLibraryDir(const ::fs::path &bundlePath) {
    Dl_info info;
    if (dladdr(reinterpret_cast<void *>(&nativeLibraryDir), &info) && info.dli_fname) {
        ::fs::path library = info.dli_fname;
        if (library.is_absolute()) {
            return library.parent_path();
        }
    }
    return bundlePath / "libs" / ARCH;
}

std::string configHome(const std::string &shared) { return ::fs::path(shared) / "config"; }

size_t configSignature(const std::string &shared);
// Config dir as last read or written by this process.
static size_t configSignature_ = 0;

void setupEnv(const std::string &bundle, const std::string &resfile, const std::string &files,
              const std::string &shared, const std::string &locale) {
    // resfile is /data/storage/el1/bundle/entry/resources/resfile
    ::fs::path bundlePath = bundle;
    ::fs::path resfilePath = resfile;
    std::string fcitx_addon_dirs = nativeLibraryDir(bundlePath);
    setenv("FCITX_ADDON_DIRS", fcitx_addon_dirs.c_str(), 1);
    FCITX_INFO() << "Addon dir: " << fcitx_addon_dirs;
    ::fs::path xdg_data_dirs = resfilePath / "usr" / "share";
    std::string fcitx_data_dirs = xdg_data_dirs / "fcitx5";
    std::string libime_model_dirs = resfilePath / "usr" / "lib" / "libime";
    std::string xkb_config_root = xdg_data_dirs / "xkeyboard-config-2";
    setenv("XDG_DATA_DIRS", xdg_data_dirs.c_str(), 1);
    setenv("FCITX_DATA_DIRS", fcitx_data_dirs.c_str(), 1);
    setenv("LIBIME_MODEL_DIRS", libime_model_dirs.c_str(), 1);
    setenv("XKB_CONFIG_ROOT", xkb_config_root.c_str(), 1);
    // Config is in the dir shared with the main app, whose settings edit it. User data
    // (pinyin user.dict and user.history) stays private to the process.
    ::fs::path filesPath = files;
    std::string xdg_config_home = configHome(shared);
    std::string xdg_data_home = filesPath / "data";
    std::string xdg_cache_home = filesPath / "cache";
    setenv("XDG_CONFIG_HOME", xdg_config_home.c_str(), 1);
    setenv("XDG_DATA_HOME", xdg_data_home.c_str(), 1);
    setenv("XDG_CACHE_HOME", xdg_cache_home.c_str(), 1);
    // isAndroid() is true on HarmonyOS, so fcitx takes the UI language from here.
    setenv("FCITX_LOCALE", locale.c_str(), 1);
    // gettext picks the catalog from LANGUAGE, e.g. zh_CN, but ignores it in the C locale.
    setenv("LANGUAGE", locale.c_str(), 1);
    std::string lang = locale + ".UTF-8";
    setenv("LANG", lang.c_str(), 1);
    setlocale(LC_MESSAGES, lang.c_str());
    // Translations are bundled, not at the compile time /usr/share/locale. Registering a
    // domain first makes later registrations by addons keep this path. The bundled
    // libintl-lite doesn't search a locale dir, so load each catalog explicitly.
    ::fs::path localeDir = xdg_data_dirs / "locale";
    std::vector<std::string> languages{locale};
    if (auto underscore = locale.find('_'); underscore != std::string::npos) {
        languages.push_back(locale.substr(0, underscore));
    }
    for (const char *domain : {"fcitx5", "fcitx5-chinese-addons", "fcitx5-lua", "xkeyboard-config", "iso_639-3"}) {
        registerDomain(domain, localeDir);
        for (const auto &language : languages) {
            auto mo = localeDir / language / "LC_MESSAGES" / (std::string(domain) + ".mo");
            if (::fs::exists(mo)) {
                loadMessageCatalog(domain, mo.c_str());
                break;
            }
        }
    }
}

// Google Pinyin starts in Chinese, like the fcitx5-android fork. Other defaults come
// from fcitx's Android branch (isAndroid() is true on HarmonyOS).
static void setDefaultConfig(const std::string &shared) {
    ::fs::path configDir = ::fs::path(configHome(shared)) / "fcitx5";
    if (!::fs::exists(configDir / "config")) {
        RawConfig raw;
        raw.setValueByPath("Behavior/ActiveByDefault", "True");
        instance->globalConfig().load(raw, true);
        instance->globalConfig().safeSave();
    }
}

// Builds before isAndroid() covered HarmonyOS saved desktop defaults, which then win over
// the Android ones. Switch those options once.
static void migrateToAndroidDefaults(const std::string &shared) {
    constexpr int version = 1;
    ::fs::path marker = ::fs::path(configHome(shared)) / "fcitx5" / "harmony-defaults-version";
    int current = 0;
    if (std::ifstream in(marker); in) {
        in >> current;
    }
    if (current >= version) {
        return;
    }
    RawConfig global;
    global.setValueByPath("Behavior/ShareInputState", "All");
    instance->globalConfig().load(global, true);
    instance->globalConfig().safeSave();
    // Pinyin is loaded on demand, so its config can still be changed here.
    RawConfig pinyin;
    readAsIni(pinyin, "conf/pinyin.conf");
    pinyin.setValueByPath("PreeditMode", "Do not show");
    pinyin.setValueByPath("PreeditCursorPositionAtBeginning", "False");
    pinyin.setValueByPath("Prediction", "True");
    pinyin.setValueByPath("ExtBEnabled", "False");
    pinyin.setValueByPath("Fuzzy/Correction", "QWERTY");
    safeSaveAsIni(pinyin, "conf/pinyin.conf");
    ::fs::create_directories(marker.parent_path());
    std::ofstream(marker) << version;
}

// Builds before the settings page kept config in the private files dir.
static void moveConfigToShared(const std::string &files, const std::string &shared) {
    ::fs::path from = ::fs::path(files) / "config";
    ::fs::path to = configHome(shared);
    std::error_code ec;
    if (::fs::exists(to, ec) || !::fs::exists(from, ec)) {
        return;
    }
    ::fs::create_directories(to.parent_path(), ec);
    ::fs::copy(from, to, ::fs::copy_options::recursive, ec);
    if (ec) {
        FCITX_ERROR() << "Failed to move config: " << ec.message();
    }
}

void init(const std::string &bundle, const std::string &resfile, const std::string &files, const std::string &shared,
          const std::string &locale) {
    setupLog();
    moveConfigToShared(files, shared);
    setupEnv(bundle, resfile, files, shared, locale);
    bool hasProfile = ::fs::exists(::fs::path(configHome(shared)) / "fcitx5" / "profile");
    // f5a and f5j need it. Not sure if f5h needs it but just do it.
    umask(007);
    StandardPath::global().syncUmask(); // Must happen after setupEnv.

    instance = std::make_unique<Instance>(0, nullptr);
    instance->setInputMethodMode(fcitx::InputMethodMode::OnScreenKeyboard);
    auto &addonMgr = instance->addonManager();
    addonMgr.registerDefaultLoader(&getStaticAddon());
    instance->initialize();
    setDefaultConfig(shared);
    migrateToAndroidDefaults(shared);
    dispatcher = std::make_unique<fcitx::EventDispatcher>();
    dispatcher->attach(&instance->eventLoop());
    fcitx_thread = std::thread([] { instance->eventLoop().exec(); });
    frontend = dynamic_cast<HarmonyFrontend *>(addonMgr.addon("harmonyfrontend"));
    ui = dynamic_cast<WebKeyboard *>(addonMgr.addon("webkeyboard"));
    if (!hasProfile) {
        // Like Google Pinyin: globe and 中/英 toggle these two. More can be added in settings.
        setInputMethods({"keyboard-us", "pinyin"});
    }
    configSignature_ = configSignature(shared);
    syncDataIfChanged(shared);
}

void focusIn(bool clientPreedit) {
    with_fcitx([clientPreedit] { frontend->focusIn(clientPreedit); });
}

void focusOut() {
    with_fcitx([] { frontend->focusOut(); });
}

InputContextState reset() {
    return with_fcitx([] { return frontend->reset(); });
}

InputContextState processKey(uint32_t unicode, int32_t keyCode, bool isRelease) {
    return with_fcitx([unicode, keyCode, isRelease] {
        auto key = ohKeyToFcitxKey(unicode, keyCode);
        return frontend->keyEvent(key, isRelease);
    });
}

void selectCandidate(int index) {
    with_fcitx([index] {
        auto ic = instance->mostRecentInputContext();
        const auto &list = ic->inputPanel().candidateList();
        if (!list)
            return;
        const auto &bulk = list->toBulk();
        if (bulk) {
            try {
                bulk->candidateFromAll(index).select(ic);
            } catch (const std::invalid_argument &e) {
                FCITX_ERROR() << "select candidate index out of range";
            }
            return;
        }
        try {
            // Engine is responsible for updating UI
            list->candidate(index).select(ic);
        } catch (const std::invalid_argument &e) {
            FCITX_ERROR() << "select candidate index out of range";
        }
    });
}

static void answerCandidateAction(ActionableCandidateList *actionableList, const CandidateWord &candidate, int index) {
    if (actionableList->hasAction(candidate)) {
        json actions = json::array();
        for (const auto &action : actionableList->candidateActions(candidate)) {
            actions.push_back({{"id", action.id()}, {"text", action.text()}});
        }
        notify_main_async(
            json{{"type", "CANDIDATE_ACTIONS"}, {"data", {{"index", index}, {"actions", actions}}}}.dump());
    }
}

void askCandidateAction(int index) {
    with_fcitx([index] {
        auto ic = instance->mostRecentInputContext();
        const auto &list = ic->inputPanel().candidateList();
        if (!list)
            return;
        auto *actionableList = list->toActionable();
        if (!actionableList) {
            return;
        }
        const auto &bulk = list->toBulk();
        if (bulk) {
            try {
                auto &candidate = bulk->candidateFromAll(index);
                answerCandidateAction(actionableList, candidate, index);
            } catch (const std::invalid_argument &e) {
                FCITX_ERROR() << "action candidate index out of range";
            }
            return;
        }
        try {
            auto &candidate = list->candidate(index);
            answerCandidateAction(actionableList, candidate, index);
        } catch (const std::invalid_argument &e) {
            FCITX_ERROR() << "action candidate index out of range";
        }
    });
}

void activateCandidateAction(int index, int id) {
    with_fcitx([=] {
        auto ic = instance->mostRecentInputContext();
        const auto &list = ic->inputPanel().candidateList();
        if (!list)
            return;
        auto *actionableList = list->toActionable();
        if (!actionableList) {
            return;
        }
        const auto &bulk = list->toBulk();
        if (bulk) {
            try {
                const auto &candidate = bulk->candidateFromAll(index);
                if (actionableList->hasAction(candidate)) {
                    actionableList->triggerAction(candidate, id);
                }
            } catch (const std::invalid_argument &e) {
                FCITX_ERROR() << "action candidate index out of range";
            }
            return;
        }
        try {
            auto &candidate = list->candidate(index);
            if (actionableList->hasAction(candidate)) {
                actionableList->triggerAction(candidate, id);
            }
        } catch (const std::invalid_argument &e) {
            FCITX_ERROR() << "action candidate index out of range";
        }
    });
}

void activateStatusAreaAction(int id) {
    with_fcitx([id] {
        if (auto *ic = instance->mostRecentInputContext()) {
            auto *action = instance->userInterfaceManager().lookupActionById(id);
            action->activate(ic);
        }
    });
}

void toggle() {
    with_fcitx([] { instance->toggle(); });
}

void setCurrentInputMethod(const std::string &inputMethod) {
    with_fcitx([&] { instance->setCurrentInputMethod(inputMethod); });
}

void scroll(int start, int count) {
    with_fcitx([=] { ui->scroll(start, count); });
}

static size_t treeSignature(const ::fs::path &root) {
    size_t signature = 0;
    std::error_code ec;
    for (::fs::recursive_directory_iterator it(root, ec), end; !ec && it != end; it.increment(ec)) {
        if (!it->is_regular_file(ec)) {
            continue;
        }
        auto time = it->last_write_time(ec).time_since_epoch().count();
        signature = signature * 31 + std::hash<std::string>{}(it->path().string()) +
                    std::hash<long long>{}(static_cast<long long>(time)) + it->file_size(ec);
    }
    return signature;
}

// Changes when the settings page writes any file of the config dir.
size_t configSignature(const std::string &shared) { return treeSignature(configHome(shared)); }

// Files the settings page edits, relative to fcitx's user data dir. The page writes them
// to a mirror in the shared dir; learned words (pinyin/user.*) stay private.
static const char *const editableData[] = {"pinyin/dictionaries", "pinyin/customphrase", "data/quickphrase.d",
                                           "punctuation"};

static ::fs::path sharedData(const std::string &shared) { return ::fs::path(shared) / "data" / "fcitx5"; }

static size_t dataSignature_ = 0;

// Copy the mirror over the private data and reload what uses it.
bool syncDataIfChanged(const std::string &shared) {
    auto signature = treeSignature(sharedData(shared));
    if (signature == dataSignature_) {
        return false;
    }
    dataSignature_ = signature;
    with_fcitx([&shared] {
        auto userData = StandardPaths::global().userDirectory(StandardPathsType::PkgData);
        for (const char *item : editableData) {
            auto from = sharedData(shared) / item;
            auto to = userData / item;
            std::error_code ec;
            ::fs::remove_all(to, ec);
            if (::fs::exists(from, ec)) {
                ::fs::create_directories(to.parent_path(), ec);
                ::fs::copy(from, to, ::fs::copy_options::recursive, ec);
                if (ec) {
                    FCITX_ERROR() << "Failed to copy " << from << ": " << ec.message();
                }
            }
        }
        auto &addonManager = instance->addonManager();
        if (auto *pinyin = addonManager.addon("pinyin")) {
            pinyin->setSubConfig("dictmanager", RawConfig{});
            pinyin->setSubConfig("customphrase", RawConfig{});
        }
        for (const char *name : {"quickphrase", "punctuation"}) {
            if (auto *addon = addonManager.addon(name)) {
                addon->reloadConfig();
            }
        }
    });
    return true;
}

// Actions the settings page can't do itself, e.g. clearuserdict and clearalldict of pinyin.
void runPinyinAction(const std::string &action) {
    with_fcitx([&action] {
        if (auto *pinyin = instance->addonManager().addon("pinyin", true)) {
            pinyin->setSubConfig(action, RawConfig{});
        }
    });
}

bool reloadConfigIfChanged(const std::string &shared, bool force) {
    auto signature = configSignature(shared);
    if (!force && signature == configSignature_) {
        return false;
    }
    with_fcitx([] {
        instance->reloadConfig();
        auto &addonManager = instance->addonManager();
        for (auto category : {AddonCategory::InputMethod, AddonCategory::Frontend, AddonCategory::Loader,
                              AddonCategory::Module, AddonCategory::UI}) {
            for (const auto &name : addonManager.addonNames(category)) {
                if (auto *addon = addonManager.addon(name)) {
                    addon->reloadConfig();
                }
            }
        }
        instance->inputMethodManager().load();
    });
    configSignature_ = signature;
    return true;
}

void save(const std::string &shared) {
    // Saving writes configs from memory: apply the settings page's changes first.
    reloadConfigIfChanged(shared);
    syncDataIfChanged(shared);
    with_fcitx([] { instance->save(); });
    configSignature_ = configSignature(shared);
    // Custom phrases pinned or deleted from candidates go back to the settings page's copy.
    std::error_code ec;
    auto userData = StandardPaths::global().userDirectory(StandardPathsType::PkgData);
    auto ours = userData / "pinyin" / "customphrase";
    auto theirs = sharedData(shared) / "pinyin" / "customphrase";
    if (::fs::exists(ours, ec) &&
        (!::fs::exists(theirs, ec) || ::fs::last_write_time(ours, ec) > ::fs::last_write_time(theirs, ec))) {
        ::fs::create_directories(theirs.parent_path(), ec);
        ::fs::copy_file(ours, theirs, ::fs::copy_options::overwrite_existing, ec);
        dataSignature_ = treeSignature(sharedData(shared));
    }
}

// From the comma key menu, like fcitx5-android.
void triggerQuickPhrase() {
    with_fcitx([] {
        auto *ic = instance->mostRecentInputContext();
        auto *quickphrase = instance->addonManager().addon("quickphrase", true);
        if (ic && quickphrase) {
            quickphrase->call<IQuickPhrase::trigger>(ic, "", "", "", "", Key{FcitxKey_None});
        }
    });
}

void triggerUnicode() {
    with_fcitx([] {
        auto *ic = instance->mostRecentInputContext();
        auto *unicode = instance->addonManager().addon("unicode", true);
        if (ic && unicode) {
            unicode->call<IUnicode::trigger>(ic);
        }
    });
}

std::string importGooglePinyinWords(const std::string &tsv) {
    return with_fcitx([&tsv]() -> std::string {
        auto *pinyin = instance->addonManager().addon("pinyin", true);
        if (!pinyin) {
            FCITX_ERROR() << "pinyin addon not available";
            return "";
        }
        return pinyin->call<IPinyinEngine::importGooglePinyinWords>(tsv);
    });
}

std::string exportGooglePinyinWords() {
    return with_fcitx([]() -> std::string {
        if (auto *pinyin = instance->addonManager().addon("pinyin")) {
            return pinyin->call<IPinyinEngine::exportGooglePinyinWords>();
        }
        // Not typed in pinyin since the keyboard started: read the saved files.
        auto dir = StandardPaths::global().userDirectory(StandardPathsType::PkgData) / "pinyin";
        return readPinyinUserWords(dir / "user.dict", dir / "user.history");
    });
}

std::string importGooglePinyinLearned(const std::string &typed, const std::string &english) {
    return with_fcitx([&typed, &english]() -> std::string {
        auto *pinyin = instance->addonManager().addon("pinyin", true);
        if (!pinyin) {
            FCITX_ERROR() << "pinyin addon not available";
            return "";
        }
        return pinyin->call<IPinyinEngine::importGooglePinyinLearned>(typed, english);
    });
}

std::string exportLearnedEnglish() {
    return with_fcitx([]() -> std::string {
        if (auto *pinyin = instance->addonManager().addon("pinyin")) {
            return pinyin->call<IPinyinEngine::exportLearnedEnglish>();
        }
        // Not typed in pinyin since the keyboard started: the saved file has the same format.
        auto path = StandardPaths::global().userDirectory(StandardPathsType::PkgData) / "pinyin" / "user.english";
        std::ifstream in(path);
        return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    });
}

std::string readPinyinUserWords(const std::string &dictPath, const std::string &historyPath) {
    try {
        return googlepinyin::toTsv(googlepinyin::readUserWords(dictPath, historyPath));
    } catch (const std::exception &e) {
        FCITX_ERROR() << "Failed to read pinyin user words: " << e.what();
        return "";
    }
}
} // namespace fcitx
