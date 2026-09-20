import 'package:flutter/material.dart';

import 'src/home_page.dart';

/// `offline_stt` の example app。
///
/// ファイルピッカー → モデル状態表示 → ダウンロード同意ダイアログ →
/// 文字起こし進行表示、という参照実装(design.md §7「example app:
/// …の参照実装を兼ねる」、requirements.md §8)をIssue #32・#41で
/// 実装したものである。実際のUI・状態管理は `src/home_page.dart` に
/// 置き、本ファイルはアプリのエントリポイントのみを担う。
void main() {
  runApp(const OfflineSttExampleApp());
}

class OfflineSttExampleApp extends StatelessWidget {
  const OfflineSttExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'offline_stt example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const OfflineSttHomePage(),
    );
  }
}
