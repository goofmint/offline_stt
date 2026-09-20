import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// `offline_stt` のAndroid実装(雛形)。
///
/// Kotlin実装本体(MediaCodecデコード → 16kHz/モノラル/16-bit PCM →
/// 実時間ポンプ → ML Kit GenAI Speech Recognition、design.md §4.3)は
/// M3・Pigeonスキーマ確定後に実装する。本クラスは
/// `OfflineTranscriberPlatform.instance` の登録先としての雛形のみである。
class OfflineSttAndroid extends OfflineTranscriberPlatform {
  /// `dartPluginClass` からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttAndroid();
  }

  @override
  Future<ModelState> checkModel(String locale) {
    throw UnimplementedError(
      'offline_stt_android: checkModel() はM3で実装する(design.md §4.3)。',
    );
  }

  @override
  Stream<DownloadProgress> downloadModel(String locale) {
    throw UnimplementedError(
      'offline_stt_android: downloadModel() はM3で実装する(design.md §4.3)。',
    );
  }

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) {
    throw UnimplementedError(
      'offline_stt_android: transcribeFile() はM3で実装する(design.md §4.3)。',
    );
  }
}
