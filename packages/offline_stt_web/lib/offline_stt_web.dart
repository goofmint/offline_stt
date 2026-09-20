import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
// offline_stt_platform_interfaceのdocコメント(lib/src/session_guard.dart)が
// 明記するとおり、TranscribeSessionGuardはネイティブ実装パッケージ間だけの
// 共有実装であり、公開バレルには意図的に含まれていない。そのためsrc/への
// 直接importが必要であり、implementation_importsのlintは意図的に抑止する。
// ignore: implementation_imports
import 'package:offline_stt_platform_interface/src/session_guard.dart';

import 'src/model_management.dart' as model_management;
import 'src/recognition_session.dart';

/// `offline_stt` のWeb実装(design.md §4.1)。
///
/// `package:web` + `dart:js_interop` によるChromeオンデバイスWeb Speech
/// 連携(`SpeechRecognition.available/install/start` + `AudioContext`に
/// よるデコード)。Pigeonは使わずDart単体で実装する(design.md §2.3)。
/// `spikes/web/` のM0検証結果(spikes/web/RESULTS.md)を移植の出発点とした。
///
/// design.md §1・§4.1が定める3モジュール境界をそのまま維持している:
/// - デコード: `src/audio_decoding.dart`(Issue #27)
/// - モデル管理: `src/model_management.dart`(Issue #26・#30)
/// - 認識セッション: `src/recognition_session.dart`(Issue #28・#29)
///
/// セッション排他(design.md §3、同時1本まで)は
/// `offline_stt_platform_interface` の `TranscribeSessionGuard` を
/// `with` して満たす。
class OfflineSttWeb extends OfflineTranscriberPlatform
    with TranscribeSessionGuard {
  /// Web向けプラグイン登録エントリポイント。
  static void registerWith(Registrar registrar) {
    OfflineTranscriberPlatform.instance = OfflineSttWeb();
  }

  @override
  Future<ModelState> checkModel(String locale) =>
      model_management.checkModel(locale);

  @override
  Stream<DownloadProgress> downloadModel(String locale) =>
      model_management.downloadModel(locale);

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      guardSession(() => runTranscriptionSession(request));
}
