// ネイティブ(darwin/Classes/DarwinTranscribeError.swiftのwireCode)に依存
// しない純粋なエラーコード文字列->TranscribeException写像のみを検証する。
// 切り分け方針は lib/src/error_code_mapping.dart 冒頭コメントを参照。

import 'package:offline_stt_darwin/src/error_code_mapping.dart';
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('mapNativeErrorCode', () {
    test('modelUnavailable は ModelUnavailableException へ写像する', () {
      expect(
        mapNativeErrorCode('modelUnavailable', null),
        isA<ModelUnavailableException>(),
      );
    });

    test('localeUnsupported は LocaleUnsupportedException へ写像する', () {
      expect(
        mapNativeErrorCode('localeUnsupported', null),
        isA<LocaleUnsupportedException>(),
      );
    });

    test('decodeFailed は DecodeFailedException へ写像する', () {
      expect(
        mapNativeErrorCode('decodeFailed', null),
        isA<DecodeFailedException>(),
      );
    });

    test('deviceUnsupported は DeviceUnsupportedException へ写像する', () {
      expect(
        mapNativeErrorCode('deviceUnsupported', null),
        isA<DeviceUnsupportedException>(),
      );
    });

    test('cancelled は CancelledException へ写像する', () {
      expect(mapNativeErrorCode('cancelled', null), isA<CancelledException>());
    });

    test('platformError はコードとメッセージを保持した PlatformException_ になる', () {
      final result = mapNativeErrorCode('platformError', 'boom');
      expect(result, isA<PlatformException_>());
      expect((result as PlatformException_).code, 'platformError');
      expect(result.message, 'boom');
    });

    test('未知のcodeもフォールバックで丸めずそのままPlatformException_として伝わる', () {
      final result = mapNativeErrorCode('some-unknown-code', 'msg');
      expect(result, isA<PlatformException_>());
      expect((result as PlatformException_).code, 'some-unknown-code');
      expect(result.message, 'msg');
    });
  });
}
