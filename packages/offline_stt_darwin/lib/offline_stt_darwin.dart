import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
// offline_stt_platform_interfaceのdocコメント(lib/src/session_guard.dart)が
// 明記するとおり、TranscribeSessionGuardはネイティブ実装パッケージ間だけの
// 共有実装であり、公開バレルには意図的に含まれていない。そのためsrc/への
// 直接importが必要であり、implementation_importsのlintは意図的に抑止する。
// ignore: implementation_imports
import 'package:offline_stt_platform_interface/src/session_guard.dart';

import 'src/model_management.dart' as model_management;
import 'src/pigeon.g.dart' as pigeon;
import 'src/recognition_session.dart';

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
/// - モデル管理: `src/model_management.dart`(Issue #35)
/// - デコード・認識セッション・キャンセル: `src/recognition_session.dart`
///   (Issue #36〜#38)
///
/// セッション排他(design.md §3、同時1本まで)は
/// `offline_stt_platform_interface`の`TranscribeSessionGuard`を`with`して
/// 満たす(offline_stt_webと同じ構成)。
class OfflineSttDarwin extends OfflineTranscriberPlatform
    with TranscribeSessionGuard {
  /// `dartPluginClass`からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttDarwin();
  }

  /// Pigeon生成のMethodチャネルAPI(design.md §2.3)。
  final pigeon.OfflineSttHostApi _hostApi = pigeon.OfflineSttHostApi();

  @override
  Future<ModelState> checkModel(String locale) =>
      model_management.checkModel(_hostApi, locale);

  @override
  Stream<DownloadProgress> downloadModel(String locale) =>
      model_management.downloadModel(_hostApi, locale);

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      guardSession(() => runTranscriptionSession(_hostApi, request));
}
