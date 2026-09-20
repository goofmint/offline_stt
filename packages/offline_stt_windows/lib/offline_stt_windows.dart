import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// `offline_stt` のWindows実装(雛形)。
///
/// C++/WinRT実装本体(Windows AI Speech Recognition の
/// `BatchRecognition.RecognizeFromFile` + 必要ならMedia Foundationでの
/// wav変換、design.md §4.4)はM4・Pigeonスキーマ確定後に実装する。
/// WinAppSDK 1.7.1+への依存宣言、MSIX + `systemAIModels` capability の
/// アプリ側要件もM4で整備する。本クラスは
/// `OfflineTranscriberPlatform.instance` の登録先としての雛形のみである。
class OfflineSttWindows extends OfflineTranscriberPlatform {
  /// `dartPluginClass` からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttWindows();
  }

  @override
  Future<ModelState> checkModel(String locale) {
    throw UnimplementedError(
      'offline_stt_windows: checkModel() はM4で実装する(design.md §4.4)。',
    );
  }

  @override
  Stream<DownloadProgress> downloadModel(String locale) {
    throw UnimplementedError(
      'offline_stt_windows: downloadModel() はM4で実装する(design.md §4.4)。',
    );
  }

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) {
    throw UnimplementedError(
      'offline_stt_windows: transcribeFile() はM4で実装する(design.md §4.4)。',
    );
  }
}
