#pragma once

#include <string>

// Config API for the main app's settings, see settings.cpp. Values are JSON.
namespace fcitx {
void initSettings(const std::string &bundle, const std::string &resfile, const std::string &files,
                  const std::string &shared, const std::string &locale);
// {cfg, desc} as RawConfig JSON ({name, value, subItems}), or "" if not configurable.
std::string getConfig(const std::string &uri);
void setConfig(const std::string &uri, const std::string &value);
std::string getAddons();
void setAddonState(const std::string &name, bool enabled);
std::string availableInputMethods();
std::string enabledInputMethods();
void setEnabledInputMethods(const std::string &names);
} // namespace fcitx
