import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// `SpeechRecognition.available()` の戻り値(文字列)を [ModelState] へ写像する
/// (design.md §4.1、requirements.md FR-1、Issue #26)。
///
/// ブラウザAPI(`dart:js_interop` / `package:web`)に一切依存しない純粋な
/// 文字列比較のみであるため、単体テストが書ける。本パッケージの
/// テスト方針(ブラウザAPIに依存しない純粋ロジックだけを切り出して単体
/// テストする)により、このファイルは `test/model_state_mapping_test.dart`
/// で検証する。
///
/// 未知の値が来た場合はフォールバックせず、明確に [StateError] を投げる
/// (Chromeの仕様変更等で `available` / `downloadable` / `downloading` /
/// `unavailable` 以外の値が返ってきた場合、意味不明な値を4値のいずれかへ
/// 無理に丸めるとバグを隠すことになるため)。
ModelState mapAvailabilityToModelState(String value) {
  switch (value) {
    case 'available':
      return ModelState.available;
    case 'downloadable':
      return ModelState.downloadable;
    case 'downloading':
      return ModelState.downloading;
    case 'unavailable':
      return ModelState.unavailable;
    default:
      throw StateError(
        'SpeechRecognition.available() が未知の値を返した: "$value"。'
        'design.md §4.1が定める4値(available/downloadable/downloading/'
        'unavailable)以外の値はフォールバックで丸めず、明確にエラーにする。',
      );
  }
}
