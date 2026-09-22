/// `offline_stt` のWeb実装。
///
/// **利用者がこのライブラリを直接importすることはない**(requirements.md
/// §6)。アプリは `offline_stt` にのみ依存すればよく、この実装は
/// `src/backend.dart` の条件付きexport(`dart.library.js_interop`)に
/// よってWebコンパイルターゲットでのみ選択される。
///
/// 認識バックエンドはChromeのオンデバイスWeb Speech
/// (`SpeechRecognition.available/install/start`)、デコードは Web Audio の
/// `AudioContext` である(design.md §4.1)。Pigeonは使わず
/// `package:web` + `dart:js_interop` のみで構成している(design.md §2.3)。
/// Chrome 142以上のデスクトップ版、かつ localhost または https 配信で
/// なければ動作しない(requirements.md NFR-4)。手動E2E手順は
/// `docs/e2e/E2E_CHECKLIST_WEB.md` にある。
///
/// このライブラリの入口は [OfflineSttWeb] 1クラスであり、残りは同じ
/// `src/web/` 配下の非公開実装である。実装の分担は同クラスのdocコメントを
/// 参照すること。
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../common.dart';
import '../session_guard.dart';
import 'model_management.dart' as model_management;
import 'recognition_session.dart';

/// `offline_stt` のWeb実装(design.md §4.1)。
///
/// `package:web` + `dart:js_interop` によるChromeオンデバイスWeb Speech
/// 連携(`SpeechRecognition.available/install/start` + `AudioContext`に
/// よるデコード)。Pigeonは使わずDart単体で実装する(design.md §2.3)。
/// `spikes/web/` のM0検証結果(spikes/web/RESULTS.md)を移植の出発点とした。
///
/// design.md §1・§4.1が定める3モジュール境界をそのまま維持している:
/// - デコード: `src/web/audio_decoding.dart`(Issue #27)
/// - モデル管理: `src/web/model_management.dart`(Issue #26・#30)
/// - 認識セッション: `src/web/recognition_session.dart`(Issue #28・#29)
///
/// セッション排他(design.md §3、同時1本まで)は共有層の
/// `TranscribeSessionGuard`(`src/session_guard.dart`)を `with` して
/// 満たす。
class OfflineSttWeb extends OfflineTranscriberPlatform
    with TranscribeSessionGuard {
  /// Web向けプラグイン登録エントリポイント。
  ///
  /// `pubspec.yaml` の `flutter.plugin.platforms.web` は `pluginClass` と
  /// その `static registerWith(Registrar)` を必須とするため宣言している。
  /// ただしこのWeb実装はPigeon・MethodChannelを使わず `package:web` +
  /// `dart:js_interop` だけで完結しており(design.md §2.3)、[Registrar]
  /// へ登録すべきチャネルハンドラを持たない。実装の選択は
  /// `src/backend.dart` の条件付きexportが行うため、ここで行う処理は無い。
  static void registerWith(Registrar registrar) {}

  @override
  Future<ModelState> checkModel(String locale) =>
      model_management.checkModel(locale);

  @override
  Future<List<String>> supportedLocales() =>
      model_management.supportedLocales();

  @override
  Stream<DownloadProgress> downloadModel(String locale) =>
      model_management.downloadModel(locale);

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      guardSession(() => runTranscriptionSession(request));
}
