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

// offline_stt のWindowsネイティブ側エントリポイント(雛形)。
//
// Pigeonスキーマ確定(design.md §2.3)後、Windows AI Speech Recognition
// (BatchRecognition.RecognizeFromFile)との連携をここに実装する
// (design.md §4.4、M4)。
FLUTTER_PLUGIN_EXPORT void OfflineSttWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_OFFLINE_STT_WINDOWS_PLUGIN_C_API_H_
