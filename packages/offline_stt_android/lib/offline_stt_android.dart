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

/// `offline_stt`のAndroid実装(design.md §4.3(wt73版)、Issue #42〜#49)。
///
/// Pigeon生成コード(`pigeons/offline_stt_events.dart`から生成、Issue #24)
/// のHostApi(MethodChannel)/EventChannelを介して、Kotlin実装本体
/// (`android/src/main/kotlin/com/moongift/offline_stt_android/`。
/// `MediaExtractor`/`MediaCodec` → リサンプリング(16kHz/モノラル/16-bit
/// PCM) → `ParcelFileDescriptor`の実時間ポンプ →
/// `android.speech.SpeechRecognizer`(オンデバイス)、
/// `SpeechRecognizer.checkRecognitionSupport()`によるモデル管理)と通信
/// する。
///
/// **バックエンド差し替えの経緯**: このブランチの`design.md`§4.3は古い
/// ML Kit GenAI版である。Androidのバックエンドは既にAndroid標準
/// `android.speech.SpeechRecognizer`へ差し替えることが決定しており、
/// 正しい設計は別ブランチ(PR #73、未マージ)の`design.md`§4.3・
/// `requirements.md`(FR-1/FR-2/FR-3/FR-6)にある。`spikes/android/`の
/// `PlatformSttHarness.kt`/`PlatformSttProbe.kt`/`RealtimePump.kt`/
/// `WavPcm.kt`(Pixel 6実機で動作確認済み)を移植の出発点とした。
///
/// design.md §1・§4.3が定める3モジュール境界をそのまま維持している:
/// - モデル管理: `src/model_management.dart`(Issue #43)
/// - デコード・認識セッション・キャンセル: `src/recognition_session.dart`
///   (Issue #44〜#48)
///
/// セッション排他(design.md §3、同時1本まで)は
/// `offline_stt_platform_interface`の`TranscribeSessionGuard`を`with`して
/// 満たす(offline_stt_darwin/webと同じ構成)。
class OfflineSttAndroid extends OfflineTranscriberPlatform
    with TranscribeSessionGuard {
  /// `dartPluginClass`からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    OfflineTranscriberPlatform.instance = OfflineSttAndroid();
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
