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

(未実施 — 実機未接続。下記「実行環境の制約」参照)

| クリップID | 形式 | 包含率 | 合否 | 所要時間 | 備考 |
|---|---|---|---|---|---|
| jaJP_10s | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |

コードは実装済み(`RecognitionHarness.runRecognition()` + `KeywordScoring.kt`)。ビルドは通っており
(`assembleDebug` 成功)、実機接続後にアプリの「Basic 認識実行」ボタンから即座に実行できる状態にある。

## Issue #12: MODE_ADVANCED フォールバック挙動

(未実施 — 実機未接続。下記「実行環境の制約」参照)

| 項目 | 値 |
|---|---|
| `preferredMode=MODE_ADVANCED` での `checkStatus()` | (未実施) |
| 自動フォールバックの有無 | (未実施) |
| `MODE_BASIC` 手動リトライの結果 | (未実施) |

コードは実装済み(`RecognitionHarness.runAdvancedFallbackCheck()`)。design.md §8 未決事項5 は
未確定のまま据え置く。

## Issue #13: PFDパイプ + 実時間ポンプの受理確認

(未実施 — 実機未接続。下記「実行環境の制約」参照)

| 項目 | 値 |
|---|---|
| `AudioSource.fromPfd()` 受理可否 | (未実施) |
| `startRecognition()` Flow 開始可否 | (未実施) |
| 最初の応答/エラー到達までの時間 | (未実施) |
| 実時間ポンプの実効送出レート実測 | (未実施) |

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

## 実行環境の制約

本検証を実行した環境には以下の制約があり、Issue #11 / #12 / #13 (ML Kit GenAI Speech Recognition
による認識そのものの検証)は実施できなかった。

- **物理Android端末は接続されていない。** `adb devices` は `emulator-5554  device` のみを返す。
- 接続されているのはエミュレータ (AVD名 `Android`、target android-36、`sdk_gphone64_arm64`) のみ。
- **ML Kit GenAI Speech Recognition は AICore を必要とし、AICore はエミュレータ上では動作しない。**
  これは実装以前の制約であり、`checkStatus()` を呼び出しても `FeatureStatus.UNAVAILABLE` 等の
  結果しか得られない(あるいはAICore自体が存在しないことに起因する別のエラーになる)可能性が高い。
  本リポジトリでは実際にエミュレータ上でこれを実行して確認する時間的余地がなかったため、
  「未実施」として明記するに留め、実機なしでの実行結果を捏造していない。
- したがって、**認識を伴う検証(Issue #11/#12/#13)には物理Android実機が必須である。** Pixel実機は
  Advancedモードの主対象、Pixel以外の実機はBasicモードのフォールバック確認・非対応端末での挙動確認
  (tasks.md M0 Androidの1項目目)に必要となる。
- Issue #14 (MediaCodecデコード出力レート調査) はAICoreに依存しない純粋なAndroidフレームワークAPI
  (`MediaExtractor`/`MediaCodec`)のみを使うため、エミュレータ上で実行可能であり、実際に実行して
  実測値を得た(上記参照)。

## design.md / requirements.md との整合性に関する注記

- **design.md §4.3 の実時間ポンプの数値記述に内部矛盾がある。** 「バッファ単位100ms(3,200サンプル)」
  という記述は、16kHz・モノラル・16-bit PCMを前提にすると、3,200サンプルは200ms相当であり
  「100ms」という表記と整合しない。また同じdesign.md/requirements.md FR-4が明記する目標レート
  「毎秒約32KB」(=16000サンプル/秒×2バイト=32,000バイト/秒)とも整合しない(32KB/秒であれば
  100msあたり1,600サンプル=3,200バイトが正しい)。本スパイクの実装(`RealtimePump.kt`)は、
  この数値の食い違いを設計側の誤記(サンプル数とバイト数の混同、または100msと200msの混同)と判断し、
  チャンクサイズの値自体はdesign.md記載の「3,200」をそのまま踏襲しつつ、累積送信サンプル数と壁時計
  経過時間の差分で毎回sleepを再計算する自己補正アルゴリズムとすることで、チャンクサイズの値に
  関わらず実効スループットが常に真のサンプルレート(16000Hz×2バイト=32,000バイト/秒)に収束する
  ようにしている。この矛盾はdesign.md本体の修正が必要と考えられるため、呼び出し元での確認を推奨する。
- `GenAiException.ErrorCode` の実際の定数一覧(`genai-common:1.0.0-beta3` の classes.jar を javap
  で確認)は design.md §5 が言及する「AICore 606」のような数値コードを含んでいない。design.md §5の
  Android列とこのライブラリの公開APIとの対応は完全には一致しないため、本スパイクの
  `ErrorMapping.kt` では断定的な対応付けを避け、実測ベースで確定させる方針とした(詳細はREADME参照)。

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
- `design.md` §4.3 の実時間ポンプ数値記述の修正(上記「design.md / requirements.mdとの整合性に関する
  注記」参照)。
