/// `offline_stt` のAndroid実装。
///
/// **利用者がこのライブラリを直接importすることはない**(requirements.md
/// §6)。アプリは `offline_stt` にのみ依存すればよく、この実装は
/// `src/backend_io.dart` が実行時のプラットフォーム判定で選択する。
///
/// 認識バックエンドはAndroid標準の `android.speech.SpeechRecognizer` の
/// オンデバイス認識である。当初設計のML Kit GenAI(AICore)は、M0検証で
/// 使用したPixel 6実機のAICoreがstub版であり利用できなかったため採用して
/// いない(spikes/android/RESULTS.md)。
///
/// このライブラリの入口は [OfflineSttAndroid] 1クラスであり、残りは同じ
/// `src/android/` 配下の非公開実装である。実装の分担・既知の制約は同
/// クラスのdocコメントを参照すること。
library;

import '../common.dart';
import '../pigeon.g.dart' as pigeon;
import '../session_guard.dart';
import 'model_management.dart' as model_management;
import 'recognition_session.dart';

/// `offline_stt`のAndroid実装(design.md §4.3(wt73版)、Issue #42〜#49)。
///
/// Pigeon生成コード(`pigeons/offline_stt_events.dart`から生成、Issue #24)
/// のHostApi(MethodChannel)/EventChannelを介して、Kotlin実装本体
/// (`android/src/main/kotlin/com/moongift/offline_stt/`。
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
/// - モデル管理: `src/android/model_management.dart`(Issue #43)
/// - デコード・認識セッション・キャンセル:
///   `src/android/recognition_session.dart`(Issue #44〜#48)
///
/// セッション排他(design.md §3、同時1本まで)は共有層の
/// `TranscribeSessionGuard`(`src/session_guard.dart`)を`with`して満たす
/// (Darwin/Web実装と同じ構成)。
class OfflineSttAndroid extends OfflineTranscriberPlatform
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
