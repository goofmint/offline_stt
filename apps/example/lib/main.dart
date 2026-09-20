import 'package:flutter/material.dart';

/// offline_stt の example app(雛形)。
///
/// ファイルピッカー → モデル状態表示 → ダウンロード同意ダイアログ →
/// 文字起こし進行表示、という参照実装(design.md §7、tasks.md M1)は
/// Issue #32 で実装する。本ファイルは `flutter pub get` / モノレポ構成の
/// 雛形としてのみ存在する。
void main() {
  runApp(const OfflineSttExampleApp());
}

class OfflineSttExampleApp extends StatelessWidget {
  const OfflineSttExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'offline_stt example',
      home: Scaffold(
        appBar: AppBar(title: const Text('offline_stt example')),
        body: const Center(child: Text('機能実装はIssue #32で行う。')),
      ),
    );
  }
}
