#include "fcitx.h"
#include <fcitx-utils/event.h>
#include <fcitx-utils/eventdispatcher.h>
#include <fcitx-utils/standardpath.h>
#include <fcitx-utils/standardpaths.h>
#include <fstream>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/rawconfig.h>
#include <fcitx/action.h>
#include <fcitx/addonmanager.h>
#include <fcitx/globalconfig.h>
#include <fcitx/instance.h>
#include <fcitx/userinterfacemanager.h>
#include <thread>
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

void setupEnv(const std::string &bundle, const std::string &resfile, const std::string &files,
              const std::string &locale) {
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
    // User config and data (pinyin user.dict and user.history) live in the app's files dir,
    // which the main ability shares, e.g. to export user words.
    ::fs::path filesPath = files;
    std::string xdg_config_home = filesPath / "config";
    std::string xdg_data_home = filesPath / "data";
    std::string xdg_cache_home = filesPath / "cache";
    setenv("XDG_CONFIG_HOME", xdg_config_home.c_str(), 1);
    setenv("XDG_DATA_HOME", xdg_data_home.c_str(), 1);
    setenv("XDG_CACHE_HOME", xdg_cache_home.c_str(), 1);
    // isAndroid() is true on HarmonyOS, so fcitx takes the UI language from here.
    setenv("FCITX_LOCALE", locale.c_str(), 1);
}

// Google Pinyin starts in Chinese, like the fcitx5-android fork. Other defaults come
// from fcitx's Android branch (isAndroid() is true on HarmonyOS).
static void setDefaultConfig(const std::string &files) {
    ::fs::path configDir = ::fs::path(files) / "config" / "fcitx5";
    if (!::fs::exists(configDir / "config")) {
        RawConfig raw;
        raw.setValueByPath("Behavior/ActiveByDefault", "True");
        instance->globalConfig().load(raw, true);
        instance->globalConfig().safeSave();
    }
}

void init(const std::string &bundle, const std::string &resfile, const std::string &files, const std::string &locale) {
    setupLog();
    setupEnv(bundle, resfile, files, locale);
    // f5a and f5j need it. Not sure if f5h needs it but just do it.
    umask(007);
    StandardPath::global().syncUmask(); // Must happen after setupEnv.

    instance = std::make_unique<Instance>(0, nullptr);
    instance->setInputMethodMode(fcitx::InputMethodMode::OnScreenKeyboard);
    auto &addonMgr = instance->addonManager();
    addonMgr.registerDefaultLoader(&getStaticAddon());
    instance->initialize();
    setDefaultConfig(files);
    dispatcher = std::make_unique<fcitx::EventDispatcher>();
    dispatcher->attach(&instance->eventLoop());
    fcitx_thread = std::thread([] { instance->eventLoop().exec(); });
    frontend = dynamic_cast<HarmonyFrontend *>(addonMgr.addon("harmonyfrontend"));
    ui = dynamic_cast<WebKeyboard *>(addonMgr.addon("webkeyboard"));
    // Google Pinyin has no other input methods: globe and 中/英 only toggle these two.
    setInputMethods({"keyboard-us", "pinyin"});
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

void save() {
    with_fcitx([] { instance->save(); });
}

static void mergeRawConfig(RawConfig &to, const RawConfig &from) {
    for (const auto &name : from.subItems()) {
        auto item = from.get(name);
        if (!item) {
            continue;
        }
        auto target = to.get(name, true);
        if (item->subItemsSize() == 0) {
            target->setValue(item->value());
        } else {
            mergeRawConfig(*target, *item);
        }
    }
}

void applyPinyinConfig(const std::string &path) {
    with_fcitx([&path] {
        std::ifstream in(path);
        if (!in) {
            return;
        }
        RawConfig changes;
        readFromIni(changes, in);
        RawConfig config;
        readAsIni(config, "conf/pinyin.conf");
        mergeRawConfig(config, changes);
        safeSaveAsIni(config, "conf/pinyin.conf");
        // Only when loaded: otherwise it reads the config when loading.
        if (auto *pinyin = instance->addonManager().addon("pinyin")) {
            pinyin->reloadConfig();
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

std::string readPinyinUserWords(const std::string &dictPath, const std::string &historyPath) {
    try {
        return googlepinyin::toTsv(googlepinyin::readUserWords(dictPath, historyPath));
    } catch (const std::exception &e) {
        FCITX_ERROR() << "Failed to read pinyin user words: " << e.what();
        return "";
    }
}
} // namespace fcitx
