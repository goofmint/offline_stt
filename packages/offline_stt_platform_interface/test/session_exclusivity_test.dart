import 'dart:async';

import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:test/test.dart';

import 'fakes/fake_offline_transcriber_platform.dart';

const _request = TranscribeRequest(path: '/tmp/a.wav', locale: 'ja-JP');

/// マイクロタスクを1周させ、`StreamController.onListen` 等の非同期コール
/// バックが実行されるのを待つ。
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// design.md §3 のセッション状態遷移
/// (idle→decoding→recognizing→done|cancelled|error)と、
/// 「同時セッションはv1では1本に制限。2本目の開始はStateError」という
/// セッション排他規則を、共有ガード `TranscribeSessionGuard`
/// (lib/src/session_guard.dart)経由で検証する。
void main() {
  group('セッション状態遷移(design.md §3)', () {
    test('idle → decoding → recognizing → done の正常系', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.available,
      );
      expect(fake.sessionPhase, SessionPhase.idle);

      final stream = fake.transcribeFile(_request);
      final events = <TranscriptSegment>[];
      final done = Completer<void>();
      final sub = stream.listen(events.add, onDone: done.complete);

      // 購読した時点でセッションが開始し decoding に遷移する。
      await _pump();
      expect(fake.sessionPhase, SessionPhase.decoding);

      fake.startRecognizing();
      expect(fake.sessionPhase, SessionPhase.recognizing);

      fake.emitSegment(const TranscriptSegment(text: 'こんにちは', isFinal: true));
      fake.completeSession();

      await done.future;
      expect(fake.sessionPhase, SessionPhase.done);
      expect(events, [const TranscriptSegment(text: 'こんにちは', isFinal: true)]);

      await sub.cancel();
    });

    test('セッションがcancelledで終わる経路', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.available,
      );

      final stream = fake.transcribeFile(_request);
      final sub = stream.listen((_) {});
      await _pump();
      expect(fake.sessionPhase, SessionPhase.decoding);

      fake.startRecognizing();
      await sub.cancel();
      await _pump();

      expect(fake.sessionPhase, SessionPhase.cancelled);
    });

    test('セッションがerrorで終わる経路', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.available,
      );

      final stream = fake.transcribeFile(_request);
      final expectation = expectLater(
        stream,
        emitsInOrder(<Object>[
          emitsError(isA<PlatformException_>()),
          emitsDone,
        ]),
      );

      await _pump();
      fake.startRecognizing();
      fake.errorSession(const PlatformException_(code: 'RECOGNITION_FAILED'));

      await expectation;
      expect(fake.sessionPhase, SessionPhase.error);
    });
  });

  group('セッション排他(design.md §3: 同時セッションは1本に制限)', () {
    test('1本目の実行中に2本目を開始するとStateErrorになる', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.available,
      );

      final stream1 = fake.transcribeFile(_request);
      final sub1 = stream1.listen((_) {});
      await _pump();
      expect(fake.sessionPhase, SessionPhase.decoding);

      final stream2 = fake.transcribeFile(_request);
      await expectLater(stream2, emitsError(isA<StateError>()));

      // 1本目は2本目の失敗に影響されず引き続き実行中である。
      expect(fake.sessionPhase, SessionPhase.decoding);

      fake.completeSession();
      await sub1.cancel();
    });

    test('1本目が正常終了した後は2本目を開始できる', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.available,
      );

      final stream1 = fake.transcribeFile(_request);
      final expectation1 = expectLater(stream1, emitsDone);
      await _pump();
      fake.completeSession();
      await expectation1;

      final stream2 = fake.transcribeFile(_request);
      final events2 = <TranscriptSegment>[];
      final sub2 = stream2.listen(events2.add);
      await _pump();

      expect(fake.sessionPhase, SessionPhase.decoding);

      fake.emitSegment(const TranscriptSegment(text: '2本目', isFinal: true));
      fake.completeSession();
      await _pump();

      expect(events2, [const TranscriptSegment(text: '2本目', isFinal: true)]);
      await sub2.cancel();
    });

    test('1本目がエラー終了した後も2本目を開始できる', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.available,
      );

      final stream1 = fake.transcribeFile(_request);
      final expectation1 = expectLater(
        stream1,
        emitsInOrder(<Object>[
          emitsError(isA<PlatformException_>()),
          emitsDone,
        ]),
      );
      await _pump();
      fake.errorSession(const PlatformException_(code: 'RECOGNITION_FAILED'));
      await expectation1;

      final stream2 = fake.transcribeFile(_request);
      final sub2 = stream2.listen((_) {});
      await _pump();

      expect(fake.sessionPhase, SessionPhase.decoding);

      fake.completeSession();
      await sub2.cancel();
    });

    test('1本目がキャンセルされた後も2本目を開始できる', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.available,
      );

      final stream1 = fake.transcribeFile(_request);
      final sub1 = stream1.listen((_) {});
      await _pump();
      await sub1.cancel();
      await _pump();
      expect(fake.sessionPhase, SessionPhase.cancelled);

      final stream2 = fake.transcribeFile(_request);
      final sub2 = stream2.listen((_) {});
      await _pump();

      expect(fake.sessionPhase, SessionPhase.decoding);

      fake.completeSession();
      await sub2.cancel();
    });
  });
}
