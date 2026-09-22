/// `offline_stt` のiOS/macOS共用実装。
///
/// **利用者がこのライブラリを直接importすることはない**(requirements.md
/// §6)。アプリは `offline_stt` にのみ依存すればよく、この実装は
/// `src/backend_io.dart` が実行時のプラットフォーム判定で選択する。
///
/// 認識バックエンドは `SpeechAnalyzer` + `SpeechTranscriber`、デコードは
/// `AVAudioFile` である(design.md §4.2)。iOSシミュレータでは
/// `SpeechTranscriber.isAvailable` が `false` になり利用できないことが
/// M0検証で確定している(spikes/darwin/RESULTS.md)。認識の検証には実機が
/// 必要である。
///
/// このライブラリの入口は [OfflineSttDarwin] 1クラスであり、残りは同じ
/// `src/darwin/` 配下の非公開実装である。実装の分担は同クラスのdoc
/// コメントを参照すること。
library;

import '../common.dart';
import '../pigeon.g.dart' as pigeon;
import '../session_guard.dart';
import 'model_management.dart' as model_management;
import 'recognition_session.dart';

/// `offline_stt`のiOS/macOS共用実装(design.md §4.2、Issue #33〜#39)。
///
/// Pigeon生成コード(`pigeons/offline_stt_events.dart`から生成、Issue #24)
/// のHostApi(MethodChannel)/EventChannelを介して、Swift実装本体
/// (`darwin/Classes/`。`AVAudioFile` → `SpeechAnalyzer` + `SpeechTranscriber`、
/// `AssetInventory`によるモデル管理)と通信する。
/// `spikes/darwin/`の検証結果(spikes/darwin/RESULTS.md。RTF・プリセット
/// 選定・`AssetInventory`状態の突き合わせ)を移植の出発点とした。
///
/// design.md §1・§4.2が定める3モジュール境界をそのまま維持している:
/// - モデル管理: `src/darwin/model_management.dart`(Issue #35)
/// - デコード・認識セッション・キャンセル:
///   `src/darwin/recognition_session.dart`(Issue #36〜#38)
///
/// セッション排他(design.md §3、同時1本まで)は共有層の
/// `TranscribeSessionGuard`(`src/session_guard.dart`)を`with`して満たす
/// (Android/Web実装と同じ構成)。
class OfflineSttDarwin extends OfflineTranscriberPlatform
    with TranscribeSessionGuard {
  /// Pigeon生成のMethodチャネルAPI(design.md §2.3)。
  final pigeon.OfflineSttHostApi _hostApi = pigeon.OfflineSttHostApi();

  @override
  Future<ModelState> checkModel(String locale) =>
      model_management.checkModel(_hostApi, locale);

  @override
  Future<List<String>> supportedLocales() =>
      model_management.supportedLocales(_hostApi);

  @override
  Stream<DownloadProgress> downloadModel(String locale) =>
      model_management.downloadModel(_hostApi, locale);

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      guardSession(() => runTranscriptionSession(_hostApi, request));
}
