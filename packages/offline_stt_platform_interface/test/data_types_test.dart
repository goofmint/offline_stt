import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  group('ModelState', () {
    test('4値を持つ(design.md §2.2)', () {
      expect(ModelState.values, hasLength(4));
      expect(
        ModelState.values,
        containsAll(<ModelState>[
          ModelState.available,
          ModelState.downloadable,
          ModelState.downloading,
          ModelState.unavailable,
        ]),
      );
    });
  });

  group('DownloadProgress', () {
    test('fractionにnullを許容する(不定進捗)', () {
      final progress = DownloadProgress(fraction: null, completed: false);
      expect(progress.fraction, isNull);
      expect(progress.completed, isFalse);
    });

    test('等価性はフィールド値で判定される', () {
      final a = DownloadProgress(fraction: 0.5, completed: false);
      final b = DownloadProgress(fraction: 0.5, completed: false);
      final c = DownloadProgress(fraction: 0.6, completed: false);
      final d = DownloadProgress(fraction: 0.5, completed: true);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('toStringにフィールド値が含まれる', () {
      final progress = DownloadProgress(fraction: 0.25, completed: false);
      expect(progress.toString(), contains('0.25'));
    });

    test('fractionが範囲外ならArgumentErrorを投げる', () {
      // assert はリリースビルドで無効化されるため、実行時に検証する。
      expect(
        () => DownloadProgress(fraction: -0.1, completed: false),
        throwsArgumentError,
      );
      expect(
        () => DownloadProgress(fraction: 1.1, completed: false),
        throwsArgumentError,
      );
      expect(
        () => DownloadProgress(fraction: double.nan, completed: false),
        throwsArgumentError,
      );
    });

    test('fractionの境界値0.0と1.0は許容する', () {
      expect(DownloadProgress(fraction: 0.0, completed: false).fraction, 0.0);
      expect(DownloadProgress(fraction: 1.0, completed: true).fraction, 1.0);
    });
  });

  group('TranscribeRequest', () {
    test('pathとlocaleを保持する', () {
      final request = TranscribeRequest(path: '/tmp/a.wav', locale: 'ja-JP');
      expect(request.path, '/tmp/a.wav');
      expect(request.locale, 'ja-JP');
    });

    test('playbackRateの既定値は1.0である(design.md §2.2)', () {
      final request = TranscribeRequest(path: '/tmp/a.wav', locale: 'ja-JP');
      expect(request.playbackRate, 1.0);
    });

    test('playbackRateを明示指定できる', () {
      final request = TranscribeRequest(
        path: '/tmp/a.wav',
        locale: 'ja-JP',
        playbackRate: 1.5,
      );
      expect(request.playbackRate, 1.5);
    });

    test('playbackRateが0以下ならArgumentErrorを投げる', () {
      // assert はリリースビルドで無効化されるため、実行時に検証する。
      expect(
        () => TranscribeRequest(
          path: '/tmp/a.wav',
          locale: 'ja-JP',
          playbackRate: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => TranscribeRequest(
          path: '/tmp/a.wav',
          locale: 'ja-JP',
          playbackRate: -1.0,
        ),
        throwsArgumentError,
      );
    });

    test('playbackRateが有限値でなければArgumentErrorを投げる', () {
      expect(
        () => TranscribeRequest(
          path: '/tmp/a.wav',
          locale: 'ja-JP',
          playbackRate: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => TranscribeRequest(
          path: '/tmp/a.wav',
          locale: 'ja-JP',
          playbackRate: double.infinity,
        ),
        throwsArgumentError,
      );
    });

    test('等価性はフィールド値で判定される(playbackRate含む)', () {
      final a = TranscribeRequest(path: '/a.wav', locale: 'ja-JP');
      final b = TranscribeRequest(path: '/a.wav', locale: 'ja-JP');
      final c = TranscribeRequest(path: '/a.wav', locale: 'en-US');
      final d = TranscribeRequest(
        path: '/a.wav',
        locale: 'ja-JP',
        playbackRate: 1.5,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });
  });

  group('TranscriptSegment', () {
    test('isFinalでpartial/finalを区別する', () {
      const partial = TranscriptSegment(text: 'こんに', isFinal: false);
      const finalSegment = TranscriptSegment(text: 'こんにちは', isFinal: true);

      expect(partial.isFinal, isFalse);
      expect(finalSegment.isFinal, isTrue);
    });

    test('等価性はフィールド値で判定される', () {
      const a = TranscriptSegment(text: 'x', isFinal: true);
      const b = TranscriptSegment(text: 'x', isFinal: true);
      const c = TranscriptSegment(text: 'x', isFinal: false);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
