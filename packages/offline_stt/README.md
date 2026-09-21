# offline_stt

> **v1 の対象は Android / iOS / macOS / Web の4つである。Windows は対象外。**
> `Microsoft.Windows.AI.Speech` が WinAppSDK の安定版に存在しないため
> (Windows 11 実機で確認)。Windows 上で呼び出すとプラットフォーム実装が
> 未登録のため `StateError` になる。詳細はリポジトリの README 冒頭を参照。

録音済み音声ファイルを、**OSネイティブの音声認識APIだけで**オフライン文字起こしするFlutterライブラリ。認識モデルも推論エンジンも同梱せず、モデルの取得・更新・削除はすべてOSに委ねる。音声も書き起こし結果もネットワークに出ない([requirements.md](https://github.com/goofmint/offline_stt/blob/main/requirements.md) NFR-2)。

**これはfederated pluginのエントリパッケージである。アプリが依存するのはこのパッケージだけでよい。** `offline_stt_android` / `offline_stt_darwin` / `offline_stt_web` は endorsed な実装パッケージであり、`flutter.plugin.platforms.*.default_package` によって自動的に選択される。直接依存に書く必要は無い(`offline_stt_windows` は **v1では endorsed に含めていない**。上記の対象外の説明を参照)([design.md](https://github.com/goofmint/offline_stt/blob/main/design.md) §1)。

---

## 対応プラットフォームとバックエンド

| プラットフォーム | バックエンドAPI | 最低OSバージョン |
|---|---|---|
| Android | 標準 `android.speech.SpeechRecognizer`(`createOnDeviceSpeechRecognizer`)+ MediaCodecデコード | Android 12 / API 31(ただし後述の制約により実質 API 33 以上) |
| iOS / macOS | `SpeechAnalyzer` + `SpeechTranscriber` + `AssetInventory` | iOS 26 / macOS 26 |
| ~~Windows~~ | — | **v1では対象外。** `Microsoft.Windows.AI.Speech` が WinAppSDK の安定版に存在しない(experimental チャンネルのみ)ことを Windows 11 実機で確認した。実装はリポジトリに残しているが公開しておらず、`flutter.plugin.platforms` からも外してある |
| Web | Chrome オンデバイス Web Speech(`processLocally: true`)+ Web Audio | Chrome 142 以上のデスクトップ版。localhost または https 配信であること |

Linuxは対象外である(OSネイティブのASR APIが存在しないため)。

各実装パッケージの詳細・セットアップ・既知の制約:

- [offline_stt_android/README.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_android/README.md)
- [offline_stt_darwin/README.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_darwin/README.md)
- [offline_stt_windows/README.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_windows/README.md)(**v1では対象外。公開していない**)
- [offline_stt_web/README.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_web/README.md)

## API

本パッケージは現在、[`offline_stt_platform_interface`](https://pub.dev/packages/offline_stt_platform_interface) が定義する型を再エクスポートしている。

- `ModelState`(`available` / `downloadable` / `downloading` / `unavailable`)
- `DownloadProgress` / `TranscribeRequest` / `TranscriptSegment`
- `TranscribeException`(sealed)とその派生: `ModelUnavailableException` / `LocaleUnsupportedException` / `DecodeFailedException` / `DeviceUnsupportedException` / `CancelledException` / `PlatformException_`

操作は3つである。

| メソッド | シグネチャ |
|---|---|
| モデル状態の確認 | `Future<ModelState> checkModel(String locale)` |
| モデル取得 | `Stream<DownloadProgress> downloadModel(String locale)` |
| 文字起こし | `Stream<TranscriptSegment> transcribeFile(TranscribeRequest request)` |

上記3メソッドは `OfflineTranscriber` が公開している。

```dart
import 'package:offline_stt/offline_stt.dart';

const transcriber = OfflineTranscriber();

final state = await transcriber.checkModel('ja-JP');
if (state == ModelState.downloadable) {
  // アプリ側で同意を取ってから呼ぶ(ライブラリは同意UIを出さない)。
  await for (final _ in transcriber.downloadModel('ja-JP')) {}
}
await for (final segment in transcriber.transcribeFile(
  TranscribeRequest(path: path, locale: 'ja-JP'),
)) {
  if (segment.isFinal) {
    // 確定テキスト
  }
}
```

`OfflineTranscriber` は `OfflineTranscriberPlatform.instance` へ委譲するだけの薄い層であり、独自のロジック・状態・既定値を持たない。**`offline_stt_platform_interface` を直接依存に書く必要はない。**

> 参照実装の [`apps/example`](https://github.com/goofmint/offline_stt/tree/main/apps/example) は、ファサードが無かった頃の名残で `offline_stt_platform_interface` を直接依存に書いている。利用側で真似する必要はない。

## 正しい呼び出し順序

```
checkModel(locale)
  ├─ available    → transcribeFile() を呼んでよい
  ├─ downloadable → 【アプリが同意UIを出す】→ 同意後に downloadModel()
  │                  → 完了後に再度 checkModel()
  ├─ downloading  → 待つ
  └─ unavailable  → 端末・OS・ブラウザの問題。アプリからは解消できない
```

**ライブラリは暗黙にモデルをダウンロードしない**(requirements.md FR-2 / §8)。同意UIはアプリ側の責務である。文言は具体的なモデル名・ベンダー名を出さず「音声認識モデル」のような一般名称で呼ぶこと。参照実装は [`apps/example/lib/src/download_consent_dialog.dart`](https://github.com/goofmint/offline_stt/blob/main/apps/example/lib/src/download_consent_dialog.dart) にある。

また、**認識セッションは同時に1本までである**(design.md §3)。実行中に2本目の `transcribeFile()` を呼ぶと `StateError` になる。

## アプリ側に必要な対応

| プラットフォーム | 依存を書く以外に必要なこと |
|---|---|
| Android | 無し(`RECORD_AUDIO` 権限も不要)。ただしモデル取得の同意UIはアプリ側 |
| iOS / macOS | 無し。同意UIはアプリ側 |
| Web | localhost または https 配信。同意UIはアプリ側 |
| ~~Windows~~ | **v1では対象外のため、アプリ側の対応も不要である。** Windows 上で呼び出すとプラットフォーム実装が未登録のため `StateError` になる |

Windows は v1 では対象外である。将来 `Microsoft.Windows.AI.Speech` が安定版に入った場合に必要となる手順(MSIXパッケージ化 + `systemAIModels` capability 宣言 + `winapp init`)は [offline_stt_windows/README.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_windows/README.md) に残してある。

## 既知の制約(採用前に読むこと)

- **日本語の精度がしきい値に届いていない。** design.md §7 のしきい値(クリーン基準音声 ja-JP は 95%以上で合格・90〜94%が条件付き合格)を満たしたプラットフォームは1つも無い。en-US では Android(Pixel 6)の `enUS_10s` が 100.0% で合格している。実測できた Darwin(macOS 26.5.1)/ Web(Chrome 153)/ Android(Pixel 6)の3つはいずれも基準音声 `jaJP_10s` で**ちょうど 66.7%(4/6)**であり、3つとも `株式会社モーンギフト` を落としている。

  **原因の切り分けは `jaJP_10s` についてだけ1つ進んでいる。** 2026-09-21 に design.md §7 の規定どおり許容表記を列挙し直して採点し直したところ、**`jaJP_10s` の 66.7% は1ポイントも動かなかった**(落としている2件は表記差ではなく誤認識であるため)。したがって **`jaJP_10s` に限っては「キーワード選定と正規化規則の不備」を原因候補から外せる**。一方、**同じ是正で長尺クリップの値は動いている**(Darwin の `jaJP_3m` は 39.3% → 42.9% / 28.6% → 32.1%、`enUS_3m` は 44.0% → 80.0%)。**長尺クリップについては、まだ表記差の影響を除外できていない。** いずれにせよ 10秒クリップの結果1件から「日本語全体が測定の問題ではない」とは結論できない。残る要因(基準音声がTTS合成音声であること、認識モデル自体の精度、プリセット選択)の切り分けも未実施である。「OSネイティブだから十分な精度が出る」と期待して採用してはいけない段階である。
- **最低OSバージョンが高い。** 特に iOS 26 / macOS 26 の下限は、採用できるユーザー母数を大きく制限する。
- **Windowsはv1の対象外である。** `Microsoft.Windows.AI.Speech` が WinAppSDK の安定版に存在しない(experimental チャンネルのみ)ことを Windows 11 実機で確認したため、`flutter.plugin.platforms` から windows を外し `offline_stt_windows` も公開していない。Windows 上で呼び出すとプラットフォーム実装が未登録のため `StateError` になる。
- **マイク入力のリアルタイム認識は対象外**である(v1はファイル入力専用)。
- **Linuxは対象外**である。
- 土台のOS APIにalpha / Experimental段階のものを含むため、0.x系で公開している(NFR-5)。

モデル同梱型(sherpa-onnx / whisper.cpp / Vosk 等)との使い分けは、[リポジトリルートのREADME](https://github.com/goofmint/offline_stt/blob/main/README.md)に比較軸をまとめてある。

## 実機E2Eの状況

認識のE2E(実際に音声ファイルが正しく文字起こしされること)はCIでは検証していない(実機・実ブラウザ依存であることが実測済みのため)。リリース前の手動チェックリストで運用する: [E2E_CHECKLIST.md](https://github.com/goofmint/offline_stt/blob/main/E2E_CHECKLIST.md)。

2026-09-21 に **Darwin(macOS 26.5.1 + iPad Pro / iOS 26.6.2)と Android(Pixel 6)で本番実装に対する実機E2Eを実行済み**である(Issue #40 / #50)。Darwin は手順1〜6が全て期待どおりで実装バグ0件、Android は初回に4件の不具合を発見し修正後は手順3が8/8成功した。**いずれも包含率はしきい値未達**である。

未実施として残るのは次の3つである。

- **example app の UI 経路**(ファイルピッカー → 同意ダイアログ → 進行表示)。`integration_test` は API を直接呼ぶため通っていない
- **Web の本番実装での再測定**(M0 スパイクでの実測のみ)
- **Windows**(v1対象外)

## ライセンス

MIT License。[LICENSE](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt/LICENSE) を参照。
