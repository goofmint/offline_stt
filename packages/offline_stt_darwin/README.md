# offline_stt_darwin

`offline_stt` の iOS / macOS 共用実装(Swift、`SpeechAnalyzer` + `SpeechTranscriber` + `AssetInventory`、デコードは `AVAudioFile`)。

このパッケージは federated plugin の実装パッケージであり、**利用者が直接依存するものではない**([requirements.md](https://github.com/goofmint/offline_stt/blob/main/requirements.md) §6 / [design.md](https://github.com/goofmint/offline_stt/blob/main/design.md) §1)。アプリ側は [`offline_stt`](https://pub.dev/packages/offline_stt) にのみ依存すれば、`offline_stt` の `flutter.plugin.platforms.ios` / `.macos` の `default_package` によって自動的にこの実装が使われる。

公開Dart APIは `OfflineSttDarwin` 1クラスのみで、これは `dartPluginClass` によりFlutterが自動登録する登録エントリである。アプリから直接インスタンス化するものではない。

---

## 1. 動作要件

| 項目 | 要件 |
|---|---|
| OS | **iOS 26 以上 / macOS 26 以上**(requirements.md NFR-4。`offline_stt_darwin.podspec` の deployment target も `26.0`) |
| 認識バックエンド | `SpeechAnalyzer` + `SpeechTranscriber`(Speech framework) |
| モデル管理 | `AssetInventory`(`installedLocales` / `AssetInstallationRequest`) |
| デコード | `AVAudioFile`(AVFoundation) |
| 実機 | **iOSは実機が必須。シミュレータでは動作しない**(§3) |

## 2. アプリ側に必要な対応

**追加のセットアップは不要である。** `offline_stt` を依存に書けばこの実装が選択される。Info.plist への追加宣言も、専用の entitlement も必要としない。

ただし**モデルダウンロードの同意UIはアプリ側の責務**である(requirements.md FR-2 / §8、design.md §3)。ライブラリは暗黙にモデルをダウンロードしない。

```
checkModel(locale)
  ├─ available    → transcribeFile() を呼んでよい
  ├─ downloadable → 【同意ダイアログを出す】→ 同意後に downloadModel()
  │                  → 完了後に再度 checkModel()
  ├─ downloading  → 待つ
  └─ unavailable  → 端末・OSの問題。アプリからは解消できない
```

同意文言は具体的なモデル名・ベンダー名を出さず「音声認識モデル」のような一般名称で呼ぶこと。参照実装は [`apps/example/lib/src/download_consent_dialog.dart`](https://github.com/goofmint/offline_stt/blob/main/apps/example/lib/src/download_consent_dialog.dart) にある。

なお `SpeechTranscriber` はバッチ認識であり、`TranscribeRequest.playbackRate` は**Web専用オプション**なのでDarwinでは無視される(速度という概念が無いため)。

## 3. 既知の制約

### 制約1: iOSシミュレータでは動作しない

**M0検証で確定している事実である。** シミュレータでは `SpeechTranscriber.isAvailable` が `false`、`supportedLocales` が0件、`AssetInventory.status` が `unsupported` を返す。`simctl spawn` による裸の実行ファイルと、正しく署名された `.app` バンドルの両方で同じ結果になったため、原因は起動方法(entitlement・コード署名・Info.plist宣言の欠如)ではなく、**シミュレータ自体にオンデバイス音声モデルが無いこと**である(`spikes/darwin/RESULTS.md`)。

したがって**認識の検証には iOS 実機が要る**。この制約は CI にもそのまま当てはまり、CIは `flutter build ios --no-codesign --debug` によるコンパイル検証しか行わない。

### 制約2: `supportedLocales` はOSバージョンで変わる

実測値は macOS 26.5.1 で30件、iOS 27.0 で45件だった。**あるロケールが対応しているかどうかを、別のOSバージョンでの結果から外挿することはできない。** 必ず `checkModel(locale)` を実行時に呼んで判定すること。

### 制約3: iOS 26 実機での確認は未実施である

requirements.md NFR-4 が定める下限は iOS 26 だが、確認できているのは **iPhone 17 / iOS 27.0** である。制約2のとおり `supportedLocales` はOSバージョンで変動するため、**iOS 27.0 の結果は iOS 26 の保証にならない。** これは Issue #7 として未解決のまま残っている。

### 制約4: iOSでのファイル処理速度は未測定である

macOS 26.5.1 実機では非実時間・高速に処理できることを実測している(RTF 0.008〜0.026、実時間の約38〜125倍速)。**iOS実機ではこの測定を行っていない。** iOS実機で確認したのは `supportedLocales` に ja-JP が含まれることだけであり、**文字起こし自体を実施していない。**

### 制約5: 精度がしきい値に届いていない

macOS 26.5.1 実機での実測は、基準音声 `jaJP_10s` で **66.7%(4/6)** であり、design.md §7 のしきい値(ja-JP は **95%以上が合格・90〜94%が条件付き合格**)に**達していない**。`株式会社モーンギフト` を「モーギフト」と誤認識している。en-US は `enUS_10s` 80.0% / `enUS_3m` **80.0%**(キーワードセット是正前は 44.0%。2026-09-21 に基準音声の許容表記を design.md §7 の規定どおりに列挙し直し、記録済みの確定テキストを採点し直した値である。**認識結果は変わっていない**)で、いずれもしきい値(95%以上)に達していない。

**この不成立の原因は未確定である。** 基準音声がTTS合成音声であること、キーワード選定と正規化規則が表記差を吸収できていないこと、認識モデル自体の精度、プリセット選択、のいずれが支配的かを分離する対照実験を行っていない。したがって「認識品質が低い」とも「基準音声の設計の問題」とも断定しない。

なお `SpeechTranscriber.Preset` の違いだけで包含率が最大20ポイント以上動く(`enUS_10s` は `.transcription` で100%に達した)ことが実測されており、包含率という指標自体が条件に強く依存する。

### 制約6: Swift 5 言語モードで固定している

`offline_stt_darwin.podspec` は `s.swift_version = '5.0'` を指定している。Swift 6 言語モード(strict concurrency)では、Pigeon が生成する `Pigeon.g.swift` のトップレベル `var`(`pigeonPigeonMethodCodec`)が `is not concurrency-safe because it is nonisolated global shared mutable state` としてコンパイルエラーになるためである。Pigeon 27.3.0 と 29.0.2 のどちらでも同じコードが生成されるため、Pigeon の更新では解決しない。Swift 5 モードでも async/await と actor は使えるため、`SpeechAnalyzer` 連携には支障がない。

## 4. 実機E2Eの状況

**本パッケージ(本番実装)に対して実機E2Eを通して実行した実績は無い。** 上記の実測値はいずれも M0 スパイク(`spikes/darwin/`)での測定である。

手順は [E2E_CHECKLIST.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_darwin/E2E_CHECKLIST.md) にある。実施は Issue #40(実機E2E)および Issue #7(iOS 26 実機)の対象である。

## 5. エラーの見分け方

design.md §5 のエラーマッピング表 Darwin 列に対応する。

| 例外 | Darwin での発生源 |
|---|---|
| `ModelUnavailableException` | モデル未取得の状態で `transcribeFile()` を呼んだ / `AssetInstallationRequest` の失敗 |
| `LocaleUnsupportedException` | `supportedLocales` に指定ロケールが無い |
| `DecodeFailedException` | `AVAudioFile` による読み込み・変換の失敗 |
| `DeviceUnsupportedException` | `SpeechTranscriber.isAvailable` が `false`(iOSシミュレータはここに落ちる) |
| `CancelledException` | 認識の中断(Streamのcancel) |
| `PlatformException_` | 上記のいずれにも分類できないもの |

## ライセンス

MIT License。[LICENSE](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_darwin/LICENSE) を参照。
