import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// `offline_stt` のiOS/macOS共用実装(雛形)。
///
/// Swift実装本体(AVAudioFile → SpeechAnalyzer + SpeechTranscriber、
/// AssetInventoryによるモデル管理、design.md §4.2)は
/// M2・Pigeonスキーマ確定後に実装する。`spikes/darwin/` の検証結果
/// (RTF・プリセット選定・AssetInventory状態の突き合わせ)を移植の出発点と
/// する。本クラスは `OfflineTranscriberPlatform.instance` の登録先としての
/// 雛形のみである。
class OfflineSttDarwin extends OfflineTranscriberPlatform {
  /// `dartPluginClass` からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttDarwin();
  }

  @override
  Future<ModelState> checkModel(String locale) {
    throw UnimplementedError(
      'offline_stt_darwin: checkModel() はM2で実装する(design.md §4.2)。',
    );
  }

  @override
  Stream<DownloadProgress> downloadModel(String locale) {
    throw UnimplementedError(
      'offline_stt_darwin: downloadModel() はM2で実装する(design.md §4.2)。',
    );
  }

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) {
    throw UnimplementedError(
      'offline_stt_darwin: transcribeFile() はM2で実装する(design.md §4.2)。',
    );
  }
}
