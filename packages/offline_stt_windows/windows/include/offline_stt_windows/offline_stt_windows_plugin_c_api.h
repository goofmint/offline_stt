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

// Native entry point of offline_stt on Windows (Issue #52).
//
// The implementation lives in offline_stt_windows_plugin.cpp. It wires up the
// Pigeon-generated `OfflineSttHostApi` / `OfflineSttStreamCallbackApi`
// (design.md section 2.3) with the Windows AI Speech Recognition integration
// (design.md section 4.4).
//
// NOTE: This header is ASCII-only on purpose. It is included by the consuming
// application's runner, which this plugin does not control. MSVC decodes a
// BOM-less source with the system ANSI code page, so non-ASCII characters here
// would emit warning C4819 and, because Flutter's runner treats warnings as
// errors, break the build of every app on a non-UTF-8 locale (verified on a
// Japanese-locale Windows 11 machine). Japanese comments are fine in the
// plugin's own sources, which are compiled with /utf-8 (see CMakeLists.txt).
FLUTTER_PLUGIN_EXPORT void OfflineSttWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_OFFLINE_STT_WINDOWS_PLUGIN_C_API_H_
