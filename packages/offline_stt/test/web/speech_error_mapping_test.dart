// ブラウザAPIに依存しない純粋なエラーコード文字列->TranscribeException
// 写像のみを検証する。切り分け方針は
// lib/src/speech_error_mapping.dart 冒頭コメント、および
// docs/e2e/E2E_CHECKLIST_WEB.md を参照。

import 'package:offline_stt/src/common.dart';
import 'package:offline_stt/src/web/speech_error_mapping.dart';
import 'package:test/test.dart';

void main() {
  group('mapSpeechErrorCode', () {
    test('language-not-supported は LocaleUnsupportedException へ写像する', () {
      expect(
        mapSpeechErrorCode('language-not-supported', ''),
        isA<LocaleUnsupportedException>(),
      );
    });

    test('network はコードを保持した PlatformException_ になる(NFR-2の兆候)', () {
      final result = mapSpeechErrorCode('network', 'boom');
      expect(result, isA<PlatformException_>());
      expect((result as PlatformException_).code, 'network');
      expect(result.message, 'boom');
    });

    test('aborted はエラー名から推測せずそのままPlatformException_になる', () {
      final result = mapSpeechErrorCode('aborted', '');
      expect(result, isA<PlatformException_>());
      expect((result as PlatformException_).code, 'aborted');
    });

    test('未対応のコードもすべてPlatformException_としてそのまま伝わる', () {
      final result = mapSpeechErrorCode('no-speech', 'msg');
      expect(result, isA<PlatformException_>());
      expect((result as PlatformException_).code, 'no-speech');
      expect(result.message, 'msg');
    });
  });
}
