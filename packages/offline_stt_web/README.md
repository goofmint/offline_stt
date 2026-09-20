# offline_stt_web

`offline_stt` の Web 実装(Dart JS interop、Chrome の**オンデバイス** Web Speech API + Web Audio)。

このパッケージは federated plugin の実装パッケージであり、**利用者が直接依存するものではない**([requirements.md](https://github.com/goofmint/offline_stt/blob/main/requirements.md) §6 / [design.md](https://github.com/goofmint/offline_stt/blob/main/design.md) §1)。アプリ側は [`offline_stt`](https://pub.dev/packages/offline_stt) にのみ依存すれば、`offline_stt` の `flutter.plugin.platforms.web.default_package` によって自動的にこの実装が使われる。

公開Dart APIは `OfflineSttWeb` 1クラスのみで、これはFlutterのWebプラグイン登録エントリである。アプリから直接インスタンス化するものではない。Pigeonは使わず `package:web` + `dart:js_interop` のみで構成している(design.md §2.3)。

---

## 1. 動作要件

| 項目 | 要件 |
|---|---|
| ブラウザ | **Chrome 142 以上のデスクトップ版**(オンデバイスWeb Speechのリグレッションが修正されたバージョン。requirements.md NFR-4)。実機検証は Chrome 153 |
| 配信元 | **localhost または https** であること |
| 認識バックエンド | `SpeechRecognition.available()` / `install()` / `start(audioTrack)` + `processLocally: true` |
| デコード | Web Audio(`AudioContext.decodeAudioData` → `MediaStreamAudioDestinationNode`) |

**`processLocally: true` は常に強制する。** サーバー認識へのサイレントフォールバックは行わない(NFR-2)。音声も書き起こし結果もネットワークに出ない。

## 2. アプリ側に必要な対応

### localhost または https で配信する

`on-device-speech-recognition` Permissions Policy の既定値が `'self'` であるため、**`file://` でビルド成果物を直接開いても動作しない。** `flutter run -d chrome` や `flutter build web` の成果物をローカルHTTPサーバーで配信すること。

### ファイル選択はユーザー操作起点であること

Web では `TranscribeRequest.path` に **Blob URL(ObjectURL)** を渡す(design.md §2.2)。`<input type="file">` 等のユーザー操作で得た File / Blob から生成すること。参照実装は [`apps/example/lib/src/object_url_web.dart`](https://github.com/goofmint/offline_stt/blob/main/apps/example/lib/src/object_url_web.dart) にある(条件付きexportで非Webビルドから除外している)。

### Chrome 以外の扱いを用意する

**Chrome 以外のブラウザでは `checkModel()` が `unavailable` を返す。** オンデバイスWeb Speech(`available()` / `install()` / `start(audioTrack)` + `processLocally`)は現時点で Chrome 系の機能であり、それ以外のブラウザでは機能検出の時点で成立しない。アプリ側は `unavailable` を「この環境では使えない」として提示する導線を用意すること。**ライブラリはサーバー認識へフォールバックしない**(NFR-2)。

### モデル取得の同意UI

**ライブラリは暗黙にモデルをダウンロードしない**(requirements.md FR-2 / §8)。

```
checkModel(locale)
  ├─ available    → transcribeFile() を呼んでよい
  ├─ downloadable → 【同意ダイアログを出す】→ 同意後に downloadModel()
  │                  → 完了後に再度 checkModel()
  ├─ downloading  → 待つ
  └─ unavailable  → Chrome以外 / 対象ロケール非対応
```

同意文言は具体的なモデル名・ベンダー名を出さず「音声認識モデル」のような一般名称で呼ぶこと。参照実装は [`apps/example/lib/src/download_consent_dialog.dart`](https://github.com/goofmint/offline_stt/blob/main/apps/example/lib/src/download_consent_dialog.dart) にある。

## 3. 既知の制約

### 制約1: 言語パックは約60MBで、進捗は不定進捗になる

言語パックは約60MBあり、Chrome 153 の実測では `install()` に **8.7秒**かかった。`install()` は**進捗イベントを持たず `Promise<boolean>` を返すだけ**であるため、`downloadModel()` が返す `DownloadProgress` は Web では常に `fraction: null`(不定進捗)である。アプリ側は不定進捗のプログレスインジケータを出すこと。

### 制約2: 処理は実時間かかる

Web は再生しながら認識する実時間方式である。Chrome 153 の実測では 9.56秒の音声に **9,676ms** かかった。

### 制約3: `playbackRate` で短縮できるが、精度が落ちる

`TranscribeRequest.playbackRate`(既定 1.0)は **Web専用のオプション**である(Darwin / Windows はバッチ認識で速度という概念が無く、Android は実時間ポンプ方式だが未実装のため、いずれも無視される)。

Chrome 153 での `jaJP_10s` 実測では、**所要時間は短縮される一方で精度は単調に低下した**。

| `playbackRate` | キーワード包含率 |
|---|---|
| 1.0x | 66.7% |
| 1.5x | 50.0% |
| 2.0x | 33.3% |

`AudioBufferSourceNode.playbackRate` はピッチも同倍率で変えるためである。**所要時間と精度のトレードオフを理解したうえで使うこと。**

### 制約4: 確定結果は形態素単位で空白区切りされる

確定(final)結果は `東京 都 渋谷 で ...` のように形態素単位で空白区切りされて返る。日本語として自然な表記が要る場合、アプリ側で処理すること。

### 制約5: 精度がしきい値に届いていない

Chrome 153 での実測は、基準音声 `jaJP_10s`(1.0x)で **66.7%(4/6)** であり、design.md §7 のしきい値(ja-JP 90%以上)に**達していない**。`株式会社モーンギフト` を「ムーンギフト」と誤認識している。

**この不成立の原因は未確定である。** 基準音声がTTS合成音声であること、キーワード選定と正規化規則が表記差を吸収できていないこと、認識モデル自体の精度、のいずれが支配的かを分離する対照実験を行っていない。したがって「認識品質が低い」とも「基準音声の設計の問題」とも断定しない。

en-US は未検証である。

### 制約6: 自動化制御下のブラウザでは動作しない

**CDP(Chrome DevTools Protocol)管理下のクリーンな一時プロファイルではオーディオレンダリングが動作しない**という実測結果がある。M0検証で `decodeAudioData → MediaStreamAudioDestinationNode → start(audioTrack)` のパイプラインを自動化ハーネスから実行したところ、`AudioContext.currentTime` が 0.01 秒で停止したまま進行せず、`AudioBufferSourceNode` が再生されず、認識結果もエラーも一切得られなかった。`--autoplay-policy=no-user-gesture-required` 等のフラグや複数の起動方法を試したが再現しなかった。通常の対話的Chromeセッションでのみ動作した(`spikes/web/RESULTS.md`)。

この制約はCI環境にもそのまま当てはまるため、**Webの認識E2EはCIに載せられない。**

## 4. E2Eの状況

**本パッケージ(本番実装)に対してE2Eチェックリストを通して実行した実績は無い。** 上記の実測値はいずれも M0 検証(`spikes/web/`)での測定である。

手順は [E2E_CHECKLIST.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_web/E2E_CHECKLIST.md) にある。CIが検証するのは `apps/example` の `flutter build web`(コンパイル)だけである。

## 5. エラーの見分け方

Web は `SpeechRecognitionErrorEvent.error` の文字列から写像する。**design.md §5 どおりに対応づくのは `language-not-supported` のみ**であり、残りはエラー名から意味を推測せず `PlatformException_` としてコードをそのまま伝える方針である(`lib/src/speech_error_mapping.dart`)。

| 例外 | Web での発生源 |
|---|---|
| `LocaleUnsupportedException` | `SpeechRecognitionErrorEvent.error` が `language-not-supported` |
| `DecodeFailedException` | `AudioContext.decodeAudioData` の失敗 |
| `ModelUnavailableException` | `available()` が `available` 以外の状態で `transcribeFile()` を呼んだ |
| `PlatformException_` | 上記以外のすべての `SpeechRecognitionErrorEvent.error`、および `install()` が `false` に解決した場合(`code: 'install-resolved-false'`) |
| `CancelledException` | **発生しない**(下記) |

**Webは `CancelledException` を送出しない。** Dart の `Stream.cancel()` は購読者自身がこれ以上イベントを受け取らないと決めた結果であり、`cancel()` が返った時点でそのStreamにはもはや誰もlistenしていない。`CancelledException` を `addError()` しても受け取る相手が存在しないため、Web実装はキャンセル時に下層リソースの解放のみを行う。

## ライセンス

MIT License。[LICENSE](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_web/LICENSE) を参照。
