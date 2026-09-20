import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// `offline_stt` のWeb実装(雛形)。
///
/// `package:web` + `dart:js_interop` によるChromeオンデバイスWeb Speech
/// 連携(`SpeechRecognition.available/install/start` + `AudioContext` に
/// よるデコード、design.md §4.1)はM1で実装する。Pigeonは使わずDart単体で
/// 実装する方針(design.md §2.3)。`spikes/web/` の検証結果を移植の出発点と
/// する。本クラスは `OfflineTranscriberPlatform.instance` の登録先としての
/// 雛形のみである。
class OfflineSttWeb extends OfflineTranscriberPlatform {
  /// Web向けプラグイン登録エントリポイント。
  static void registerWith(Registrar registrar) {
    OfflineTranscriberPlatform.instance = OfflineSttWeb();
  }

  @override
  Future<ModelState> checkModel(String locale) {
    throw UnimplementedError(
      'offline_stt_web: checkModel() はM1で実装する(design.md §4.1)。',
    );
  }

  @override
  Stream<DownloadProgress> downloadModel(String locale) {
    throw UnimplementedError(
      'offline_stt_web: downloadModel() はM1で実装する(design.md §4.1)。',
    );
  }

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) {
    throw UnimplementedError(
      'offline_stt_web: transcribeFile() はM1で実装する(design.md §4.1)。',
    );
  }
}
