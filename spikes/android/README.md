# M0 検証スパイク: Android (ML Kit GenAI Speech Recognition)

対応 Issue: #11 (Basic + ja-JP 認識・包含率判定) / #12 (MODE_ADVANCED フォールバック挙動) /
#13 (PFDパイプ + 実時間ポンプの受理確認) / #14 (MediaCodec デコード出力レート調査)。
対応する設計: design.md §4.3 Android、§5 エラーマッピング、§6 並行性・スレッディング、
§7 テスト戦略・評価基準(キーワード包含率)、§8 未決事項5・6。
対応するタスク: tasks.md「M0 検証スパイク」> Android セクション。

このディレクトリは、Flutterライブラリの実装(M3)に入る前に「Android上でML Kit GenAI Speech
Recognition による PFDパイプ入力の文字起こしが実際に動くか」「MediaCodec のデコード出力が
design.md §4.3 の目標形式(16kHz・モノラル・16-bit PCM)と一致しリサンプリングが不要か」を
確認するための、Flutter を介さない Kotlin 単体の Gradle プロジェクトである。`spikes/web/`
(README + RESULTS の文書構成)および `spikes/darwin/`(実行可能ターゲット + ライブラリターゲット
の分離、実測に基づく確定/未確定の書き分け)の方針を踏襲している。

## ディレクトリ構成

```
spikes/android/
├── build.gradle.kts               … ルートビルドファイル(プラグインバージョン宣言のみ)
├── settings.gradle.kts            … モジュール構成
├── gradle.properties
├── local.properties               … sdk.dir (コミット対象外。ビルドに必要なため作成が必要)
├── gradlew / gradlew.bat / gradle/wrapper/  … Gradle Wrapper (Gradle 9.6.0)
├── README.md                      … 本ファイル
├── RESULTS.md                     … 実測結果
└── app/
    ├── build.gradle.kts           … アプリモジュールのビルド設定 (ML Kit依存・sourceSets等)
    └── src/
        ├── main/
        │   ├── AndroidManifest.xml
        │   ├── res/                       … レイアウト・文字列 (単一Activity)
        │   └── java/com/moongift/offlinestt/spike/
        │       ├── MainActivity.kt        … 単一Activityハーネス (Issue #11/#12/#13 のUI)
        │       ├── RecognitionHarness.kt  … checkStatus→download→PFDパイプ→startRecognition の中核
        │       ├── RealtimePump.kt        … 実時間ポンプ (design.md §4.3, §6)
        │       ├── WavPcm.kt              … 基準wavのヘッダを飛ばしてraw PCMを取り出すRIFFパーサ
        │       ├── KeywordScoring.kt      … design.md §7 準拠のキーワード包含率スコアリング
        │       ├── ErrorMapping.kt        … design.md §5 のAndroid列への写像
        │       ├── BaselineClip.kt        … test-assets/baseline-audio/*.json の読み込み
        │       └── SpikeLog.kt            … 全段階ログユーティリティ
        └── androidTest/
            └── java/com/moongift/offlinestt/spike/
                └── MediaCodecDecodeRateTest.kt  … Issue #14 の Instrumentation Test
fixtures/
├── generate-rate-fixtures.sh      … Issue #14 実環境相当音源の生成スクリプト(下記参照)
└── generated/                     … 生成物置き場(コミット対象外。.gitignore参照)
```

基準音声 (`test-assets/baseline-audio/`) はリポジトリ内にコピーしていない。`app/build.gradle.kts`
の `android.sourceSets["main"].assets.srcDirs(...)` / `android.sourceSets["androidTest"].assets.srcDirs(...)`
で `../../../test-assets/baseline-audio` を直接 assets ソースディレクトリとして参照しており、
ビルド時にそのディレクトリの内容(wav/m4a/json/txt/README/scripts)がそのまま各 APK の assets に
パッケージされる。コピー用の Gradle タスクは存在しない。

## 前提

- **minSdk 31**(requirements.md NFR-4: Android 12 / API 31 以上)。
- **ML Kit GenAI Speech Recognition は AICore を必要とし、エミュレータでは動作しない。**
  Issue #11 / #12 / #13(認識を伴う検証)は **物理Android実機が必須**。Pixel実機がAdvancedモードの
  主対象だが、本スパイクの目的上「Pixel以外」の実機での Basic 動作確認も重要(tasks.md M0 Android
  1項目目)。
- **Issue #14 (MediaCodec デコード出力レート調査) はエミュレータで実行可能**であり、本リポジトリでは
  実際にエミュレータ上で実行し実測値を得ている(RESULTS.md 参照)。
- ツールチェーン:
  - `JAVA_HOME` に **JDK 17** を指定すること(例: `/opt/homebrew/opt/openjdk@17`)。既定のJDK(本検証環境では
    JDK 26)は AGP と非互換であり、ビルドが失敗する。
  - `ANDROID_HOME=$HOME/Library/Android/sdk`
  - build-tools 36.1.0 / platforms android-36 を使用(compileSdk = targetSdk = 36)。
  - Android Gradle Plugin **9.4.1**、Gradle **9.6.0**(Wrapper に同梱)。
    - 経緯: `gradle wrapper` はシステムの Gradle 9.5.1 で実行して生成したが、AGP 9.4.1 が要求する
      最低 Gradle バージョンが 9.6.0 だったため、生成後に `gradle-wrapper.properties` の
      `distributionUrl` を `gradle-9.6.0-bin.zip` に手動で更新している。
    - AGP 9.0 以降は Kotlin サポートが組み込まれており、`org.jetbrains.kotlin.android` プラグインは
      **適用しない**(適用すると `Failed to apply plugin 'com.jetbrains.kotlin.android'` エラーになる。
      https://issuetracker.google.com/438678642 )。`kotlinOptions {}` DSL も存在しないため、JVMターゲットは
      `compileOptions.sourceCompatibility/targetCompatibility = VERSION_17` から組み込みサポートが解決する。
  - `adb` は `$ANDROID_HOME/platform-tools/adb`。

## ビルド方法

```bash
cd spikes/android
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug
```

`local.properties` が無い場合は `sdk.dir=<ANDROID_HOMEの絶対パス>` の1行を持つファイルを作成すること
(コミット対象外。`.gitignore` 参照)。

## Issue #14: Instrumentation Test の実行方法 (エミュレータ/実機どちらでも可)

Issue #14 のテストは **2系統**で構成されている。

1. **基準音声系**(`jaJP_10s`/`jaJP_3m`/`enUS_10s`/`enUS_3m` の `.wav`/`.m4a`、計8ファイル):
   `test-assets/baseline-audio/` をそのまま計測対象にする。このディレクトリはリポジトリに
   コミット済みのため、追加のセットアップなしで実行できる。
2. **実環境相当音源系**(`fixtures/generated/` の7ファイル。`rate_44100_stereo`/`rate_48000_stereo`
   の `.wav`/`.m4a`(+ `rate_44100_stereo.mp3`)、`rate_22050_mono.wav`、`rate_8000_mono.wav`):
   `fixtures/generate-rate-fixtures.sh` を実行して初めて生成される。**基準音声系は`generate.sh`
   (test-assets/baseline-audio/)が16kHz・モノラルで生成したものであるため、これだけを計測して
   「リサンプリング不要」と結論づけるのは循環論法になる**(16kHz入力をデコードして16kHzが出るのは
   当然)。実際のユーザー音源(ボイスメモ・会議録音等)は44.1kHz/48kHzのステレオが一般的であるため、
   この系統でそれに近い組み合わせを検証する。

### `fixtures/generate-rate-fixtures.sh` の目的・実行方法

`test-assets/baseline-audio/jaJP_10s.wav`(16kHz/モノラル)を入力として、`ffmpeg` で以下の
組み合わせを `fixtures/generated/` に生成する。生成後は `ffprobe` で実際のサンプルレート/
チャンネル数/コーデックを検証し、期待値と異なれば非ゼロ終了する。

| 出力ファイル名 | サンプルレート | ch | コーデック/コンテナ |
|---|---|---|---|
| `rate_44100_stereo.wav` | 44100 | 2 | pcm_s16le / wav |
| `rate_48000_stereo.wav` | 48000 | 2 | pcm_s16le / wav |
| `rate_44100_stereo.m4a` | 44100 | 2 | aac / m4a |
| `rate_48000_stereo.m4a` | 48000 | 2 | aac / m4a |
| `rate_44100_stereo.mp3` | 44100 | 2 | libmp3lame / mp3 |
| `rate_22050_mono.wav` | 22050 | 1 | pcm_s16le / wav |
| `rate_8000_mono.wav` | 8000 | 1 | pcm_s16le / wav |

実行方法:

```bash
bash spikes/android/fixtures/generate-rate-fixtures.sh
```

冪等に再実行可能(既存の生成物は上書きされる)。前提は `ffmpeg`/`ffprobe`(Homebrew等)のみ。

**生成物 (`fixtures/generated/`) はリポジトリにコミットしない**(`spikes/android/.gitignore` の
`fixtures/generated/` エントリ参照)。理由: `test-assets/baseline-audio/jaJP_10s.wav` から機械的に
再生成できるファイルであり、コミットするとバイナリファイルの追加でリポジトリを肥大化させるだけで
メリットがないため。CI/別環境でIssue #14を再実行する際は、このスクリプトを先に実行すること。

### 実行手順

1. エミュレータを起動する(既に起動済みなら不要):
   ```bash
   $ANDROID_HOME/emulator/emulator -avd Android -no-snapshot-load -no-audio -no-boot-anim &
   $ANDROID_HOME/platform-tools/adb wait-for-device
   ```
2. (実環境相当音源系も計測する場合)フィクスチャを生成する:
   ```bash
   bash spikes/android/fixtures/generate-rate-fixtures.sh
   ```
3. Instrumentation Test を実行する:
   ```bash
   cd spikes/android
   JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew connectedAndroidTest
   ```
4. 結果の確認方法(いずれも実行後に利用可能):
   - HTML レポート: `app/build/reports/androidTests/connected/debug/index.html`
   - JUnit XML: `app/build/outputs/androidTest-results/connected/debug/TEST-*.xml`
   - 各テストケースの logcat 全文がテストごとに保存される:
     `app/build/outputs/androidTest-results/connected/debug/<デバイス名>/logcat-<テストクラス>-<テストメソッド>.txt`
   - 実機/起動中のエミュレータから直接回収する場合:
     ```bash
     $ANDROID_HOME/platform-tools/adb logcat -d -s OfflineSttSpike.M14Result OfflineSttSpike.M14
     ```
     `OfflineSttSpike.M14Result` タグには1行1JSONの機械可読な計測結果のみが出力される
     (`clip`/`format`/`inputMime`/`inputSampleRate`/`inputChannels`/`outputSampleRate`/
     `outputChannels`/`outputPcmEncoding`/`outputBytes`/`durationUs`/`effectiveSampleRate`/
     `expectedSampleRate`/`expectedChannels`/`resampleNeeded`)。`fixtures/generate-rate-fixtures.sh`
     を実行していないためファイルが存在しない場合は `skipped: true` のJSON(`reason`フィールド付き)が
     出力され、当該テストはスキップ扱いになる(テスト自体は失敗しない。黙って通すことはせず、必ず
     ログに残す)。`OfflineSttSpike.M14` タグには各段階の詳細ログ(入力/出力 MediaFormat の全フィールド
     等。スキップ時は `SKIPPED` という文字列を含む警告ログ)が出力される。

### Issue #14 の判定基準

各クリップについて、MediaCodec 出力側 `MediaFormat` の `KEY_SAMPLE_RATE` が 16000、
`KEY_CHANNEL_COUNT` が 1 であれば**リサンプリング不要**、1つでも異なれば**リサンプリング要**と
判定する。基準音声系(8ファイル)だけでこの判定を行うと循環論法になるため(上記参照)、
実環境相当音源系(7ファイル)の結果を合わせて評価する。実測値・最終結論(design.md §8 未決事項6)は
RESULTS.md 参照。

## Issue #11 / #12 / #13: ハーネスアプリの実機での実行手順

**エミュレータでは動作しない。物理Android実機(API 31以上、ブートローダーロック済み、AICore利用可)が
必須。** 本リポジトリの実行環境には物理端末が接続されていないため、この経路は未実施である
(RESULTS.md「実行環境の制約」参照)。実機接続後の手順は以下のとおり。

1. 実機を開発者向けオプション経由でUSBデバッグ有効化し、`adb devices` で認識されることを確認する。
2. `JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew installDebug` でハーネスアプリをインストールする。
   (assets には `test-assets/baseline-audio/` の内容がビルド時に自動的に含まれるため、`adb push` 等の
   追加手順は不要。)
3. 端末でアプリ「OfflineSTT M0 Spike」を起動する。画面上部に端末情報(モデル名・SDK_INTなど)が
   表示されることを確認する。
4. 「Basic 状態確認」ボタンを押す。`SpeechRecognizerOptions{locale=ja-JP, preferredMode=MODE_BASIC}` での
   `checkStatus()` 結果(AVAILABLE/DOWNLOADABLE/DOWNLOADING/UNAVAILABLE)がログとテキスト表示に出る。
5. 「Basic 認識実行」ボタンを押す(Issue #11 + #13)。以下が逐次ログに出力される:
   - `checkStatus()` → 必要なら `download()` の進捗 → 再度 `checkStatus()`
   - `jaJP_10s.wav` のヘッダを飛ばして raw PCM を取得(16kHz/mono/16-bit であることを検証。異なる場合は
     明確にエラー停止し、リサンプリングは行わない)
   - `ParcelFileDescriptor.createPipe()` → 実時間ポンプ開始(壁時計基準、100msバッファ、目標レート
     約32KB/秒。詳細は `RealtimePump.kt` のコメント参照。design.md記載値との数値の齟齬についても
     同ファイルに記載している)
   - `AudioSource.fromPfd()` の成否
   - `SpeechRecognizer.startRecognition()` の Flow から得た partial/final/completed/error
   - 受理成立/不成立の判定(下記「受理成立の判定基準」)
   - 最終テキストが得られた場合はキーワード包含率スコアリング結果(一致/不一致キーワード、%、判定)
6. 「Advanced フォールバック検証」ボタンを押す(Issue #12)。`preferredMode=MODE_ADVANCED` での
   `checkStatus()` と認識可否を記録したのち、続けて `MODE_BASIC` での手動リトライを実行し、両者の
   結果を比較できるようにログへ出力する。
7. 実行中セッションがある状態で「実行中セッションをキャンセル」ボタンを押すと、
   design.md §4.3 のキャンセル経路(パイプclose → `stopRecognition()` → `close()`)が動作する。

### 受理成立の判定基準 (Issue #13)

以下をすべて満たした場合に「受理成立」とする(`RecognitionHarness.kt` の `SessionResult.accepted` /
`runRecognition()` 内のコメント参照):

1. `AudioSource.fromPfd()` が例外を投げずにソースを生成できる
2. `SpeechRecognizer.startRecognition()` が `Flow` を返し、`collect` が例外なく開始する
3. 既定20秒以内に、最初の応答(partial/final/completedのいずれか)または最初のエラー
   (`ErrorResponse` または Flow自体の例外)が到達する

これらを満たさない場合は「受理不成立」とし、発生した例外種別・`GenAiException.errorCode` を記録する
(`ErrorMapping.kt` 参照)。

### NFR-2(プライバシー)の確認手順

1. 実機の設定でネットワーク使用量モニタ、または `adb shell dumpsys netstats` 等でアプリ
   (`com.moongift.offlinestt.spike`)のデータ送受信量を実行前後で比較する。
2. `AndroidManifest.xml` は `INTERNET` パーミッションを宣言していないため、アプリ自身のプロセスが
   直接ネットワークソケットを開くことはできない設計になっている(付与していない理由は
   `AndroidManifest.xml` 内コメント参照)。checkStatus()/download() が Google Play services 側の
   プロセス経由でモデルを取得する場合、そのネットワーク通信はアプリのINTERNET権限の有無に依らない
   可能性があるため、実機検証時にこの前提が崩れないか確認すること。

## design.md §5 エラーマッピング表との対応

| 共通例外 | Android (design.md) | 本スパイクでの扱い |
|---|---|---|
| ModelUnavailable | FeatureStatus.UNAVAILABLE / AICore 606 | `ErrorMapping.classifyFeatureStatus()` / `ErrorMapping.classify()`(`GenAiException.ErrorCode.NOT_AVAILABLE`/`NEEDS_SYSTEM_UPDATE`) |
| LocaleUnsupported | ロケール非対応ステータス | `checkStatus()` の `UNAVAILABLE` 相当として観測 (専用エラーコードは本ライブラリのpublic APIには見当たらなかった。RESULTS.md参照) |
| DecodeFailed | MediaCodecエラー | `MediaCodecDecodeRateTest` 側(Issue #14)で発生しうる。ハーネス本体(B/C/D)はraw PCM読込のみのため対象外 |
| DeviceUnsupported | ブートローダーアンロック / API<31 | `ErrorMapping.classify()`(`GenAiException.ErrorCode.AICORE_INCOMPATIBLE`)。API<31はminSdkでビルド時に排除 |
| Cancelled | Flow cancel | `RecognitionHarness.cancelActiveSession()` / `GenAiException.ErrorCode.CANCELLED` |

「AICore 606」のような数値エラーコードは、`genai-speech-recognition:1.0.0-alpha1` /
`genai-common:1.0.0-beta3` の classes.jar を `javap` で実際に確認した限り、公開APIの
`GenAiException.ErrorCode` 定数一覧には含まれていない。本実装はこの対応関係を断定せず、
例外メッセージ/causeチェーンに数値コードらしき文字列を検出した場合にログへ残すだけに留めている
(`ErrorMapping.scanForAiCoreNumericCode()`)。

## キーワード包含率のしきい値 (design.md §7)

`KeywordScoring.kt` の `THRESHOLDS` にまとめている。design.md §7 由来。

- ja-JP: 95%以上で合格、90〜94%で条件付き合格、90%未満で不成立
- en-US: 95%以上で合格、95%未満で不成立

正規化ルール(NFKC正規化 → 小文字化 → 句読点・記号除去 → 空白除去、ja-JPはさらにひらがな→カタカナ
畳み込み)も design.md §7 に厳密に従っている。句読点・記号除去には Unicode 一般カテゴリの単一文字
グループ `\p{P}` / `\p{S}` を用いている(`\p{IsSymbol}` のような binary property 名の綴りは Java の
`Pattern` では未定義でありコンパイルエラーになるため使っていない。詳細は `KeywordScoring.kt` の
コメント参照)。参照実装は `spikes/web/spike.js` の (C) ブロックであり、判定ロジックが同一になる
ようにしている。

## design.md §8 未決事項5・6 との対応

- 未決事項5(Android: MODE_ADVANCED指定時の非対応端末での自動フォールバック有無)は Issue #12 の
  範囲。本スパイクは検証ロジックを実装済みだが、実機接続の制約により未実施(RESULTS.md参照)。
- 未決事項6(Android: リサンプリング実装の要否)は Issue #14 の範囲。**本スパイクはこれを実際に
  エミュレータ上で実行し、基準音声系・実環境相当音源系の両方で実測値を得ている。実環境相当音源系
  (44.1kHz/48kHzステレオ等、計7ファイル)は全てリサンプリングが必要という結果になり、
  design.md §4.3 のAudioResampler相当の実装が必須と結論づけている**(RESULTS.md参照)。

## やっていないこと

- リサンプリングの実装(M3の仕事。本スパイクは要否の判定までを行う)。
- Flutterプラグイン本体の実装。
- tasks.md / requirements.md / design.md 自体の更新(呼び出し元が別途反映する)。
