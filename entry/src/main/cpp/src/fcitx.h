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

void init(const std::string &bundle, const std::string &resfile, const std::string &files);
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
void save();
// Apply conf/pinyin.conf written by the main app.
void reloadPinyinConfig();
// Google Pinyin user words, UTF-8 lines of "word\tpin'yin\tcount".
// Merge into the running pinyin engine. Returns "added existing invalid".
std::string importGooglePinyinWords(const std::string &tsv);
// Read user words from saved pinyin user data files, without a running engine.
std::string readPinyinUserWords(const std::string &dictPath, const std::string &historyPath);
} // namespace fcitx
