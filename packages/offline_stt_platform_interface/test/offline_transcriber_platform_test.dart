import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:test/test.dart';

/// `extends` による正当な実装。token検証を通過する。
class _FakeOfflineTranscriberPlatform extends OfflineTranscriberPlatform {
  @override
  Future<ModelState> checkModel(String locale) async => ModelState.available;

  @override
  Stream<DownloadProgress> downloadModel(String locale) =>
      const Stream<DownloadProgress>.empty();

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      const Stream<TranscriptSegment>.empty();
}

/// `PlatformInterface` を独自tokenで継承し `implements` で型だけ満たす、
/// 不正なインスタンス。`OfflineTranscriberPlatform` のprivate tokenを
/// 持たないため、`PlatformInterface.verify` はこれを拒否しなければならない。
class _InvalidTokenPlatform extends PlatformInterface
    implements OfflineTranscriberPlatform {
  _InvalidTokenPlatform() : super(token: Object());

  @override
  Future<ModelState> checkModel(String locale) async => ModelState.available;

  @override
  Stream<DownloadProgress> downloadModel(String locale) =>
      const Stream<DownloadProgress>.empty();

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      const Stream<TranscriptSegment>.empty();
}

void main() {
  group('OfflineTranscriberPlatform.instance', () {
    test('未設定の場合は取得時にStateErrorを送出する', () {
      expect(() => OfflineTranscriberPlatform.instance, throwsStateError);
    });

    test('token検証を通過した実装をset/getできる', () {
      final fake = _FakeOfflineTranscriberPlatform();
      OfflineTranscriberPlatform.instance = fake;
      expect(OfflineTranscriberPlatform.instance, same(fake));
    });

    test('不正なtokenのインスタンスをsetすると例外になる', () {
      expect(
        () => OfflineTranscriberPlatform.instance = _InvalidTokenPlatform(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
