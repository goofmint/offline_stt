import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// requirements.md FR-2・§8「モデルダウンロード同意ダイアログの実装」の
/// 参照実装。
///
/// **これが example app の最重要要素である。** requirements.md FR-2 と
/// §8 は「ダウンロードはユーザー同意後に呼び出す前提とし、同意UIは
/// ライブラリ利用者(アプリ側)の責務とする」と定めている。この関数が
/// `true` を返した場合のみ `downloadModel()` を呼び出すこと。同意なしに
/// 呼び出してはならない。
///
/// 文言は requirements.md §8 のガイドラインに従う:
/// - モデル名(例: 具体的なモデル名・ベンダー名)ではなく「音声認識モデル」
///   という一般名称のみを用いる
/// - ダウンロードサイズの目安に触れる(Webの言語パックは約60MB、
///   requirements.md §3)。ただし他プラットフォームはOS管理でサイズが
///   異なるため、Web専用の数値であることも明示する
///
/// Windows(Issue #59)では、Microsoft公式ドキュメントの
/// 「Recommended UX pattern」が同意ダイアログに含めるべき内容を具体的に
/// 挙げているため、Windowsのときだけ専用の文面に切り替える。詳細は
/// `packages/offline_stt_windows/README.md` §5 を参照。
///
/// Android(Issue #51)も専用の文面に切り替える。ダウンロードされるのは
/// 「対象ロケールのオンデバイス言語パック」であり、取得は
/// `SpeechRecognizer.triggerModelDownload()` を通じてOS / Google Play
/// services 側が行う。**完了通知(`ModelDownloadListener`)が発火しない
/// 実測があり**、完了判定は `checkModel()` の再照会で行っている、という
/// アプリの挙動をユーザーへ説明しておく必要がある。詳細は
/// `packages/offline_stt_android/README.md` §4 制約2 を参照。
Future<bool> showDownloadConsentDialog(
  BuildContext context, {
  required String locale,
}) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('音声認識モデルのダウンロード'),
        content: SingleChildScrollView(child: Text(_consentBody(locale))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('同意してダウンロード'),
          ),
        ],
      );
    },
  );
  return agreed ?? false;
}

bool get _isWindows =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String _consentBody(String locale) {
  if (_isWindows) {
    // Microsoft公式ドキュメント(Windows AI APIs / Speech Recognition の
    // 「Recommended UX pattern」)が、EnsureReadyAsync() を呼ぶ前に
    // ユーザーへ伝えるべきとしている4点をすべて含めている:
    //   (a) オプションの音声認識モデルがダウンロードされること
    //   (b) ダウンロードは Windows Update 経由でバックグラウンドに行われること
    //   (c) 進捗は 設定 > Windows Update で確認できること
    //   (d) モデルは後から 設定 > システム > AI コンポーネント で削除できること
    // 「モデル名ではなく一般名称を使う」という点は requirements.md §8 と
    // 公式ドキュメントの双方が同じことを言っている。
    return '文字起こしを行うには、オプションのAIコンポーネントである'
        '音声認識モデルをこの端末にダウンロードする必要がある。'
        'アプリ自体のサイズは増えない。\n\n'
        'ダウンロードはWindows Update経由でバックグラウンドに行われる。'
        '進捗は「設定 > Windows Update」で確認できる。\n\n'
        'ダウンロードしたモデルは、後から「設定 > システム > '
        'AIコンポーネント」でいつでも削除できる。削除するとこのアプリの'
        '文字起こしは再びダウンロードが必要な状態に戻り、'
        'このダイアログが改めて表示される。\n\n'
        'なお、Windowsの音声認識APIには認識する言語を指定する手段が'
        '存在しないため、入力欄のロケール「$locale」はWindowsでは無視される'
        '(どの言語で認識されるかはOS側の設定に依存する。'
        'packages/offline_stt_windows/README.md §7 参照)。\n\n'
        'この通信で音声データや文字起こし結果が送信されることはない。';
  }
  if (_isAndroid) {
    // Issue #51。Androidで伝えるべきことは requirements.md §8 の文言
    // ガイドライン(一般名称で呼ぶ・サイズの目安に触れる)に加えて、
    // packages/offline_stt_android/README.md §4 制約1・制約2 の2点である。
    //   - ダウンロードはOS / Google Play services 側が行うこと
    //   - 完了が通知されないことがあるため、アプリ側で状態を確認し直すこと
    // **ダウンロードサイズの数値は書かない。** Androidの言語パックの
    // サイズは実測しておらず、根拠のない数値を出さない方針である
    // (Webの約60MBはWebでの実測値であって、Androidへ外挿できない)。
    return '文字起こしを行うには、ロケール「$locale」向けのオンデバイス'
        '音声認識モデル(言語パック)をこの端末にダウンロードする必要がある。'
        'アプリ自体のサイズは増えない。\n\n'
        'ダウンロードはOS(Google Play services)側が行い、モデルもOSが'
        '管理する。ダウンロードサイズの目安はロケール・端末によって異なり、'
        'このアプリからは分からない。\n\n'
        'ダウンロードの完了がOSから通知されない場合があることが実測で'
        '判明しているため、このアプリは完了後にモデルの状態を自分で'
        '確認し直す。そのため完了表示までに多少の時間差が出ることがある。'
        '\n\n'
        'この通信で音声データや文字起こし結果が送信されることはない。';
  }
  return '文字起こしを行うには、ロケール「$locale」向けの音声認識モデルを'
      'ダウンロードする必要がある。このモデルはOS(またはブラウザ)が'
      '管理し、端末に保存される。アプリ自体のサイズは増えない。\n\n'
      'ダウンロードサイズの目安: 約60MB(Webの場合)。Android / iOS / '
      'macOSでは各OSがモデルを管理するため、実際の目安はこれと異なる。\n\n'
      'この通信で音声データや文字起こし結果が送信されることはない。';
}
