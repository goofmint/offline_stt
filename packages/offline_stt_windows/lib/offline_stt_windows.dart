import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

// Pigeon生成コード(`pigeons/offline_stt_windows.dart` から生成、Issue #24)。
// `ModelState` / `DownloadProgress` / `TranscribeRequest` / `TranscriptSegment`
// はplatform_interface側と同名のためプレフィックス付きでimportする。
// design.md §2.3 の方針(EventChannel)どおりにはできないため、Windowsのみ
// `OfflineSttStreamCallbackApi`(FlutterApiコールバック)でストリームを
// 代替している(理由は `pigeons/offline_stt_windows.dart` 冒頭コメント参照)。
import 'src/pigeon.g.dart' as pigeon;

/// `offline_stt` のWindows実装(雛形)。
///
/// C++/WinRT実装本体(Windows AI Speech Recognition の
/// `BatchRecognition.RecognizeFromFile` + 必要ならMedia Foundationでの
/// wav変換、design.md §4.4)はM4で実装する。WinAppSDK 1.7.1+への依存宣言、
/// MSIX + `systemAIModels` capability のアプリ側要件もM4で整備する。
/// 本クラスは `OfflineTranscriberPlatform.instance` の登録先としての雛形
/// のみであるが、Pigeon生成の `OfflineSttHostApi` /
/// `OfflineSttStreamCallbackApi`(design.md §2.3)への参照はここで保持し、
/// M4での実装の出発点とする。
class OfflineSttWindows extends OfflineTranscriberPlatform {
  /// `dartPluginClass` からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttWindows();
  }

  /// Pigeon生成のMethodチャネルAPI(design.md §2.3)。
  ///
  /// 各メソッドの実装本体(M4)で使用する。現時点では各メソッドが
  /// `UnimplementedError` を送出するスタブのままであるため未使用であり、
  /// それを示すため明示的にignoreしている。M4では合わせて
  /// `pigeon.OfflineSttStreamCallbackApi.setUp()` でストリーム
  /// コールバックの受信を登録する。
  // ignore: unused_field
  final pigeon.OfflineSttHostApi _hostApi = pigeon.OfflineSttHostApi();

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
