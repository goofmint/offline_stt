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
      const progress = DownloadProgress(fraction: null, completed: false);
      expect(progress.fraction, isNull);
      expect(progress.completed, isFalse);
    });

    test('等価性はフィールド値で判定される', () {
      const a = DownloadProgress(fraction: 0.5, completed: false);
      const b = DownloadProgress(fraction: 0.5, completed: false);
      const c = DownloadProgress(fraction: 0.6, completed: false);
      const d = DownloadProgress(fraction: 0.5, completed: true);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('toStringにフィールド値が含まれる', () {
      const progress = DownloadProgress(fraction: 0.25, completed: false);
      expect(progress.toString(), contains('0.25'));
    });
  });

  group('TranscribeRequest', () {
    test('pathとlocaleを保持する', () {
      const request = TranscribeRequest(path: '/tmp/a.wav', locale: 'ja-JP');
      expect(request.path, '/tmp/a.wav');
      expect(request.locale, 'ja-JP');
    });

    test('等価性はフィールド値で判定される', () {
      const a = TranscribeRequest(path: '/a.wav', locale: 'ja-JP');
      const b = TranscribeRequest(path: '/a.wav', locale: 'ja-JP');
      const c = TranscribeRequest(path: '/a.wav', locale: 'en-US');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
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
