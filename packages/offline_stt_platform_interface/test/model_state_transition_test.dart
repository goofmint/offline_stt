import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:test/test.dart';

import 'fakes/fake_offline_transcriber_platform.dart';

/// design.md §3 のモデル状態遷移図を、[FakeOfflineTranscriberPlatform] を
/// 通じて網羅的に検証する。
///
/// ```
/// [unavailable] … 端末/OS/ブラウザ非対応。終端
/// [downloadable] --downloadModel()--> [downloading] --完了--> [available]
///                                         └--失敗--> [downloadable](エラー通知)
/// [available] --transcribeFile()--> セッション(idle→decoding→recognizing→done|cancelled|error)
/// ```
void main() {
  group('モデル状態遷移(design.md §3)', () {
    test('unavailableは終端であり、downloadModel()してもavailableにならない', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.unavailable,
      );

      expect(await fake.checkModel('ja-JP'), ModelState.unavailable);

      final events = await fake.downloadModel('ja-JP').toList();

      expect(events, isEmpty);
      expect(await fake.checkModel('ja-JP'), ModelState.unavailable);
    });

    test(
      'downloadable → downloadModel() → downloading → 完了 → available',
      () async {
        final fake = FakeOfflineTranscriberPlatform(
          initialState: ModelState.downloadable,
        );

        expect(await fake.checkModel('ja-JP'), ModelState.downloadable);

        final stream = fake.downloadModel('ja-JP');
        // downloadModel() を呼び出した時点でdownloadingに遷移する。
        expect(await fake.checkModel('ja-JP'), ModelState.downloading);

        final expectation = expectLater(
          stream,
          emitsInOrder(<Object>[
            DownloadProgress(fraction: 0.5, completed: false),
            DownloadProgress(fraction: 1.0, completed: true),
            emitsDone,
          ]),
        );

        fake.emitDownloadProgress(
          DownloadProgress(fraction: 0.5, completed: false),
        );
        fake.completeDownloadSuccess();

        await expectation;
        expect(await fake.checkModel('ja-JP'), ModelState.available);
      },
    );

    test('downloading中に失敗するとdownloadableに戻り、エラーが通知される', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.downloadable,
      );

      final stream = fake.downloadModel('ja-JP');
      expect(await fake.checkModel('ja-JP'), ModelState.downloading);

      final expectation = expectLater(
        stream,
        emitsInOrder(<Object>[emitsError(isA<PlatformException_>()), emitsDone]),
      );

      fake.failDownload(const PlatformException_(code: 'DOWNLOAD_FAILED'));

      await expectation;
      expect(await fake.checkModel('ja-JP'), ModelState.downloadable);
    });

    test('DownloadProgressのfraction: null(不定進捗)を扱える(Windows/Web想定)', () async {
      final fake = FakeOfflineTranscriberPlatform(
        initialState: ModelState.downloadable,
      );

      final stream = fake.downloadModel('ja-JP');
      final expectation = expectLater(
        stream,
        emitsInOrder(<Object>[
          DownloadProgress(fraction: null, completed: false),
          DownloadProgress(fraction: 1.0, completed: true),
          emitsDone,
        ]),
      );

      fake.emitDownloadProgress(
        DownloadProgress(fraction: null, completed: false),
      );
      fake.completeDownloadSuccess();

      await expectation;
    });

    test(
      'transcribeFile()はcheckModel()がavailable以外ならModelUnavailableExceptionを'
      '即座にStreamエラーで返す(暗黙ダウンロードしない)',
      () async {
        final fake = FakeOfflineTranscriberPlatform(
          initialState: ModelState.downloadable,
        );

        final stream = fake.transcribeFile(
          const TranscribeRequest(path: '/tmp/a.wav', locale: 'ja-JP'),
        );

        await expectLater(stream, emitsError(isA<ModelUnavailableException>()));

        // 内部で暗黙的にダウンロードを開始していないこと。
        expect(fake.modelState, ModelState.downloadable);
      },
    );
  });
}
