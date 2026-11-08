// Settings for the main app, ported from fcitx5-android's native-lib.cpp config API.
// The main app runs its own Instance for config descriptions and edits. Config files are
// in the dir shared with the input method, which reloads them when they change.
#include "settings.h"
#include <fcitx-config/configuration.h>
#include <fcitx-config/rawconfig.h>
#include <fcitx/addoninfo.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/globalconfig.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputmethodentry.h>
#include <fcitx/inputmethodgroup.h>
#include <fcitx/inputmethodmanager.h>
#include <fcitx/instance.h>
#include <nlohmann/json.hpp>
#include <set>
#include <sys/stat.h>
#include <unordered_set>
#include "fcitx.h"

using json = nlohmann::json;

// Same static addons as the input method, defined in fcitx.cpp.
fcitx::StaticAddonRegistry &getStaticAddon();

namespace fcitx {
extern std::unique_ptr<Instance> instance;

void initSettings(const std::string &bundle, const std::string &resfile, const std::string &files,
                  const std::string &shared, const std::string &locale) {
    if (instance) {
        return;
    }
    setupLog();
    setupEnv(bundle, resfile, files, shared, locale);
    umask(007);
    instance = std::make_unique<Instance>(0, nullptr);
    instance->setInputMethodMode(InputMethodMode::OnScreenKeyboard);
    instance->addonManager().registerDefaultLoader(&getStaticAddon());
    instance->initialize();
}

static json toJson(const RawConfig &config) {
    json subItems = json::array();
    config.visitSubItems([&subItems](const RawConfig &item, const std::string &) {
        subItems.push_back(toJson(item));
        return true;
    });
    return {{"name", config.name()}, {"value", config.value()}, {"subItems", subItems}};
}

static void fromJson(RawConfig &config, const json &j) {
    config.setValue(j.value("value", ""));
    if (auto it = j.find("subItems"); it != j.end() && it->is_array()) {
        for (const auto &item : *it) {
            fromJson(*config.get(item.value("name", ""), true), item);
        }
    }
}

// {cfg, desc} like fcitx5-android's mergeConfigDesc.
static std::string dumpConfig(const Configuration &configuration) {
    RawConfig topLevel;
    configuration.save(*topLevel.get("cfg", true));
    configuration.dumpDescription(*topLevel.get("desc", true));
    return toJson(topLevel).dump();
}

static AddonInstance *configurableAddon(const std::string &name) {
    const auto *info = instance->addonManager().addonInfo(name);
    if (!info || !info->isConfigurable()) {
        return nullptr;
    }
    return instance->addonManager().addon(name, true);
}

// uri: "global", "addon/<name>", "addon/<name>/<sub config path>" or "im/<name>".
std::string getConfig(const std::string &uri) {
    if (uri == "global") {
        return dumpConfig(instance->globalConfig().config());
    }
    if (uri.starts_with("addon/")) {
        auto rest = uri.substr(6);
        auto slash = rest.find('/');
        auto *addon = configurableAddon(rest.substr(0, slash));
        if (!addon) {
            return "";
        }
        const auto *configuration =
            slash == std::string::npos ? addon->getConfig() : addon->getSubConfig(rest.substr(slash + 1));
        return configuration ? dumpConfig(*configuration) : "";
    }
    if (uri.starts_with("im/")) {
        auto name = uri.substr(3);
        const auto *entry = instance->inputMethodManager().entry(name);
        if (!entry || !entry->isConfigurable()) {
            return "";
        }
        auto *engine = instance->inputMethodEngine(name);
        if (!engine) {
            return "";
        }
        const auto *configuration = engine->getConfigForInputMethod(*entry);
        return configuration ? dumpConfig(*configuration) : "";
    }
    return "";
}

void setConfig(const std::string &uri, const std::string &value) {
    RawConfig config;
    fromJson(config, json::parse(value));
    if (uri == "global") {
        instance->globalConfig().load(config, true);
        if (instance->globalConfig().safeSave()) {
            instance->reloadConfig();
        }
        return;
    }
    if (uri.starts_with("addon/")) {
        auto rest = uri.substr(6);
        auto slash = rest.find('/');
        auto *addon = configurableAddon(rest.substr(0, slash));
        if (!addon) {
            return;
        }
        if (slash == std::string::npos) {
            addon->setConfig(config);
        } else {
            addon->setSubConfig(rest.substr(slash + 1), config);
        }
        return;
    }
    if (uri.starts_with("im/")) {
        auto name = uri.substr(3);
        const auto *entry = instance->inputMethodManager().entry(name);
        auto *engine = instance->inputMethodEngine(name);
        if (entry && entry->isConfigurable() && engine) {
            engine->setConfigForInputMethod(*entry, config);
        }
    }
}

static json addonJson(const AddonInfo &info, bool enabled) {
    return {{"uniqueName", info.uniqueName()},
            {"name", info.name().match("system")},
            {"comment", info.comment().match("system")},
            {"category", static_cast<int>(info.category())},
            {"configurable", info.isConfigurable()},
            {"defaultEnabled", info.isDefaultEnabled()},
            {"onDemand", info.onDemand()},
            {"enabled", enabled}};
}

std::string getAddons() {
    auto &globalConfig = instance->globalConfig();
    auto &addonManager = instance->addonManager();
    const auto &enabledAddons = globalConfig.enabledAddons();
    const std::unordered_set<std::string> enabledSet(enabledAddons.begin(), enabledAddons.end());
    const auto &disabledAddons = globalConfig.disabledAddons();
    const std::unordered_set<std::string> disabledSet(disabledAddons.begin(), disabledAddons.end());
    json addons = json::array();
    for (auto category : {AddonCategory::InputMethod, AddonCategory::Frontend, AddonCategory::Loader,
                          AddonCategory::Module, AddonCategory::UI}) {
        for (const auto &name : addonManager.addonNames(category)) {
            const auto *info = addonManager.addonInfo(name);
            if (!info) {
                continue;
            }
            bool enabled = info->isDefaultEnabled();
            if (disabledSet.contains(info->uniqueName())) {
                enabled = false;
            } else if (enabledSet.contains(info->uniqueName())) {
                enabled = true;
            }
            addons.push_back(addonJson(*info, enabled));
        }
    }
    return addons.dump();
}

void setAddonState(const std::string &name, bool enabled) {
    auto &globalConfig = instance->globalConfig();
    const auto *info = instance->addonManager().addonInfo(name);
    if (!info) {
        return;
    }
    const auto &enabledAddons = globalConfig.enabledAddons();
    std::set<std::string> enabledSet(enabledAddons.begin(), enabledAddons.end());
    const auto &disabledAddons = globalConfig.disabledAddons();
    std::set<std::string> disabledSet(disabledAddons.begin(), disabledAddons.end());
    const auto &uniqueName = info->uniqueName();
    enabledSet.erase(uniqueName);
    disabledSet.erase(uniqueName);
    if (enabled != info->isDefaultEnabled()) {
        (enabled ? enabledSet : disabledSet).insert(uniqueName);
    }
    globalConfig.setEnabledAddons({enabledSet.begin(), enabledSet.end()});
    globalConfig.setDisabledAddons({disabledSet.begin(), disabledSet.end()});
    globalConfig.safeSave();
}

static json inputMethodJson(const InputMethodEntry &entry) {
    return {{"uniqueName", entry.uniqueName()},      {"name", entry.name()},   {"nativeName", entry.nativeName()},
            {"languageCode", entry.languageCode()},  {"label", entry.label()}, {"addon", entry.addon()},
            {"configurable", entry.isConfigurable()}};
}

std::string availableInputMethods() {
    json entries = json::array();
    instance->inputMethodManager().foreachEntries([&entries](const InputMethodEntry &entry) {
        entries.push_back(inputMethodJson(entry));
        return true;
    });
    return entries.dump();
}

std::string enabledInputMethods() {
    json names = json::array();
    for (const auto &item : instance->inputMethodManager().currentGroup().inputMethodList()) {
        names.push_back(item.name());
    }
    return names.dump();
}

void setEnabledInputMethods(const std::string &names) {
    auto &imMgr = instance->inputMethodManager();
    InputMethodGroup group(imMgr.currentGroup().name());
    group.setDefaultLayout("us");
    for (const auto &name : json::parse(names)) {
        group.inputMethodList().emplace_back(name.get<std::string>());
    }
    imMgr.setGroup(std::move(group));
    imMgr.save();
}
} // namespace fcitx
