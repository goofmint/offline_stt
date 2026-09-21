import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// [error] を利用者向けの日本語メッセージへ変換する。
///
/// requirements.md FR-6・design.md §2.2 が定める `TranscribeException` の
/// 各サブクラスを区別し、意味のあるメッセージを出す参照実装(Issue #32の
/// 要件「エラー表示」)。`TranscribeException` は sealed class のため、
/// switch式で全サブクラスを網羅していないとコンパイルエラーになる
/// (取りこぼし防止)。
///
/// `TranscribeException` 以外にも、以下の2つはライブラリの契約上あり得る
/// ため個別に扱う:
/// - [StateError]: design.md §3「同時セッションは1本まで。2本目の開始は
///   StateErrorをStreamエラーとして送出する」
/// - [UnimplementedError]: Android実装(M3)が未実装のスタブ
///   メソッドから送出される(offline_stt_android参照)
String describeTranscribeError(Object error) {
  if (error is TranscribeException) {
    return switch (error) {
      ModelUnavailableException() =>
        'モデルの状態が「利用可能」ではないため文字起こしを開始できない。'
            '先に音声認識モデルの状態を確認し、ダウンロード可能であれば'
            '同意のうえダウンロードすること。',
      LocaleUnsupportedException() => '指定したロケールはこの端末・ブラウザでは対応していない。',
      DecodeFailedException() =>
        '音声ファイルのデコードに失敗した。対応形式(wav / m4a / '
            'mp3 / aac 等)かどうかを確認すること。',
      DeviceUnsupportedException() =>
        'この端末・OSは音声認識機能自体に対応していない'
            '(例: Androidのブートローダーアンロック端末)。',
      CancelledException() => '文字起こしがキャンセルされた。',
      PlatformException_(:final code, :final message) =>
        'プラットフォーム側でエラーが発生した(code: $code'
            '${message != null ? ', message: $message' : ''})。',
    };
  }
  if (error is StateError) {
    return '既に実行中のセッションがある(design.md §3のとおり同時実行は1本まで)。'
        '実行中の文字起こしが終わってから再度試すこと。詳細: ${error.message}';
  }
  if (error is UnimplementedError) {
    return 'このプラットフォームの実装はまだ提供されていない。詳細: '
        '${error.message}';
  }
  return '予期しないエラーが発生した: $error';
}
