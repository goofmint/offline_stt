import 'package:flutter/services.dart' show PlatformException;
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

import 'error_code_mapping.dart';

/// `package:flutter/services.dart`の[PlatformException]から
/// [TranscribeException]への変換(Issue #56)。
///
/// Windowsでこの型が届くのはHostApiメソッド(`checkModel` /
/// `downloadModel` / `transcribeFile` / `cancel`)の呼び出しが
/// ネイティブ側で`FlutterError`を返した場合である。ストリームのエラーは
/// EventChannelではなく`OfflineSttStreamCallbackApi.onStreamError`で届く
/// ため`PlatformException`にはならず、`stream_router.dart`が
/// `mapNativeErrorCode`を直接呼ぶ(`error_code_mapping.dart`冒頭コメント
/// 参照)。
///
/// このファイルを`error_code_mapping.dart`から分けている理由は
/// `offline_stt_darwin`の同名ファイルと同じで、`error_code_mapping.dart`を
/// `flutter`パッケージに依存しない純粋ロジックに保ち、`dart test`
/// (melos run test)で単体テストできるようにするためである。
TranscribeException mapPlatformException(PlatformException exception) {
  return mapNativeErrorCode(exception.code, exception.message);
}
