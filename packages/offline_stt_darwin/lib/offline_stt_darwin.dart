import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

// Pigeon生成コード(`pigeons/offline_stt_events.dart` から生成、Issue #24)。
// `ModelState` / `DownloadProgress` / `TranscribeRequest` / `TranscriptSegment`
// はplatform_interface側と同名のためプレフィックス付きでimportする。
import 'src/pigeon.g.dart' as pigeon;

/// `offline_stt` のiOS/macOS共用実装(雛形)。
///
/// Swift実装本体(AVAudioFile → SpeechAnalyzer + SpeechTranscriber、
/// AssetInventoryによるモデル管理、design.md §4.2)はM2で実装する。
/// `spikes/darwin/` の検証結果(RTF・プリセット選定・AssetInventory状態の
/// 突き合わせ)を移植の出発点とする。本クラスは
/// `OfflineTranscriberPlatform.instance` の登録先としての雛形のみである
/// が、Pigeon生成の `OfflineSttHostApi` / `pigeon.segments()` /
/// `pigeon.downloadProgress()`(design.md §2.3)への参照はここで保持し、
/// M2での実装の出発点とする。
class OfflineSttDarwin extends OfflineTranscriberPlatform {
  /// `dartPluginClass` からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttDarwin();
  }

  /// Pigeon生成のMethodチャネルAPI(design.md §2.3)。
  ///
  /// 各メソッドの実装本体(M2)で使用する。現時点では各メソッドが
  /// `UnimplementedError` を送出するスタブのままであるため未使用であり、
  /// それを示すため明示的にignoreしている。
  // ignore: unused_field
  final pigeon.OfflineSttHostApi _hostApi = pigeon.OfflineSttHostApi();

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
