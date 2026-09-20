import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:test/test.dart';

/// sealed class の網羅的switch式が成立することを確認するためのヘルパー。
/// 分岐漏れがあるとコンパイル時に検出される(non_exhaustive_switch)。
String _describe(TranscribeException exception) {
  return switch (exception) {
    ModelUnavailableException() => 'model-unavailable',
    LocaleUnsupportedException() => 'locale-unsupported',
    DecodeFailedException() => 'decode-failed',
    DeviceUnsupportedException() => 'device-unsupported',
    CancelledException() => 'cancelled',
    PlatformException_() => 'platform-error',
  };
}

void main() {
  group('TranscribeException', () {
    test('sealed classとして網羅的に分岐できる', () {
      expect(_describe(const ModelUnavailableException()), 'model-unavailable');
      expect(
        _describe(const LocaleUnsupportedException()),
        'locale-unsupported',
      );
      expect(_describe(const DecodeFailedException()), 'decode-failed');
      expect(
        _describe(const DeviceUnsupportedException()),
        'device-unsupported',
      );
      expect(_describe(const CancelledException()), 'cancelled');
      expect(
        _describe(const PlatformException_(code: 'E1', message: 'boom')),
        'platform-error',
      );
    });

    test('全てTranscribeExceptionかつExceptionである', () {
      const exceptions = <TranscribeException>[
        ModelUnavailableException(),
        LocaleUnsupportedException(),
        DecodeFailedException(),
        DeviceUnsupportedException(),
        CancelledException(),
        PlatformException_(code: 'E1'),
      ];
      for (final exception in exceptions) {
        expect(exception, isA<Exception>());
      }
    });

    test('toStringはクラス名を含む', () {
      expect(
        const ModelUnavailableException().toString(),
        'ModelUnavailableException',
      );
      expect(
        const LocaleUnsupportedException().toString(),
        'LocaleUnsupportedException',
      );
      expect(const DecodeFailedException().toString(), 'DecodeFailedException');
      expect(
        const DeviceUnsupportedException().toString(),
        'DeviceUnsupportedException',
      );
      expect(const CancelledException().toString(), 'CancelledException');
    });

    test('PlatformException_ のtoStringはcode/messageを含む', () {
      const withMessage = PlatformException_(code: 'E1', message: 'boom');
      expect(
        withMessage.toString(),
        'PlatformException_(code: E1, message: boom)',
      );

      const withoutMessage = PlatformException_(code: 'E2');
      expect(withoutMessage.message, isNull);
      expect(
        withoutMessage.toString(),
        'PlatformException_(code: E2, message: null)',
      );
    });

    test('PlatformException_ の等価性はcode/messageで判定される', () {
      const a = PlatformException_(code: 'E1', message: 'boom');
      const b = PlatformException_(code: 'E1', message: 'boom');
      const c = PlatformException_(code: 'E1', message: 'other');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
