# offline_stt_android

`offline_stt` の Android 実装(Kotlin、Android標準の [`android.speech.SpeechRecognizer`](https://developer.android.com/reference/android/speech/SpeechRecognizer) によるオンデバイス認識)。

このパッケージは federated plugin の実装パッケージであり、**利用者が直接依存するものではない**([requirements.md](https://github.com/goofmint/offline_stt/blob/main/requirements.md) §6 / [design.md](https://github.com/goofmint/offline_stt/blob/main/design.md) §1)。アプリ側は [`offline_stt`](https://pub.dev/packages/offline_stt) にのみ依存すれば、`offline_stt` の `flutter.plugin.platforms.android.default_package` によって自動的にこの実装が使われる。

公開Dart APIは `OfflineSttAndroid` 1クラスのみで、これは `dartPluginClass` によりFlutterが自動登録する登録エントリである。アプリから直接インスタンス化するものではない。

---

## 1. 認識バックエンドについて(重要)

> **本パッケージが使うのは Android 標準の `android.speech.SpeechRecognizer`(オンデバイス)である。ML Kit GenAI / AICore ではない。**

当初設計は ML Kit GenAI Speech Recognition(AICore)を前提としていたが、**M0検証の結果この方針は破棄した。** 検証に使った Pixel 6 実機の `com.google.android.aicore` は `versionName = 0.stub.stub_aicore_...` という実体の無い stub 版であり、`checkStatus()` / `startRecognition()` はいずれも `PERMISSION_DENIED: Api access revoked.` を返した。Google Play ストア自身が Pixel 6 を非対応と表示する。端末側の制約でありアプリ側の実装では回避できないため、標準 `SpeechRecognizer` へ差し替えてある(`spikes/android/RESULTS.md`)。

**したがって「AICore の初期化を待つ」といったアプリ側の対応は不要である。** リポジトリ内に AICore / ML Kit GenAI を前提とした記述が残っている場合、それは古い記述である。

使用しているAPI:

| 用途 | API |
|---|---|
| 認識器の生成 | `SpeechRecognizer.createOnDeviceSpeechRecognizer()` |
| モデル状態の判定 | `SpeechRecognizer.checkRecognitionSupport()`(`RecognitionSupport` の4リスト) |
| モデル取得 | `SpeechRecognizer.triggerModelDownload()` |
| ファイル音声の入力 | `RecognizerIntent.EXTRA_AUDIO_SOURCE`(`ParcelFileDescriptor` パイプ) |
| デコード | `MediaExtractor` / `MediaCodec` → 16kHz・モノラル・16-bit PCM へリサンプリング |

## 2. 動作要件

| 項目 | 要件 |
|---|---|
| `minSdk` | **31**(Android 12。requirements.md NFR-4) |
| `compileSdk` | 35 |
| Java / Kotlin | `sourceCompatibility` 17 / Kotlin 2.1.0、AGP 8.7.0 |
| 端末 | **実機であること。** エミュレータにはオンデバイス認識のモデルが無い |

> **`minSdk` は 31 だが、API 31 / 32 では常に `unavailable` になる。** モデル状態の判定に使う `checkRecognitionSupport()` は **API 33(TIRAMISU)で追加されたAPI** であり、API 31/32 では `RecognitionSupport` の4リストを取得する手段が無い。本実装はここでフォールバックせず、明示的に `ModelState.unavailable` を返す(`android/src/main/kotlin/.../ModelAvailability.kt`)。**実質的に API 33 以上が必要である。**

## 3. アプリ側に必要な対応

### `minSdk` を 31 以上にする

アプリの `android/app/build.gradle.kts`(または `build.gradle`)の `minSdk` を 31 以上にすること。Flutter の既定値(24)のままだと、マニフェストのマージが次のエラーで失敗する。

```
uses-sdk:minSdkVersion 24 cannot be smaller than version 31 declared in library [:offline_stt_android]
```

### パーミッションは不要

**`RECORD_AUDIO` 権限は必要ない。** 本実装はマイクを使わず、`EXTRA_AUDIO_SOURCE` で `ParcelFileDescriptor` パイプ経由にデコード済みPCMを流し込む。プラグインの `AndroidManifest.xml` は空であり、パーミッションを一切追加しない。

### `checkModel()` を必ず先に呼ぶ

オンデバイス認識は、対象ロケールの言語パックが端末にダウンロードされていなければ動かない。**Pixel 6 実機での実測では、初期状態の `installedOnDeviceLanguages` は `[en-US]` のみで ja-JP は含まれていなかった。**

```
checkModel(locale)
  ├─ available    → transcribeFile() を呼んでよい
  ├─ downloadable → 【同意ダイアログを出す】→ 同意後に downloadModel()
  │                  → 完了後に再度 checkModel()
  ├─ downloading  → 待つ(pendingOnDeviceLanguages に入っている状態)
  └─ unavailable  → API 32以下 / 対象ロケール非対応 / 端末非対応
```

**ライブラリは暗黙にモデルをダウンロードしない**(requirements.md FR-2 / §8)。同意UIはアプリ側の責務であり、文言は具体的なモデル名・ベンダー名を出さず「音声認識モデル」のような一般名称で呼ぶこと。参照実装は [`apps/example/lib/src/download_consent_dialog.dart`](https://github.com/goofmint/offline_stt/blob/main/apps/example/lib/src/download_consent_dialog.dart) にある。

## 4. 既知の制約

### 制約1: 処理は実時間かかる

**Androidは実時間方式である。** `EXTRA_AUDIO_SOURCE` のパイプへ実時間レートで供給する必要があるため、**ファイル長と同等の時間がかかる。** Pixel 6 実機の実測では、9.56秒の音声に対しポンプが 9,564ms、実効 31,993.7 バイト/秒(16kHz・モノラル・16-bit PCM の理論値 32,000 バイト/秒にほぼ一致)だった。

長時間の音声ではその長さ分だけ待つことになる。バッチ認識である Darwin とはこの点が根本的に異なるので、UI の進行表示はこの前提で設計すること。

`TranscribeRequest.playbackRate` は**Web専用オプション**である。実時間ポンプ方式のAndroidには理論上は適用余地があるが、**未実装・未検証**であり、現状は無視される。

### 制約2: `triggerModelDownload()` の完了通知は当てにできない

`ModelDownloadListener` は**ダウンロード完了を確実には通知しない**ことが実測で判明している。Pixel 6 実機で `onSuccess()` を一度も観測できないまま、実際にはダウンロードが完了していた。

完了判定は `checkRecognitionSupport()` の `installedOnDeviceLanguages` を再照会することによってのみ確実に行える。**本プラグインはこの方式(ポーリング)で実装している。** アプリ側は `downloadModel()` の完了後に必ず `checkModel()` で `available` を確認してから `transcribeFile()` へ進むこと。

### 制約3: 端末による差が大きく、Pixel 6 以外は未検証である

M0検証で確認できたのは **Pixel 6 単一機種**である。`SpeechRecognizer.isOnDeviceRecognitionAvailable()` が `true` を返すか、対象ロケールが `supportedOnDeviceLanguages` に含まれるかは端末に依存し、**含まれない端末が存在しうる。** AICore の件(§1)が示すとおり、「実機さえあれば検証できる」という前提そのものが誤りであったことが実測で示されている。

### 制約4: 精度がしきい値に届いていない

Pixel 6(Android 17 / API 37)実機での実測は、基準音声 `jaJP_10s` で **66.7%(4/6)** であり、design.md §7 のしきい値(ja-JP は **95%以上が合格・90〜94%が条件付き合格**)に**達していない**。`株式会社モーンギフト` を「モンギフト」と誤認識している。

**この不成立の原因は未確定である。** ただし `jaJP_10s` に限っては、原因候補を1つ外せている。2026-09-21 に design.md §7 の規定どおり基準音声の許容表記を列挙し直し、記録済みの確定テキストを採点し直したが、**`jaJP_10s` の 66.7% は前後で変わらなかった**(落としている2件は表記差ではなく誤認識であるため)。したがって **`jaJP_10s` については「キーワード選定と正規化規則が表記差を吸収できていないこと」は原因ではない**。残る候補(基準音声がTTS合成音声であること、認識モデル自体の精度)を分離する対照実験は行っていない。

**この結論は `jaJP_10s` に限られる。** 長尺クリップは別である。`jaJP_3m.wav` は是正の前後どちらも 17.9%(5/28)で変わらなかったが、`jaJP_3m.m4a` は確定テキストを本書に逐語記録していないため**再採点できておらず**、表記差の影響を除外できていない。

en-US は `enUS_10s`(.wav / .m4a / 44.1kHz ステレオ .m4a)が **100.0% でしきい値(95%以上)を満たしている**。`enUS_3m.wav` は是正後 12.0%(3/25)で不成立である。詳細は [E2E_RESULTS.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_android/E2E_RESULTS.md) を参照。

## 5. 実機E2Eの状況

**本パッケージ(本番実装)に対して実機E2Eを通して実行した実績は無い。** 上記の実測値はいずれも M0 検証(`spikes/android/`)での測定である。

手順は [E2E_CHECKLIST.md](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_android/E2E_CHECKLIST.md) にある。実施は Issue #50 の対象である。

CIが検証するのは `apps/example` の `flutter build apk --debug`(コンパイル)だけであり、認識E2Eは検証しない。

## 6. エラーの見分け方

design.md §5 のエラーマッピング表 Android 列に対応する。

| 例外 | Android での発生源 |
|---|---|
| `ModelUnavailableException` | モデル未取得の状態で `transcribeFile()` を呼んだ / `triggerModelDownload()` の失敗 |
| `LocaleUnsupportedException` | 対象ロケールが `supportedOnDeviceLanguages` に無い |
| `DecodeFailedException` | `MediaExtractor` / `MediaCodec` によるデコード・リサンプリングの失敗 |
| `DeviceUnsupportedException` | オンデバイス認識が利用できない端末・API水準 |
| `CancelledException` | 認識の中断(Streamのcancel) |
| `PlatformException_` | 上記のいずれにも分類できないもの |

## ライセンス

MIT License。[LICENSE](https://github.com/goofmint/offline_stt/blob/main/packages/offline_stt_android/LICENSE) を参照。
