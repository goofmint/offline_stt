#ifndef FLUTTER_PLUGIN_OFFLINE_STT_WINDOWS_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_OFFLINE_STT_WINDOWS_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// offline_stt のWindowsネイティブ側エントリポイント(Issue #52)。
//
// 実装本体は offline_stt_windows_plugin.cpp。Pigeon生成の
// `OfflineSttHostApi` / `OfflineSttStreamCallbackApi`(design.md §2.3)と、
// Windows AI Speech Recognition 連携(design.md §4.4)を結びつける。
FLUTTER_PLUGIN_EXPORT void OfflineSttWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_OFFLINE_STT_WINDOWS_PLUGIN_C_API_H_
