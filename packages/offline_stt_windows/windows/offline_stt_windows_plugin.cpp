#include "include/offline_stt_windows/offline_stt_windows_plugin_c_api.h"

// Pigeon生成コード(pigeons/offline_stt_windows.dart から生成、Issue #24)。
// `OfflineSttHostApi`(HostApi)・`OfflineSttStreamCallbackApi`(FlutterApi
// コールバック)はここで定義されている。design.md §4.4 のとおり、
// Windows実装(C++/WinRT)はPigeonのC++ EventChannel未対応のため
// FlutterApiコールバックでストリームを代替する
// (pigeons/offline_stt_windows.dart 冒頭コメント参照)。
#include "pigeon.g.h"

// TODO(M4): C++/WinRT実装本体(design.md §4.4)をここに実装する。
// `offline_stt_windows::OfflineSttHostApi` を継承したクラスを実装し、
// `SetUp()` でregistrarに登録する。ストリーム配信には
// `offline_stt_windows::OfflineSttStreamCallbackApi` を利用する。

void OfflineSttWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  // TODO(M4): Pigeon生成のAPI実装をここに接続する。
}
