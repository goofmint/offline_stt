import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

// Pigeon生成コード(`pigeons/offline_stt_events.dart` から生成、Issue #24)。
// `ModelState` / `DownloadProgress` / `TranscribeRequest` / `TranscriptSegment`
// はplatform_interface側と同名のためプレフィックス付きでimportする。
import 'src/pigeon.g.dart' as pigeon;

/// `offline_stt` のAndroid実装(雛形)。
///
/// Kotlin実装本体(MediaCodecデコード → 16kHz/モノラル/16-bit PCM →
/// 実時間ポンプ → ML Kit GenAI Speech Recognition、design.md §4.3)は
/// M3で実装する。本クラスは `OfflineTranscriberPlatform.instance` の
/// 登録先としての雛形のみであるが、Pigeon生成の `OfflineSttHostApi` /
/// `pigeon.segments()` / `pigeon.downloadProgress()`(design.md §2.3)への
/// 参照はここで保持し、M3での実装の出発点とする。
class OfflineSttAndroid extends OfflineTranscriberPlatform {
  /// `dartPluginClass` からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttAndroid();
  }

  /// Pigeon生成のMethodチャネルAPI(design.md §2.3)。
  ///
  /// 各メソッドの実装本体(M3)で使用する。現時点では各メソッドが
  /// `UnimplementedError` を送出するスタブのままであるため未使用であり、
  /// それを示すため明示的にignoreしている。
  // ignore: unused_field
  final pigeon.OfflineSttHostApi _hostApi = pigeon.OfflineSttHostApi();

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
