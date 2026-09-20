import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// `SpeechRecognitionErrorEvent.error` の値(文字列)を [TranscribeException]
/// へ写像する(design.md §5 エラーマッピング表 Web列、Issue #28)。
///
/// ブラウザAPIに依存しない純粋な文字列分岐のみであるため単体テストが書ける
/// (`test/speech_error_mapping_test.dart` 参照)。
///
/// 各コードの扱い:
/// - `language-not-supported`: design.md §5どおり [LocaleUnsupportedException]
///   に写像する。
/// - `network`: NFR-2(サーバーへのフォールバック禁止)違反の兆候である。
///   design.md §2.2の例外階層には専用の型が無いため、[PlatformException_]の
///   `code` に `network` をそのまま残し、呼び出し側がコード名で気づける形で
///   伝播させる。
/// - `aborted`: design.md §4.1・§8未決事項4の実機知見(spikes/web/RESULTS.md)
///   により、言語パック未取得時にja-JPで観測される。しかしdesign.md §5の
///   注記は「この状況を ModelUnavailable へ写像する実装は、エラー名の判定
///   ではなく `available()` による事前確認によって行うべきである」と明記して
///   いる。そのためここではエラー名から意味を推測せず、[PlatformException_]
///   としてそのまま伝える(本セッションの `available` 事前確認が本来の防止策
///   である。recognition_session.dart 参照)。
/// - 上記以外: すべて [PlatformException_] としてコードをそのまま伝える。
///   design.md §5の表に明示の対応が無いコード(`no-speech` /
///   `audio-capture` / `not-allowed` / `service-not-allowed` /
///   `bad-grammar` 等)を、対応の無い共通例外へ無理に丸めることはしない。
TranscribeException mapSpeechErrorCode(String code, String message) {
  switch (code) {
    case 'language-not-supported':
      return const LocaleUnsupportedException();
    default:
      return PlatformException_(code: code, message: message);
  }
}
