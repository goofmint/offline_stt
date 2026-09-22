import 'dart:io';

import 'android/offline_stt_android.dart';
import 'common.dart';
import 'darwin/offline_stt_darwin.dart';

/// 非Webコンパイルターゲット向けのバックエンド生成(design.md §1)。
///
/// 実行中のOSに対応する実装を返す。サポート対象外のOSでは既定の実装へ
/// フォールバックせず [UnsupportedError] を送出する。「とりあえず動く」
/// 既定値は不具合の温床になるためである(requirements.md §6・NFR-4 は
/// サポート対象を Android / iOS / macOS / Web に限定している)。
OfflineTranscriberPlatform createBackend() {
  if (Platform.isAndroid) {
    return OfflineSttAndroid();
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return OfflineSttDarwin();
  }
  throw UnsupportedError(
    'offline_stt は Android / iOS / macOS / Web のみをサポートする。'
    '現在のプラットフォーム(${Platform.operatingSystem})には実装が無い。',
  );
}
