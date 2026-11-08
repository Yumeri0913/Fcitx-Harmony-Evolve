#pragma once

#include <string>
#include <cstdint>
#include "napi/native_api.h"

extern napi_threadsafe_function tsfn;
void notify_main_async(std::string str);

namespace fcitx {
struct InputContextState {
    std::string commit;
    std::string preedit;
    int cursorPos;
    bool accepted;
};

void setupLog();
// files is the process's private files dir, shared the dir shared by the app and the input method.
void setupEnv(const std::string &bundle, const std::string &resfile, const std::string &files,
              const std::string &shared, const std::string &locale);
// locale is like zh_CN, for translated names.
void init(const std::string &bundle, const std::string &resfile, const std::string &files, const std::string &shared,
          const std::string &locale);
void focusIn(bool clientPreedit);
void focusOut();
InputContextState reset();
InputContextState processKey(uint32_t unicode, int32_t keyCode, bool isRelease);
void selectCandidate(int index);
void askCandidateAction(int index);
void activateCandidateAction(int index, int id);
void activateStatusAreaAction(int id);
void toggle();
void setCurrentInputMethod(const std::string &inputMethod);
void scroll(int start, int count);
// Reload config if the settings page changed it. Returns whether it did.
bool reloadConfigIfChanged(const std::string &shared);
void save(const std::string &shared);
// Google Pinyin user words, UTF-8 lines of "word\tpin'yin\tcount".
// Merge into the running pinyin engine. Returns "added existing invalid".
std::string importGooglePinyinWords(const std::string &tsv);
// All pinyin user words with usage counts.
std::string exportGooglePinyinWords();
// Read user words from saved pinyin user data files, without a running engine.
std::string readPinyinUserWords(const std::string &dictPath, const std::string &historyPath);
} // namespace fcitx
