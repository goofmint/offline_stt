# offline_stt の使い方

録音済み音声ファイルを、OSネイティブの音声認識APIだけでオフライン文字起こしする。
アプリが依存するのは `offline_stt` だけでよい(実装パッケージは
`flutter.plugin.platforms.*.default_package` によって自動的に選択される)。

完全に動作する参照実装(ファイルピッカー・同意ダイアログ・進行表示まで)は
リポジトリの [`apps/example`](https://github.com/goofmint/offline_stt/tree/main/apps/example)
にある。

## 依存

```yaml
dependencies:
  offline_stt: ^0.1.0
```

## 最小のコード

```dart
import 'package:offline_stt/offline_stt.dart';

Future<String> transcribe(String path, String locale) async {
  const transcriber = OfflineTranscriber();

  // 1. モデルの状態を確認する。ライブラリは暗黙にダウンロードしない。
  var state = await transcriber.checkModel(locale);

  if (state == ModelState.downloadable) {
    // 2. アプリ側で同意を取ってから取得する(同意UIはアプリの責務)。
    //    文言は具体的なモデル名・ベンダー名を出さず「音声認識モデル」のような
    //    一般名称で呼ぶこと。
    await for (final progress in transcriber.downloadModel(locale)) {
      // fraction は進捗が取れないプラットフォームでは null になる。
      // 取れない場合に 0 などを代入して「取れたふり」をしないこと。
      final fraction = progress.fraction;
      if (fraction != null) {
        print('${(fraction * 100).toStringAsFixed(0)}%');
      }
    }
    state = await transcriber.checkModel(locale);
  }

  if (state != ModelState.available) {
    throw StateError('モデルが利用できない: $state');
  }

  // 3. 文字起こしする。確定(isFinal)のセグメントだけを積む。
  final buffer = StringBuffer();
  await for (final segment in transcriber.transcribeFile(
    TranscribeRequest(path: path, locale: locale),
  )) {
    if (segment.isFinal) {
      buffer.write(segment.text);
    }
  }
  return buffer.toString();
}
```

## 注意

- **認識セッションは同時に1本までである。** 実行中に2本目の `transcribeFile()`
  を呼ぶと `StateError` になる。
- **日本語の精度はしきい値に届いていない**(基準音声 `jaJP_10s` で 66.7%)。
  採用前に [README の「既知の制約」](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt/README.md#既知の制約採用前に読むこと)
  を読むこと。
- **Windows は v1 では対象外である。** 呼び出すとプラットフォーム実装が
  未登録のため `StateError` になる。
