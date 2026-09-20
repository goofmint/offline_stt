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
Future<bool> showDownloadConsentDialog(
  BuildContext context, {
  required String locale,
}) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('音声認識モデルのダウンロード'),
        content: Text(
          '文字起こしを行うには、ロケール「$locale」向けの音声認識モデルを'
          'ダウンロードする必要がある。このモデルはOS(またはブラウザ)が'
          '管理し、端末に保存される。アプリ自体のサイズは増えない。\n\n'
          'ダウンロードサイズの目安: 約60MB(Webの場合)。Android / iOS / '
          'macOS / Windowsでは各OSがモデルを管理するため、実際の目安は'
          'これと異なる。\n\n'
          'この通信で音声データや文字起こし結果が送信されることはない。',
        ),
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
