# RESULTS.md — Android M0 検証結果

対応 Issue: #11 / #12 / #13 / #14。対応する設計: design.md §4.3 Android、§5 エラーマッピング、
§7 評価基準、§8 未決事項5・6。

**このファイルは部分的な実機検証結果である。** Issue #14(MediaCodec デコード出力レート調査)は
エミュレータ上で実際に実行し、基準音声8ファイル + 実環境相当音源7ファイルの計15ファイル全ての
実測値を記載している。Issue #11 / #12 / #13(ML Kit GenAI Speech Recognition による認識そのもの)は、
AICore の実行にエミュレータが対応していないため **(未実施 — 実機未接続。下記「実行環境の制約」参照)**
である。

## 検証環境

| 項目 | 値 |
|---|---|
| 実行日時 | 2026-09-20 (JST) |
| ホストOS | macOS 26.5.1 (build 25F80), arm64 |
| JDK | Temurin/Homebrew OpenJDK 17 (`/opt/homebrew/opt/openjdk@17`) |
| Android Gradle Plugin | 9.4.1 |
| Gradle (Wrapper) | 9.6.0 |
| compileSdk / targetSdk / minSdk | 36 / 36 / 31 |
| ML Kit ライブラリ | `com.google.mlkit:genai-speech-recognition:1.0.0-alpha1`(依存: `com.google.mlkit:genai-common:1.0.0-beta3`) |
| 実行デバイス (Issue #14) | AVD名 `Android`、`sdk_gphone64_arm64` (Google)、Android 16 / API 36、エミュレータ (物理端末ではない) |
| 実行デバイス (Issue #11/#12/#13) | (未実施 — 実機未接続) |
| adb devices | `emulator-5554  device` のみ。物理端末は接続されていない |
| ffmpeg / ffprobe (fixtures生成) | ffmpeg 8.1.1 (Homebrew, `/opt/homebrew/bin/ffmpeg`) |

## Issue #14: MediaCodec デコード出力レート調査 (実測)

### この調査には既知の限界があった(循環論法)

当初の検証(本ファイルの旧版)は `test-assets/baseline-audio/` の8ファイルのみを対象にしていた。
しかしこれらは `test-assets/baseline-audio/generate.sh` が **16kHz・モノラルで生成したもの**である
(同スクリプトの `ffmpeg -ar 16000 -ac 1 ...` 参照)。16kHz・モノラルの入力をMediaCodecでデコードして
16kHz・モノラルの出力が得られること自体は当然であり、これのみをもって「リサンプリング不要」と
結論づけるのは**循環論法**である。実際にユーザーが持ち込む音源(ボイスメモ、会議録音等)は
44.1kHzや48kHzのステレオが一般的であり、そちらこそが本来の調査対象である。

この限界を解消するため、`fixtures/generate-rate-fixtures.sh` を新規作成し、
`test-assets/baseline-audio/jaJP_10s.wav`(16kHz/モノラル)を入力として、ffmpegで実環境に近い
サンプルレート・チャンネル数・コーデック/コンテナの組み合わせ(44.1kHz/48kHzステレオ、mp3、
22.05kHz、8kHzの計7ファイル)を生成し、同じ `MediaCodecDecodeRateTest` で計測した。結果は
「実環境相当音源の結果(実測)」節を参照。

`./gradlew connectedAndroidTest` を実行し、`MediaCodecDecodeRateTest` の15テストケース全てが
成功した(JUnit XML: `failures="0" errors="0" skipped="0"`、`tests="15"`、実行時間 15.914秒)。
ここでの「成功」はJUnitレベルでのテスト成功(例外を投げずに計測を完了したこと)を意味し、
`resampleNeeded` の値そのものはテストの合否条件にしていない(調査であって要件検証ではないため)。

### クリップ別結果(基準音声。16kHz・モノラルで生成 — 上記「既知の限界」参照)

| クリップID | 形式 | 入力mime | 入力サンプルレート | 入力ch | 出力サンプルレート | 出力ch | 出力PCM形式 | 出力バイト数 | 実効サンプルレート(検算) | `.json`期待値(16000/mono)との一致 | リサンプリング要否 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| jaJP_10s | wav | audio/raw | 16000 | 1 | **16000** | **1** | PCM_16BIT (=2) | 305,988 | 16,600.9 Hz | 一致 | 不要 |
| jaJP_10s | m4a | audio/mp4a-latm | 16000 | 1 | **16000** | **1** | (未設定→16bit既定) | 307,200 | 16,107.4 Hz | 一致 | 不要 |
| jaJP_3m  | wav | audio/raw | 16000 | 1 | **16000** | **1** | PCM_16BIT (=2) | 5,607,568 | 16,012.1 Hz | 一致 | 不要 |
| jaJP_3m  | m4a | audio/mp4a-latm | 16000 | 1 | **16000** | **1** | (未設定→16bit既定) | 5,609,472 | 16,005.8 Hz | 一致 | 不要 |
| enUS_10s | wav | audio/raw | 16000 | 1 | **16000** | **1** | PCM_16BIT (=2) | 380,712 | 16,899.5 Hz | 一致 | 不要 |
| enUS_10s | m4a | audio/mp4a-latm | 16000 | 1 | **16000** | **1** | (未設定→16bit既定) | 380,928 | 16,086.5 Hz | 一致 | 不要 |
| enUS_3m  | wav | audio/raw | 16000 | 1 | **16000** | **1** | PCM_16BIT (=2) | 5,642,538 | 16,018.3 Hz | 一致 | 不要 |
| enUS_3m  | m4a | audio/mp4a-latm | 16000 | 1 | **16000** | **1** | (未設定→16bit既定) | 5,644,288 | 16,005.8 Hz | 一致 | 不要 |

生ログ(1行1JSON、`adb logcat -s OfflineSttSpike.M14Result` で回収した内容そのもの):

```
{"clip":"jaJP_10s","format":"wav","inputMime":"audio/raw","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputPcmEncoding":2,"outputBytes":305988,"durationUs":9216000,"effectiveSampleRate":16600.911458333336,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
{"clip":"jaJP_10s","format":"m4a","inputMime":"audio/mp4a-latm","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputBytes":307200,"durationUs":9536000,"effectiveSampleRate":16107.382550335571,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
{"clip":"jaJP_3m","format":"wav","inputMime":"audio/raw","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputPcmEncoding":2,"outputBytes":5607568,"durationUs":175104000,"effectiveSampleRate":16012.107090643274,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
{"clip":"jaJP_3m","format":"m4a","inputMime":"audio/mp4a-latm","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputBytes":5609472,"durationUs":175232000,"effectiveSampleRate":16005.843681519358,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
{"clip":"enUS_10s","format":"wav","inputMime":"audio/raw","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputPcmEncoding":2,"outputBytes":380712,"durationUs":11264000,"effectiveSampleRate":16899.502840909092,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
{"clip":"enUS_10s","format":"m4a","inputMime":"audio/mp4a-latm","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputBytes":380928,"durationUs":11840000,"effectiveSampleRate":16086.486486486487,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
{"clip":"enUS_3m","format":"wav","inputMime":"audio/raw","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputPcmEncoding":2,"outputBytes":5642538,"durationUs":176128000,"effectiveSampleRate":16018.287836119187,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
{"clip":"enUS_3m","format":"m4a","inputMime":"audio/mp4a-latm","inputSampleRate":16000,"inputChannels":1,"outputSampleRate":16000,"outputChannels":1,"outputBytes":5644288,"durationUs":176320000,"effectiveSampleRate":16005.807622504537,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":false}
```

### 実環境相当音源の結果(実測。`fixtures/generate-rate-fixtures.sh` の生成物)

`test-assets/baseline-audio/jaJP_10s.wav`(16kHz/モノラル)から ffmpeg で生成した、44.1kHz/48kHz
ステレオ・mp3・22.05kHz・8kHzの計7ファイルの実測結果である。いずれも `bash
spikes/android/fixtures/generate-rate-fixtures.sh` 実行後、同一の `connectedAndroidTest` 実行で
基準音声8ファイルと合わせて計測した(実行環境は上記「検証環境」と同一)。

| クリップID | 形式 | 入力mime | 入力サンプルレート | 入力ch | 出力サンプルレート | 出力ch | 出力PCM形式 | 出力バイト数 | `.json`期待値(16000/mono)との一致 | リサンプリング要否 |
|---|---|---|---|---|---|---|---|---|---|---|
| rate_44100_stereo | wav | audio/raw | 44100 | 2 | **44100** | **2** | PCM_16BIT (=2) | 1,686,760 | 不一致 | **要** |
| rate_44100_stereo | m4a | audio/mp4a-latm | 44100 | 2 | **44100** | **2** | (未設定→16bit既定) | 1,687,528 | 不一致 | **要** |
| rate_44100_stereo | mp3 | audio/mpeg | 44100 | 2 | **44100** | **2** | (未設定→16bit既定) | 1,686,760 | 不一致 | **要** |
| rate_48000_stereo | wav | audio/raw | 48000 | 2 | **48000** | **2** | PCM_16BIT (=2) | 1,835,928 | 不一致 | **要** |
| rate_48000_stereo | m4a | audio/mp4a-latm | 48000 | 2 | **48000** | **2** | (未設定→16bit既定) | 1,839,080 | 不一致 | **要** |
| rate_22050_mono | wav | audio/raw | 22050 | 1 | **22050** | **1** | PCM_16BIT (=2) | 421,690 | 不一致 | **要** |
| rate_8000_mono | wav | audio/raw | 8000 | 1 | **8000** | **1** | PCM_16BIT (=2) | 152,994 | 不一致 | **要** |

生ログ(1行1JSON、`adb logcat -s OfflineSttSpike.M14Result` で回収した内容そのもの):

```
{"clip":"rate_44100_stereo","format":"wav","inputMime":"audio/raw","inputSampleRate":44100,"inputChannels":2,"outputSampleRate":44100,"outputChannels":2,"outputPcmEncoding":2,"outputBytes":1686760,"durationUs":9473741,"effectiveSampleRate":44511.45540077568,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":true}
{"clip":"rate_44100_stereo","format":"m4a","inputMime":"audio/mp4a-latm","inputSampleRate":44100,"inputChannels":2,"outputSampleRate":44100,"outputChannels":2,"outputBytes":1687528,"durationUs":9543401,"effectiveSampleRate":44206.67223351508,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":true}
{"clip":"rate_44100_stereo","format":"mp3","inputMime":"audio/mpeg","inputSampleRate":44100,"inputChannels":2,"outputSampleRate":44100,"outputChannels":2,"outputBytes":1686760,"durationUs":9586938,"effectiveSampleRate":43985.889968204654,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":true}
{"clip":"rate_48000_stereo","format":"wav","inputMime":"audio/raw","inputSampleRate":48000,"inputChannels":2,"outputSampleRate":48000,"outputChannels":2,"outputPcmEncoding":2,"outputBytes":1835928,"durationUs":9557333,"effectiveSampleRate":48024.0669651251,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":true}
{"clip":"rate_48000_stereo","format":"m4a","inputMime":"audio/mp4a-latm","inputSampleRate":48000,"inputChannels":2,"outputSampleRate":48000,"outputChannels":2,"outputBytes":1839080,"durationUs":9557333,"effectiveSampleRate":48106.51674478644,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":true}
{"clip":"rate_22050_mono","format":"wav","inputMime":"audio/raw","inputSampleRate":22050,"inputChannels":1,"outputSampleRate":22050,"outputChannels":1,"outputPcmEncoding":2,"outputBytes":421690,"durationUs":8916462,"effectiveSampleRate":23646.710993665427,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":true}
{"clip":"rate_8000_mono","format":"wav","inputMime":"audio/raw","inputSampleRate":8000,"inputChannels":1,"outputSampleRate":8000,"outputChannels":1,"outputPcmEncoding":2,"outputBytes":152994,"durationUs":8192000,"effectiveSampleRate":9338.0126953125,"expectedSampleRate":16000,"expectedChannels":1,"resampleNeeded":true}
```

### 所見

- **基準音声(16kHz・モノラル生成)8ファイル全てで出力 `MediaFormat` の `KEY_SAMPLE_RATE=16000` /
  `KEY_CHANNEL_COUNT=1` を確認した。** design.md §4.3 の目標形式(16kHz・モノラル)と完全に一致する。
  ただしこれは入力自体が16kHz・モノラルであることの当然の帰結であり(「既知の限界」参照)、
  単独では「リサンプリング不要」の根拠にならない。
- **実環境相当音源7ファイル全てで、出力 `MediaFormat` のサンプルレート・チャンネル数は入力側と
  完全に一致し、16kHz・モノラルへは変換されなかった。** すなわち `rate_44100_stereo.wav` は
  44100Hz・2chのまま、`rate_8000_mono.wav` は8000Hz・1chのまま出力された。**MediaCodecはサンプル
  レート変換やダウンミックスを一切行わない**ことが実測から確認できる。7ファイル全てで
  `resampleNeeded=true` となった。
- wav(`audio/raw` mime、`OMX.google.raw.decoder` 相当のパススルー的デコーダ経由)は、入力側の
  `MediaFormat` に `pcm-encoding=2`(`AudioFormat.ENCODING_PCM_16BIT`)が明示されており、出力側
  `MediaFormat` にも `KEY_PCM_ENCODING=2` が明示されていた。
- m4a(`audio/mp4a-latm`、AAC)・mp3(`audio/mpeg`)は、出力側 `MediaFormat` に `KEY_PCM_ENCODING`
  キー自体が**存在しなかった**(ログの `outputPcmEncoding` が該当ファイルで `null`)。Android の
  ドキュメント上、`MediaCodec` の音声デコーダ出力はこのキーが無い場合 16-bit PCM がデフォルトという
  前提があり、実際に出力バイト数(例: jaJP_10s.m4a は 307,200 バイト = 9.6秒 × 16000Hz × 1ch ×
  2バイト、ほぼ一致)からもこの前提と整合する。
- 「実効サンプルレート(検算)」列は、出力バイト数を「入力側から供給した最後のサンプルの
  presentation timestamp」で割って算出したものであり、宣言値よりおおむね0〜7%程度高めに出ている
  (例: enUS_10s.wav で 16,899.5Hz、+5.6%。rate_22050_mono.wav で 23,646.7Hz、+7.2%)。これは検算
  方法自体の系統的なバイアスによるものである: 「最後に投入したサンプルの presentation timestamp」
  はそのサンプルの**開始**時刻であって、ストリーム全体の終了時刻ではないため、真の総再生時間を
  わずかに過小評価し、結果として計算上のサンプルレートが実際より高く出る。したがって**この列は
  真のリサンプリング要否判定には使っていない**。判定はあくまで `MediaFormat` が直接申告する
  `KEY_SAMPLE_RATE`/`KEY_CHANNEL_COUNT`(上表の「出力サンプルレート」「出力ch」列)を正としている。
  この方法論上の限界はREADME/コードコメントに記載済みである(`MediaCodecDecodeRateTest.kt` 参照)。
- logcat には `MediaCodec: Media Quality Service not found.` / `Codec2Client: query -- param
  skipped` 等の警告・エラーログが混在していたが、いずれもエミュレータのCodec2フレームワーク由来の
  ノイズであり、本テストの成否(15/15成功、実測値の整合性)には影響していない。

### design.md §8 未決事項6 に対する結論(実測に基づき是正)

**確定: Android実装にはリサンプリングが必須である。** design.md §4.3 の「リサンプリング:
MediaCodec出力が16kHz以外の場合は線形補間ではなくAudioResampler相当の処理が必要」という記述は、
本調査の実測により裏付けられた。

根拠: 実環境相当音源7ファイル(44.1kHz/48kHzステレオ、mp3、22.05kHz、8kHz)は、`MediaCodec`
出力側 `MediaFormat` のサンプルレート・チャンネル数が入力側と完全に一致しており、design.md §4.3の
目標形式(16kHz・モノラル)への変換は一切行われなかった(全7ファイルで `resampleNeeded=true`)。
これは `MediaCodec` がコーデックのデコードのみを担い、サンプルレート変換・チャンネルダウンミックス
を行わないという、ドキュメント上も想定される挙動と整合する。

旧結論(「8ファイル全てでリサンプリングは不要」)は、基準音声が16kHz・モノラルで生成されたもの
のみを対象にした循環論法であり撤回する。**M3実装ではdesign.md §4.3記載のAudioResampler相当の
リサンプリング処理(サンプルレート変換 + ステレオ→モノラルのダウンミックス)を実装しなければ、
44.1kHz/48kHzステレオのユーザー音源(ボイスメモ・会議録音等、実際に流通する音源の主流)を
ML Kit GenAI Speech Recognitionへ正しく供給できない。**

限界: 本結果はエミュレータ (`sdk_gphone64_arm64`, Android 16/API 36) 単一環境でのものであり、
実機・他のOEM/コーデック実装(ハードウェアデコーダ等)で挙動が異なる可能性は残る。ただし
「MediaCodecはコーデックのデコードのみを行いサンプルレート変換は行わない」という結論は
Android の `MediaCodec`/`MediaExtractor` APIの設計(デコーダの責務がコーデックのビットストリーム
展開に限定されること)から見ても妥当であり、実機で結果が反転する可能性は低いと考えられる。とはいえ
これは推測であり、実機での追試により確定させることが望ましい。

## Issue #11: MODE_BASIC + ja-JP 認識・キーワード包含率判定

**未達成。** エミュレータでは AICore 自体が動作しないため未実施だった(下記「実行環境の制約」参照)。
その後 Pixel 6 実機(API 37、ブートローダーロック済み)で実行したが、`checkStatus()` が
`PERMISSION_DENIED: Api access revoked.` を返し、キーワード包含率判定に必要な認識そのものに到達
しなかった(実測の詳細は「Pixel 6 実機での実測」節参照)。AICore が stub 版であることが原因であり、
本項目は依然として未達成である。

| クリップID | 形式 | 包含率 | 合否 | 所要時間 | 備考 |
|---|---|---|---|---|---|
| jaJP_10s | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |

コードは実装済み(`RecognitionHarness.runRecognition()` + `KeywordScoring.kt`)。ビルドは通っており
(`assembleDebug` 成功)、Pixel 6 実機へのインストール・起動・「Basic 認識実行」ボタンからの実行自体は
できたが、`checkStatus()` の時点で `PERMISSION_DENIED: Api access revoked.` となり認識には進めなかった。
実体のある AICore を搭載した実機での再実行が必要である。

## Issue #12: MODE_ADVANCED フォールバック挙動

**未達成。** エミュレータでは未実施だった(下記「実行環境の制約」参照)。Pixel 6 実機(API 37、
ブートローダーロック済み)で `preferredMode=MODE_ADVANCED` を指定して実行したところ、
`UNAVAILABLE: Peer process crashed, exited or was killed (binderDied)` が発生し、自動フォールバックの
有無を確認できなかった(実測の詳細は「Pixel 6 実機での実測」節参照)。

| 項目 | 値 |
|---|---|
| `preferredMode=MODE_ADVANCED` での `checkStatus()` | Pixel 6 実機: `UNAVAILABLE: Peer process crashed, exited or was killed (binderDied)` |
| 自動フォールバックの有無 | 未確認(上記エラーにより判定不能) |
| `MODE_BASIC` 手動リトライの結果 | Pixel 6 実機: `PERMISSION_DENIED: Api access revoked.`(Issue #11 と同一の失敗) |

コードは実装済み(`RecognitionHarness.runAdvancedFallbackCheck()`)。design.md §8 未決事項5 は
未確定のまま据え置く。

## Issue #13: PFDパイプ + 実時間ポンプの受理確認

**未達成。** エミュレータでは未実施だった(下記「実行環境の制約」参照)。Pixel 6 実機(API 37、
ブートローダーロック済み)で実行したが、`checkStatus()` が `PERMISSION_DENIED: Api access revoked.`
を返し `AVAILABLE` にならなかったため、ハーネスが `AudioSource.fromPfd()` 呼び出しの手前で処理を
終了した(実測の詳細は「Pixel 6 実機での実測」節参照)。

| 項目 | 値 |
|---|---|
| `AudioSource.fromPfd()` 受理可否 | 未到達(`checkStatus()` の時点で終了) |
| `startRecognition()` Flow 開始可否 | 未到達 |
| 最初の応答/エラー到達までの時間 | 未到達 |
| 実時間ポンプの実効送出レート実測 | 未到達 |

コードは実装済み(`RealtimePump.kt` + `RecognitionHarness.runRecognition()` のパイプ生成〜
`AudioSource.fromPfd()` 呼び出し部分)。受理成立の判定基準はREADME「受理成立の判定基準」節を参照。

## Android 総合判定

**Issue #14 のみ判定する(他は保留)。**

| 項目 | 値 |
|---|---|
| Issue #14 総合判定 | **成立(リサンプリング要)** — 基準音声8/8ファイルは出力16kHz・モノラルを確認したが、これは入力自体が16kHz・モノラルであることの当然の帰結(循環論法、上記参照)。実環境相当音源7/7ファイル(44.1kHz/48kHzステレオ、mp3、22.05kHz、8kHz)は全て出力が入力と同じサンプルレート・チャンネル数のままであり、16kHz・モノラルへの変換は一切行われなかった。**MediaCodecはリサンプリングを行わないため、design.md §4.3のAudioResampler相当の実装が必須。** |
| Issue #11 総合判定 | 保留(未実施) |
| Issue #12 総合判定 | 保留(未実施) |
| Issue #13 総合判定 | 保留(未実施) |

## エミュレータでの実測(Issue #11/#12/#13 の到達点)

**「エミュレータでは何も確認できない」わけではない。** 実際にアプリを起動して以下を実測した。

検証環境: エミュレータ `sdk_gphone64_arm64`、`Build.MANUFACTURER=Google`、`SDK_INT=36`、
`FINGERPRINT=google/sdk_gphone64_arm64/emu64a:16/BE2A.250530.026.F3/13894323:userdebug/dev-keys`。
実行日時: 2026-09-20 JST。

| 項目 | 結果 |
|---|---|
| アプリ起動・UI表示 | 成功 |
| 基準音声アセットの読み込み | 成功(`jaJP_10s.json`、locale=ja-JP、keywords=6件) |
| `SpeechRecognition.getClient().checkStatus()` | **`UNAVAILABLE`** |
| `UNAVAILABLE` → `MODEL_UNAVAILABLE` への写像 | 成功(design.md §5 の Android 列どおりに分類され、明確なエラーで停止した) |
| `AudioSource.fromPfd()` の受理(Issue #13) | **未到達**。`checkStatus()` が `AVAILABLE` でないため手前で中止する |
| MODE_BASIC + ja-JP の認識(Issue #11) | **未到達**(同上) |
| MODE_ADVANCED フォールバック(Issue #12) | **未到達**(同上) |

実行ログ(抜粋):

```
=== Basic 状態確認開始 ===
checkStatus() = UNAVAILABLE
=== Basic 状態確認終了 ===
=== runRecognition開始: locale=ja-JP mode=MODE_BASIC clip=jaJP_10s ===
checkStatus() 初回 = UNAVAILABLE
checkStatus() が MODEL_UNAVAILABLE 相当を示した (UNAVAILABLE)。
checkStatus() が AVAILABLE にならなかった (UNAVAILABLE)。認識は実行できない。
Basic: 受理不成立。error=null
```

**実測で確認できた事実**は、エミュレータ上で `checkStatus()` が `UNAVAILABLE` を返したこと、および本ハーネスの `RecognitionHarness` がそれを検出して処理を終了したことである。

`fromPfd()` に到達しないのは、**本ハーネスが `checkStatus()` の結果が `AVAILABLE` でない場合に認識を開始しないという制御を持っているため**である。ML Kit の公式例は `checkStatus()` の後に `AVAILABLE` なら認識を開始し `DOWNLOADABLE` ならダウンロードする流れを示しているが、`UNAVAILABLE` 時に `fromPfd()` を呼べないことまでを API 仕様として定めているわけではない。ハーネス側の制御と API 仕様を混同しないこと。

いずれにせよ、Issue #11/#12/#13 が求める**実際の認識**には AICore が必要であり、これは AICore 対応の実機でのみ確認できる。

### エミュレータでの実行により発見・修正した不具合

アプリが起動直後にクラッシュしていた。

```
java.lang.IllegalStateException: You need to use a Theme.AppCompat theme (or descendant) with this activity.
	at com.moongift.offlinestt.spike.MainActivity.onCreate(MainActivity.kt:53)
```

`MainActivity` が `AppCompatActivity` を継承しているにもかかわらず、`AndroidManifest.xml` のテーマが
`@android:style/Theme.Material.Light` であったことが原因である。Instrumentation Test(Issue #14)は
`MainActivity` を起動しないため、この不具合はテストでは検出できなかった。
`Theme.AppCompat.DayNight.NoActionBar` を親とするテーマを追加して修正し、起動を実測で確認した。

**この不具合が実機でも発生するかは未実測である。** ただしテーマの解決は Android フレームワークの共通処理であり、
同じテーマ構成のまま実機で起動した場合も同様にクラッシュすると推測される。その推測が正しければ、
エミュレータでの起動確認を行わずに実機検証へ進んだ場合、実機接続時に同じクラッシュで手戻りが発生していたことになる。

## Pixel 6 実機での実測(2026-09-20 JST)

**この節は上記「エミュレータでの実測」に続き、物理Android実機(Pixel 6)で実際に検証した結果である。**
design.md §4.3 が言う「ブートローダーアンロック端末では動作しない」という条件には該当しない
(下記「端末情報」のとおりブートローダーはロック済みである)。

### 端末情報

| 項目 | 値 |
|---|---|
| `ro.product.manufacturer` | `Google` |
| `ro.product.model` | `Pixel 6` |
| コードネーム | `oriole` |
| `ro.build.version.release` | `17` |
| `ro.build.version.sdk` | **`37`**(requirements.md NFR-4 の API 31 を大きく上回る) |
| `ro.product.cpu.abi` | `arm64-v8a` |
| `ro.boot.verifiedbootstate` | **`green`**(ブートローダーはロック済み) |
| `ro.boot.flash.locked` | **`1`**(同上) |
| `FINGERPRINT` | `google/oriole/oriole:17/CP2A.260705.006/15641320:user/release-keys` |

### AICore の状態

`com.google.android.aicore` はインストール済みだが、バージョンは以下である。

```
versionCode = 395592  minSdk=33  targetSdk=37
versionName = 0.stub.stub_aicore_20260302.01_RC00.877448964
enabled = 0(有効)
```

**`versionName` が `0.stub.stub_aicore_...` であり、実体のない stub(スタブ)版である。** Pixel 6 は
Gemini Nano 非対応世代であり、AICore はスタブのみが配布されている。

`com.google.android.as.oss` も存在する。

### AICore のインストール形態

```
codePath = /product/priv-app/AICorePrebuilt-aicore_20260302.01_RC00
installerPackageName = null
pkgFlags = [ SYSTEM HAS_CODE ALLOW_CLEAR_USER_DATA ]
```

`/product/priv-app` 配下のシステムアプリであり、`installerPackageName` が `null`(Play ストア経由で
インストール・更新された履歴が無い)。すなわち ROM に stub がそのまま焼き込まれている状態であり、
アプリ側やユーザー操作で後から実体版に置き換えられる余地が無い。

### 【最重要】Google Play ストアが「非対応」と明示している

端末上で `market://details?id=com.google.android.aicore` を開いたところ、Play ストアのアプリページに
以下の警告が表示された。

> **このアプリはお使いのデバイスに対応しなくなりました。詳しくは、デベロッパーにお問い合わせください。**

(アプリ名は「Android AICore」、提供元は「Google LLC」)。更新ボタンもインストールボタンも表示されない。

**これが本検証における根本原因の決定的な証拠である。** すなわち Google 自身が Pixel 6 を Android
AICore の非対応端末として扱っており、この端末上で実体のある AICore を入手する手段は存在しない。
これは設定や手順の不備ではなく、**端末側の制約であり回避策が存在しない。**

### 実行結果

| 操作 | 結果 |
|---|---|
| アプリ起動 | 成功 |
| 基準音声アセットの読み込み | 成功(`jaJP_10s.json`、locale=ja-JP、keywords=6件) |
| `checkStatus()`(MODE_BASIC、Issue #11) | **`zzaze: PERMISSION_DENIED: Api access revoked.`** |
| `startRecognition()`(MODE_BASIC、Issue #11/#13) | **`zzaze: PERMISSION_DENIED: Api access revoked.`** |
| MODE_ADVANCED での検証(Issue #12) | **`zzaze: UNAVAILABLE: Peer process crashed, exited or was killed (binderDied)`** |

logcat には `PhenotypeResourceReader: unable to find any Phenotype resource metadata for
com.google.android.aicore` も出ている。

`AudioSource.fromPfd()`(Issue #13)には到達していない。`checkStatus()` が `AVAILABLE` でないため、
ハーネスが手前で処理を終了するためである(エミュレータでの実測と同様、これはハーネス側の制御による
ものであり、`UNAVAILABLE` 時に `fromPfd()` を呼べないことをAPI仕様として定めているわけではない)。

### 参考情報(実測ではない)

Pixel 6 は Tensor G1 を搭載する世代であり、Gemini Nano は一般に Pixel 8 Pro(Tensor G3)以降が要件と
されている。**ただしこれは一般に知られた情報であって本検証で実測したものではない。** どの世代・機種
から実体のあるAICoreが提供されるかは未検証であり、断定しない。

### 公式ドキュメントとの食い違い(WebFetch で確認)

`https://developers.google.com/ml-kit/genai/speech-recognition/android` の記載:

- **Basic Mode**: 「Android devices using API level 31 and higher」
- **Advanced Mode**: 「Pixel 10, Pixel 11」のみ
- 「This API is not supported on devices with an unlocked bootloader.」

**しかし API 37 の Pixel 6(ブートローダーはロック済み)は、Google Play ストア自身が「対応しなくなった」
と明示する端末であり、Basic Mode は動作しない。** したがってドキュメントが述べる Basic Mode の端末
要件(「API level 31 and higher」)は実態と食い違っている。実際に必要なのはAPIレベルの条件ではなく、
「Google が対応端末と認め、実体のある(stubでない)AICoreを搭載した端末」であることが、Play ストアの
表示という一次情報によって裏付けられた。

## 実行環境の制約

本検証を実行した環境には以下の制約があり、Issue #11 / #12 / #13 (ML Kit GenAI Speech Recognition
による認識そのものの検証)は依然として実施できていない。

- **物理Android実機(Pixel 6)は接続されており、エミュレータ固有の制約(AICoreがエミュレータ上では
  動作しない)は解消された。** しかし上記「Pixel 6 実機での実測」のとおり、接続したPixel 6の
  `com.google.android.aicore` は `versionName = 0.stub.stub_aicore_20260302.01_RC00.877448964` という
  実体のない stub 版であり、Google Play ストアも「このアプリはお使いのデバイスに対応しなくなりました」
  と明示している。`checkStatus()`/`startRecognition()` はいずれも `PERMISSION_DENIED: Api access
  revoked.` を返した。**「実機さえあれば検証できる」という前提そのものが誤りであったことが実測で
  判明した。**
- **真に必要なのは「物理実機」ではなく「Googleが対応端末と認め、実体のあるAICoreを搭載した実機」である。**
  Pixel 6はrequirements.md NFR-4のAPI 31を大きく上回るAPI 37・ブートローダーロック済みという条件を
  満たしていても、AICoreがstub版でありPlayストアからも非対応と明示されるため動作しなかった。
- **どの機種であれば実体のあるAICoreを持つかは未検証である。** 公式ドキュメントはAdvanced Modeの対象を
  「Pixel 10, Pixel 11」としているが、Basic Modeの対象機種についてはPixel 6が不適合と判明した以外の
  実測情報がなく、他の機種(Pixel 8/9等)で動作するかは断定できない。実機を変えての追試が必要である。
- Issue #14 (MediaCodecデコード出力レート調査) はAICoreに依存しない純粋なAndroidフレームワークAPI
  (`MediaExtractor`/`MediaCodec`)のみを使うため、エミュレータ上で実行可能であり、実際に実行して
  実測値を得た(上記参照)。この制約はIssue #14には影響しない。

## design.md / requirements.md との整合性に関する注記

- **design.md §4.3 の実時間ポンプの数値記述に内部矛盾を検出し、本PRで design.md を是正した。**
  是正前の「バッファ単位100ms(3,200サンプル)」という記述は、16kHz・モノラル・16-bit PCMを
  前提にすると、3,200サンプルは200ms相当であり「100ms」という表記と整合しなかった。また同じ
  design.md/requirements.md FR-4が明記する目標レート「毎秒約32KB」(=16000サンプル/秒×2バイト
  =32,000バイト/秒、100msあたり1,600サンプル=3,200バイト)とも整合しなかった。この数値の
  食い違いを設計側の誤記(サンプル数とバイト数の混同、または100msと200msの混同)と判断し、
  design.md §4.3 を「バッファ単位100ms(16kHz・モノラル・16-bit PCMでは1,600サンプル=
  3,200バイト。1サンプル=2バイトである点に注意)」へ是正した上で、本スパイクの実装
  (`RealtimePump.kt`)の `DEFAULT_CHUNK_SAMPLES` も是正後の値(1,600)に合わせた。なお本実装は
  累積送信サンプル数と壁時計経過時間の差分で毎回sleepを再計算する自己補正アルゴリズムのため、
  チャンクサイズの値に関わらず実効スループットは常に真のサンプルレート(16000Hz×2バイト=
  32,000バイト/秒)に収束する。
- `GenAiException.ErrorCode` の実際の定数一覧(`genai-common:1.0.0-beta3` の classes.jar を javap
  で確認)は design.md §5 が言及する「AICore 606」のような数値コードを含んでいない。design.md §5の
  Android列とこのライブラリの公開APIとの対応は完全には一致しないため、本スパイクの
  `ErrorMapping.kt` では断定的な対応付けを避け、実測ベースで確定させる方針とした(詳細はREADME参照)。

## 代替案の検証: Android 標準 SpeechRecognizer

### なぜ代替案を検討したか

上記「Pixel 6 実機での実測」のとおり、ML Kit GenAI Speech Recognition が必要とする AICore は
Pixel 6 では `versionName = 0.stub.stub_aicore_...` という実体のない stub 版であり、Google Play
ストア自身が「このアプリはお使いのデバイスに対応しなくなりました」と明示する。`checkStatus()` /
`startRecognition()` はいずれも `PERMISSION_DENIED: Api access revoked.` を返し、回避策が無い
(端末側の制約であり、アプリ側の実装をどう変えても解決しない)。

そこで、モデルを同梱せず OS 側の認識エンジンを使うという requirements.md NFR-3 の方針を維持した
まま利用できる代替として、Android 標準の `android.speech.SpeechRecognizer` のオンデバイス認識を
Pixel 6 実機で調査した。本節はその実測結果である。実装は既存の ML Kit GenAI 用コード
(`RecognitionHarness.kt` 等)とは完全に独立した別ファイル・別ボタンで行った
(`PlatformSttProbe.kt`(照会専用、既存)、`PlatformSttHarness.kt`(新規、A/B の本体)、
`MainActivity.kt` の `onProbePlatformAbc()`(新規ボタン `btn_probe_platform_abc`))。

### 事前に実測済みだった照会結果(本検証開始時点で既知だった値。再掲)

```
SpeechRecognizer.isRecognitionAvailable() = true
SpeechRecognizer.isOnDeviceRecognitionAvailable() = true
supportedOnDeviceLanguages = [de-DE, ja-JP, fr-FR, ... 全36言語]   ← ja-JP を含む
installedOnDeviceLanguages = [en-US]                              ← ja-JP は未ダウンロード
pendingOnDeviceLanguages = []
onlineLanguages = []
supportError = null
```

### A: ja-JP オンデバイス言語パックの取得(実測)

`SpeechRecognizer.triggerModelDownload(Intent, Executor, ModelDownloadListener)` を試みた
(API 36 の `android.jar` を `javap` で確認済み: `triggerModelDownload(Intent)` と
`triggerModelDownload(Intent, Executor, ModelDownloadListener)` の両オーバーロードが存在する)。
`ModelDownloadListener` は `onScheduled()` / `onProgress(Int)` / `onSuccess()` / `onError(Int)` の
4メソッドを持つ。

**1回目の実行(タイムアウト60秒):**

```
=== A: ja-JP オンデバイス言語パックのダウンロード開始 (triggerModelDownload) ===
triggerModelDownload: onScheduled()
（60秒間、onProgress/onSuccess/onError のいずれも到達しなかった）
triggerJaJpModelDownload: 60000ms 以内に onSuccess/onError が到達しなかった。
=== A: ダウンロード試行終了: scheduled=true, success=false, lastProgress=null, errorCode=null, timedOut=true ===
A後の installedOnDeviceLanguages=[en-US, ja-JP], ja-JP installed = true
```

`onScheduled()` は呼ばれたが `onProgress`/`onSuccess`/`onError` はいずれも60秒以内に呼ばれず、
`ModelDownloadListener` としては未達成(タイムアウト)だった。**しかしタイムアウト直後に
`PlatformSttProbe.run()` で再照会したところ、`installedOnDeviceLanguages` に `ja-JP` が現れており、
実際にはダウンロードは完了していた。** すなわち `ModelDownloadListener` のコールバックは
信頼できるタイミングで発火しない(または本実装では正しく発火条件を捉えられていない)が、
ダウンロード自体は OS 側で非同期に進行し、成功している。

**2回目の実行(端末再起動なし、アプリ再起動後に再実行):**

```
=== A: ja-JP オンデバイス言語パックのダウンロード開始 (triggerModelDownload) ===
（60秒間、onScheduled/onProgress/onSuccess/onError のいずれも呼ばれなかった）
triggerJaJpModelDownload: 60000ms 以内に onSuccess/onError が到達しなかった。
=== A: ダウンロード試行終了: scheduled=false, success=false, lastProgress=null, errorCode=null, timedOut=true ===
A後の installedOnDeviceLanguages=[en-US, ja-JP], ja-JP installed = true
```

2回目は `onScheduled()` すら呼ばれなかった(既にダウンロード済みのため何もスケジュールされな
かったと推測されるが、その場合でも `onSuccess()` 等で即座に通知される仕様ではないらしく、
コールバックは一切発火しなかった)。`installedOnDeviceLanguages` は両回とも `ja-JP` を含んで
いたため、**ja-JP 言語パックの取得そのものは成立している(1回目の実行で完了し、以後永続する)**。

**A の結論:** `triggerModelDownload()` は呼び出せて `ja-JP` の実際のダウンロードも成功したが、
`ModelDownloadListener` のコールバックはダウンロード完了を確実には通知しない(実測では一度も
`onSuccess()` が観測できなかった)。**取得できたかどうかの確認は、コールバックではなく
`checkRecognitionSupport()` の `installedOnDeviceLanguages` を再照会することでのみ確実に判定
できる**という実測に基づく知見を得た。設定アプリからの手動ダウンロード経路は、A の
`triggerModelDownload()` で目的を達成できたため試していない。

### B: `EXTRA_AUDIO_SOURCE` によるファイル入力の受理確認(実測。最重要)

**受理された。** design.md §4.3 の PFDパイプ + 実時間ポンプ方式(`ParcelFileDescriptor.createPipe()`
+ `RealtimePump.pump()` + `WavPcm.readMono16kHz16BitPcmOrThrow()`)をそのまま流用し、
`RecognizerIntent.EXTRA_AUDIO_SOURCE`(読み取り側PFD)、`EXTRA_AUDIO_SOURCE_CHANNEL_COUNT=1`、
`EXTRA_AUDIO_SOURCE_ENCODING=ENCODING_PCM_16BIT`、`EXTRA_AUDIO_SOURCE_SAMPLING_RATE=16000`、
`EXTRA_PREFER_OFFLINE=true` を設定した `Intent` を
`SpeechRecognizer.createOnDeviceSpeechRecognizer(context).startListening(intent)` に渡した。
**`RECORD_AUDIO` 権限は付与していない**(AndroidManifest.xml に記載なし。本検証でも追加していない)。

再現性のあるクリーンな1回分の実行ログ(force-stop → logcat clear → 起動 → ボタン1回タップ):

```
startListening() を呼び出す (EXTRA_AUDIO_SOURCE 付き)。   ← 22:58:01.028
[RecognitionListener] onReadyForSpeech(...)                ← 22:58:01.040 (12ms後)
[RecognitionListener] onRmsChanged(-1.88)                  ← 22:58:01.998
[RecognitionListener] onBeginningOfSpeech()                ← 22:58:02.030
[RecognitionListener] onPartialResults(texts=[東京])        ← 22:58:02.332
  ... (以下、pump が送出するPCMの再生位置に追従して逐次的に
       "東京都渋谷で" → "2024年11月3日" → "午後3時" → "株式会社モ(ー)ンギフトが" →
       "新製品を発表しました" → "来場者は128名でした" と部分認識テキストが伸びていく)
[OK] RealtimePump 終了: sentBytes=305988/305988, elapsedMs=9564, 実効レート=31993.7バイト/秒, cancelled=false  ← 22:58:10.596
[RecognitionListener] onResults(texts=null)                ← 22:58:10.756
```

**受理成立の根拠:**
1. `startListening()` 呼び出しから12ms後に `onReadyForSpeech()` が返り、権限エラー等は一切出な
   かった(`RECORD_AUDIO` 権限が無いにもかかわらず)。マイクを実際に開こうとした場合、権限が無
   ければ即座に `onError(ERROR_INSUFFICIENT_PERMISSIONS)` 相当のエラーになるはずだが、そのような
   エラーは一度も発生しなかった。
2. `onBeginningOfSpeech()` 以降の `onPartialResults()` が返すテキストが、jaJP_10s.wav の台本
   (「東京都渋谷区で、2024年11月3日午後3時、株式会社モーンギフトが新製品を発表しました。
   来場者は128名でした。」)と時系列に沿って完全に一致する形で少しずつ伸びていった。周囲雑音や
   マイク入力(本機は静かな室内で無音状態)がこの台本と偶然一致することはあり得ず、
   **`EXTRA_AUDIO_SOURCE` で渡したPFD経由の音声データが実際に認識エンジンへ供給されたことの
   直接証拠である。**
3. `RealtimePump` の送出完了(`elapsedMs=9564`、実効レート31,993.7バイト/秒 ≒
   目標の32,000バイト/秒)から約160ms後に `onResults()` が呼ばれており、実時間ポンプの送出完了
   とほぼ同期して認識が終端した。これは design.md §4.3 の実時間ポンプ方式がそのままこのAPIでも
   機能することを示す。

**ただし `onResults()` の `RESULTS_RECOGNITION`(確定テキスト)は `null` だった。** 部分認識
(`onPartialResults`)は正しく機能し最終的な文全体に近いテキストまで到達していたが、確定結果
(`onResults`)ではテキスト配列が得られなかった。この現象は2回の独立した実行(クリーンな1回、
および前段でのA→B連続実行)の両方で再現した。原因は特定できていない(オンデバイスエンジン側の
挙動か、`EXTRA_AUDIO_SOURCE` 経由特有の終端処理の違いか、本実装のIntent設定の不足かは未検証)。
**この点は本代替案をM3で採用する場合の要検証事項として残る。**

**追加実験: 明示的な `stopListening()` 呼び出しは解決策にならなかった。** 「パイプを閉じるだけでは
入力終了が伝わっていないのではないか」という仮説のもと、`RealtimePump` 完了直後に
`recognizer.stopListening()` を明示的に呼び出す変更を加えて再実行した。結果は次のとおりである。

```
[RecognitionListener] onResults(texts=null)                ← 23:04:26.969 (ポンプ完了の150ms後、この時点で既にnull)
stopListening() を呼び出した。                                ← 23:04:40.281 (resultsTextsがnullのまま20秒待った後)
[RecognitionListener] onError(error=5, name=ERROR_CLIENT)   ← 23:04:40.307
```

**`onResults(texts=null)` は `stopListening()` を呼ぶより前に、パイプが閉じた直後の時点で既に
発火していた。** つまり本実装の呼び出し順序（パイプclose → 約20秒待機 → stopListening()）では
手遅れであり、`stopListening()` はセッション終了後の呼び出しとなって `ERROR_CLIENT`(5番)を
誘発しただけだった。**`onResults` のテキストが `null` になる現象は、`stopListening()` の
有無とは無関係に発生しており、パイプの読み取り終端(EOF)自体が確定テキスト無しの
`onResults` を引き起こしていると考えられる。** 本当に試すべきなのは「`RealtimePump` が
書き込みを終えてパイプをcloseした直後、間を置かずに `stopListening()` を呼ぶ」順序だが、
これは時間の制約により本検証では実施できなかった。

### C: ja-JP の認識精度(実測。ただし「確定テキスト」ではなく最終部分認識テキストによる)

B で確定テキスト(`onResults`)が `null` だったため、design.md §7 の「確定テキストで判定する」
という前提を厳密には満たせていない。**次善として、`onResults` 直前の最後の `onPartialResults`
が返した最上位候補(最初の要素)を用いて `KeywordScoring.kt`(design.md §7 準拠)で判定した。**

最終部分認識テキスト(最上位候補): 「東京都渋谷で2024年11月3日午後3時株式会社モンギフトが
新製品を発表しました来場者は128名でした」

| キーワード | 判定 |
|---|---|
| 東京都渋谷区 | 不一致(「渋谷で」であり「区」が脱落) |
| 2024年11月3日 | 一致 |
| 午後3時 | 一致 |
| 株式会社モーンギフト | 不一致(「モンギフト」であり長音「ー」が脱落) |
| 新製品 | 一致 |
| 128名 | 一致 |

包含率: 4/6 = **66.7%** → design.md §7 の ja-JP 閾値(95%以上合格、90〜94%条件付き、90%未満不成立)
に照らすと **不成立**。

参考: `onPartialResults` は同時に代替候補を複数返しており、2番目の候補は「モーンギフト」
(長音あり)で「株式会社モーンギフト」に一致していた。その候補のみで再計算すると 5/6 = 83.3%
だが、それでも90%には届かず、判定は変わらず **不成立** である。「東京都渋谷区」の「区」が
どの候補でも一貫して脱落しており、これが主要因である。

所要時間: `startListening()` から最後の有意な部分認識(128名でした、を含むもの)まで約9.7秒
(22:58:01.028 → 22:58:10.753)。10秒の音声クリップに対してほぼ実時間で追従した。

### requirements.md の方針を満たせるかの評価

| 方針 | 満たせるか | 根拠 |
|---|---|---|
| NFR-3(モデル非同梱) | **満たせる** | `android.speech.SpeechRecognizer` はOS/Google Play services側が保持するオンデバイスモデルを使い、アプリはモデルを同梱しない。 |
| NFR-2(オフライン) | **部分的に満たせる可能性がある。断定はできない** | `EXTRA_PREFER_OFFLINE=true` を設定し `createOnDeviceSpeechRecognizer()` を使用した。本機はWi-Fi接続状態(画面のWi-Fiアイコン参照)だったため、実際に通信が発生しなかったことまでは確認していない(パケットキャプチャ等は本検証の範囲外)。`INTERNET` 権限も付与していないため、少なくともアプリ自身が直接ネットワーク送信する経路は無い。 |
| FR-3(ファイル入力) | **満たせる(実測で確認)** | B の実測により、`EXTRA_AUDIO_SOURCE` 経由でPFDパイプからのファイル入力が受理されることを確認した。マイクは使用されなかった(RECORD_AUDIO権限なしでもエラーが出ず、認識結果が台本と一致したため)。 |
| design.md §7(評価基準) | **確定テキストでの判定はできなかった** | `onResults` が `null` を返したため、最終部分認識テキストで代用した。この代用値では ja-JP 閾値を満たさなかった(66.7%、不成立)。 |

### design.md §4.3 の PFDパイプ方式の流用可否

**流用できる部分が大半である。** `ParcelFileDescriptor.createPipe()`、`WavPcm`(WAVヘッダ解析)、
`RealtimePump`(壁時計基準の自己補正ポンプ)は一切変更せずそのまま利用でき、実際に機能した
(B参照)。変更が必要だったのは「シンク側API」のみである:

| 項目 | ML Kit GenAI (design.md §4.3) | 標準 SpeechRecognizer (本代替案) |
|---|---|---|
| 音声入力の渡し方 | `AudioSource.fromPfd(readSide)` → `SpeechRecognizerRequest` | `Intent.putExtra(EXTRA_AUDIO_SOURCE, readSide)` + チャンネル数/エンコーディング/サンプルレートの各Extra |
| 認識結果の受け取り方 | `Flow<SpeechRecognizerResponse>` (`collect`) | `RecognitionListener` のコールバック (`onPartialResults`/`onResults`/`onError`等) |
| 開始/終了 | `startRecognition()` / `stopRecognition()` | `startListening()` / `stopListening()` / `cancel()` / `destroy()` |
| キャンセル経路 | パイプclose → stopRecognition() → close() | 同様の順序が使えると考えられるが、本検証ではキャンセル経路(design.md §4.3のキャンセル手順そのもの)は検証していない |

### 限界

- **Pixel 6 単一機種での実測である。** 他機種(特に ja-JP の on-device 言語パックが最初から
  インストール済みの機種、または `installedOnDeviceLanguages` にそもそも ja-JP が
  `supportedOnDeviceLanguages` に含まれない機種)での挙動は未検証である。
- `onResults()` が `null` を返した原因は特定していない。M3で採用する場合は、この点を
  Android バージョン違い・他機種・`EXTRA_AUDIO_SOURCE` 以外の入力経路(マイク実入力)との
  比較などで追加調査する必要がある。
- キャンセル経路(design.md §4.3 のキャンセル手順)は本検証の範囲外であり未検証である。
- NFR-2(オフライン)について、実際に通信が発生していないことをネットワークレベルで確認しては
  いない。
- 本検証中に一度、ABC検証フローの実行途中でアプリのプロセスが複数回再起動する事象を観測したが、
  クリーンな単体実行(force-stop→ログクリア→起動→1回タップ)では再現せず、原因はエージェント側の
  操作環境に起因する可能性が高いと判断し、アプリ側のバグとしては扱っていない(クリーン実行の
  ログを本節の実測値として採用した)。

## フォローアップ(反映先。本ファイル自体の役目ではなく、呼び出し元が別途実施)

- `tasks.md` M0 Android の該当4項目のチェック状態更新(Issue #14 のみ実測に基づき更新可能。
  Issue #11/#12/#13 は実機検証後まで保留)。
- `requirements.md` の対応表への反映(Android列の検証済み事項)。
- `design.md` §8 未決事項6 を「リサンプリング必須(エミュレータ実測)」として更新すること。
  実環境相当音源7ファイル全てで `resampleNeeded=true`(実測)となったため、design.md §4.3の
  AudioResamplerに関する記述を「対応入力を限定するか判断(M3で決定)」ではなく実装必須として
  確定させることを推奨する。実機での追試は引き続き望ましいが、結論を左右する可能性は低い
  (RESULTS.md「design.md §8 未決事項6 に対する結論」の限界の項参照)。
  未決事項5 は Issue #12 実施後まで据え置き。
