set(GOOGLEPINYIN_DIR "${PROJECT_SOURCE_DIR}/fcitx5-chinese-addons/im/pinyin")

add_library(fcitx SHARED
    fcitx.cpp
    keycode.cpp
    inputmethod.cpp
    settings.cpp
    "${GOOGLEPINYIN_DIR}/googlepinyin_userdata.cpp"
)
target_include_directories(fcitx PRIVATE "${GOOGLEPINYIN_DIR}")
target_link_libraries(fcitx Fcitx5::Core LibIME::Pinyin libhilog_ndk.z.so libace_napi.z.so)

fcitx5_import_addons(fcitx
    REGISTRY_VARNAME getStaticAddon
    ADDONS harmonyfrontend webkeyboard keyboard
)
