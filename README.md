# offline_stt

録音済み音声ファイルを、OSネイティブの音声認識APIのみでオフライン文字起こしするFlutterライブラリ(モノレポ)。

v1 の対象は Android / iOS / macOS / Web の4つである。

詳細な要件・設計は [requirements.md](./requirements.md) / [design.md](./design.md) / [tasks.md](./tasks.md) を参照。

## 対応状況マトリクス

**このマトリクスは実測に基づく。実測していない欄は「未検証」と書いてあり、推測値は入れていない。**
各欄の根拠は `spikes/{web,darwin,android}/RESULTS.md` にある。

| プラットフォーム | バックエンドAPI | 最低OSバージョン | 所要時間特性 | ja-JP検証結果 |
|---|---|---|---|---|
| Android | 標準 `android.speech.SpeechRecognizer`(`createOnDeviceSpeechRecognizer`)+ MediaCodecデコード + 実時間ポンプ | Android 12 / API 31(`minSdk 31`) | **実時間**。PFDパイプへ毎秒約32KBで供給するため、ファイル長と同等の時間がかかる(Pixel 6実機: 9.56秒の音声に対しポンプ9,564ms、実効31,993.7バイト/秒) | **不成立**。Pixel 6(Android 17 / API 37)実機で jaJP_10s 66.7%(4/6) |
| iOS / macOS | SpeechAnalyzer + SpeechTranscriber(AVFoundationデコード) | iOS 26 / macOS 26(podspec の deployment target も 26.0) | **非実時間・高速**。macOS 26.5.1実機でRTF 0.0067〜0.0245、**iPad Pro (iOS 26.6.2) 実機で RTF 0.0059〜0.0511**(いずれも実時間の約20〜170倍速) | **不成立**。macOS 26.5.1実機・iPad Pro (iOS 26.6.2) 実機とも jaJP_10s 66.7%(4/6)、enUS_10s 80.0%(いずれもキーワードセット是正の前後で不変)。`enUS_3m` は是正後 80.0%(是正前 44.0%)。**両プラットフォームで率もHIT/MISSの内訳も完全一致** |
| Web | Chrome オンデバイス Web Speech(`processLocally: true`)+ Web Audio | Chrome 142 以上(オンデバイスWeb Speechのリグレッション修正済みバージョン)。実機検証は Chrome 153 | **実時間**。Chrome 153で9.56秒の音声に9,676ms。`playbackRate` で短縮できるが精度が落ちる(後述) | **不成立**。Chrome 153で jaJP_10s(1.0x)66.7%(4/6) |

Linuxは対象外である(OSネイティブのASR APIが存在しないため。requirements.md §3)。

### 検証に使った環境(実測値の出どころ)

| プラットフォーム | 検証環境 |
|---|---|
| Android | Pixel 6(`oriole`、Android 17 / API 37、ブートローダーはロック済み) |
| macOS | macOS 26.5.1 (build 25F80) / Apple Silicon |
| iOS | **iPad Pro 11-inch (M4) / iOS 26.6.2**(requirements.md NFR-4 が定める下限)と iPhone 17 / iOS 27.0。`supportedLocales` はOSバージョンで件数が異なる(macOS 26.5.1: 30件、iOS 26.6.2: 30件、iOS 27.0: 45件)ため、iOS 27.0 の結果を下限へ外挿することはできない。**下限での確認は Issue #7 で完了済み** |
| Web | Chrome 153.0.8010.48 / macOS 26.5.1、localhost配信 |

### 精度について(重要)

**design.md §7 のしきい値は、クリーン基準音声で ja-JP が 95%以上で合格・90〜94%が条件付き合格、en-US が 95%以上で合格である。ja-JP は、実測できた Darwin / Web / Android の3つすべてで満たしていない**。en-US では Android(Pixel 6)の `enUS_10s` が 100.0% で満たしている。

- Darwin(macOS 26.5.1)・Web(Chrome 153)・Android(Pixel 6)の3つはいずれも、同一の基準音声 `jaJP_10s` で**ちょうど 66.7%(4/6)**という同率だった。
- 3プラットフォームすべてが `株式会社モーンギフト` を落としている(Darwin「モーギフト」、Web「ムーンギフト」、Android「モンギフト」)。
- **この不成立の原因は未確定である。** 基準音声がTTS合成音声であること、キーワード選定と正規化規則が表記差を吸収できていないこと、認識モデル自体の精度、(Darwinでは)プリセット選択、のいずれが支配的かを分離する対照実験を行っていない。したがって「認識品質が低い」とも「基準音声の設計の問題」とも断定しない。**ただし次項のとおり、`jaJP_10s` についてだけは「キーワード選定と正規化規則」を候補から外せている。長尺クリップでは外せていない。** 詳細は design.md §7 の注記と各 `RESULTS.md` を参照。
- **2026-09-21 にキーワードセットの不備を1件是正した。** design.md §7 は「表記が複数あり得るキーワードは許容表記を列挙する」と定めているのに、`test-assets/baseline-audio/*.json` は各キーワード1表記しか持っておらず、`three hundred and twenty thousand` と `320,000` のような**単なる表記差を不一致として数えていた**。許容表記を列挙できるスキーマ(文字列 または 配列)に改め、**記録済みの確定テキストを採点し直した**。値が動いたのは `enUS_3m`(44.0% → **80.0%**、Darwin)と `jaJP_3m`(39.3% → **42.9%** / 28.6% → **32.1%**、Darwin)であり、**`jaJP_10s` の 66.7% は前後で変わらない**(落としている2件は表記差ではなく誤認識であるため)。**認識結果は一切変わっていない。端末での再測定もしていない。**

  **是正後にしきい値を満たしているのは Android(Pixel 6)の `enUS_10s`(100.0%)だけである。** 条件付き合格圏(ja-JP 90〜94%)に入ったクリップも無い。
- Darwinでは `SpeechTranscriber.Preset` の違いだけで包含率が最大20ポイント以上動く(`enUS_10s` は `.transcription` で100%に達した)ことが実測されており、包含率という指標自体が条件に強く依存する。

ja-JP以外では、Darwin と Android で en-US を実測している。Darwin は `enUS_10s` 80.0% / `enUS_3m` **80.0%**(キーワードセット是正前は 44.0%)で、いずれも不成立である。Android(Pixel 6)は `enUS_10s` が **100.0% で合格**、`enUS_3m` は 40.0%(是正前の値。確定テキストが逐語で記録されていないため再採点できていない)。Web の en-US は未検証である。

### 再生速度オプション(`playbackRate`)

`transcribeFile()` の `playbackRate`(既定 1.0)は**Web専用オプション**である。Darwinはバッチ認識であり速度という概念が無いため無視される。Androidは実時間ポンプ方式のため理論上は適用余地があるが未実装・未検証である。

Chrome 153 での jaJP_10s 実測では、所要時間は短縮される一方で**精度は 1.0x → 1.5x → 2.0x と単調に低下**した(66.7% → 50.0% → 33.3%)。`AudioBufferSourceNode.playbackRate` はピッチも同倍率で変えるためである。所要時間と精度のトレードオフを理解したうえで使うこと。

### 実機E2Eの状況

認識のE2E(実際に音声ファイルが正しく文字起こしされること)はCIでは検証していない(理由は後述の「CI」節)。リリース前の手動チェックリストで運用する。**チェックリスト群の入口(なぜCIに載せないのか・共通の前提・基準音声・包含率の算出方法)は [E2E_CHECKLIST.md](./E2E_CHECKLIST.md) にある**(Issue #66)。

| プラットフォーム | 実装E2Eの状況 |
|---|---|
| Web | 手動チェックリストあり([packages/offline_stt_web/E2E_CHECKLIST.md](./packages/offline_stt_web/E2E_CHECKLIST.md))。本番実装での再測定は未実施 |
| Darwin | **2026-09-21 に本番実装を macOS 26.5.1 + iPad Pro (iOS 26.6.2) で実行済み(Issue #40)。手順1〜6は全て期待どおりで実装バグ0件。16回すべて1回目で完走。包含率は8ファイルとも未達**([結果](./packages/offline_stt_darwin/E2E_RESULTS.md))。iOS 27実機は未実施 |
| Android | **2026-09-21 に本番実装を Pixel 6 で実行済み(Issue #50)。初回は不合格でバグ4件を発見し、修正後の最終実行は手順3が8/8成功**([結果](./packages/offline_stt_android/E2E_RESULTS.md))。包含率は enUS_10s のみ合格。非Pixel機は未実施(利用者判断により対象外) |

上の表の「ja-JP検証結果」はいずれも**M0スパイク実装での実測値**であり、本リポジトリの実装パッケージで取り直したものではない。

## アプリ側に必要な対応

ライブラリを依存に足すだけでは完結しない事項がある。プラットフォームごとに次の対応がアプリ側の責務となる。

### 共通: モデルダウンロードの同意ダイアログ

全プラットフォームで、**ライブラリは暗黙にモデルをダウンロードしない**(requirements.md FR-2 / §8、design.md §3)。`checkModel()` が `downloadable` を返したら、アプリが同意UIを出し、同意が得られてから `downloadModel()` を呼ぶ。文言は具体的なモデル名・ベンダー名を出さず「音声認識モデル」のような一般名称で呼ぶ。参照実装は [`apps/example/lib/src/download_consent_dialog.dart`](./apps/example/lib/src/download_consent_dialog.dart) にある。

### Android: `checkModel()` を先に呼ぶ

Androidのオンデバイス認識は、対象ロケールの言語パックが端末にダウンロードされていなければ動かない。Pixel 6実機での実測では、初期状態の `installedOnDeviceLanguages` は `[en-US]` のみで ja-JP は含まれていなかった。そのため**必ず `checkModel(locale)` を先に呼び、`downloadable` なら同意のうえ `downloadModel()` を呼ぶ**。

加えて、`SpeechRecognizer.triggerModelDownload()` の `ModelDownloadListener` は**ダウンロード完了を確実には通知しない**ことが実測で判明している(Pixel 6実機で `onSuccess()` を一度も観測できないまま、実際にはダウンロードが完了していた)。完了判定は `checkRecognitionSupport()` の `installedOnDeviceLanguages` の再照会によってのみ確実に行える。本プラグインはこの方式で実装している。

> **注意: AICore / ML Kit GenAI は使っていない。**
> 初期の設計(requirements.md / design.md の旧記述)はML Kit GenAI Speech Recognition(AICore)を前提としていたが、**M0検証の結果この方針は破棄した**。Pixel 6実機の `com.google.android.aicore` は `versionName = 0.stub.stub_aicore_...` という実体の無いstub版であり、Google Play ストア自身が「このアプリはお使いのデバイスに対応しなくなりました」と表示する。`checkStatus()` / `startRecognition()` はいずれも `PERMISSION_DENIED: Api access revoked.` を返した。端末側の制約であり回避策が無いため、標準 `android.speech.SpeechRecognizer` に差し替えてある。**「AICoreの初期化を待つ」といったアプリ側対応は不要である。**

### Web: ユーザー操作起点とChrome以外の扱い

- ファイル選択はユーザー操作起点(File / Blob)であること。
- **localhost または https 配信であること。** `on-device-speech-recognition` Permissions Policy の既定値が `'self'` であるため、`file://` で直接開いても動作しない。
- **Chrome以外のブラウザでは `checkModel()` が `unavailable` を返す。** Web Speech API のオンデバイス認識(`SpeechRecognition.available()` / `install()` / `start(audioTrack)` + `processLocally`)は現時点でChrome系の機能であり、それ以外のブラウザでは機能検出の時点で成立しない。アプリ側は `unavailable` を「この環境では使えない」として提示する導線を用意すること。ライブラリはサーバー認識へフォールバックしない(NFR-2)。
- 言語パックは約60MBあり、`install()` に8.7秒(Chrome 153実測)かかった。`install()` は進捗イベントを持たず `Promise<boolean>` を返すだけなので、進捗は不定進捗として扱われる。
- 確定(final)結果は形態素単位で空白区切りされる(`東京 都 渋谷 で ...`)。

## モデル同梱型の代替(sherpa-onnx / whisper.cpp / Vosk)との使い分け

`offline_stt` は「**モデルを一切同梱せず、OSが持つ認識エンジンだけを使う**」という一点に特化している(requirements.md §2 / NFR-3)。この選択には裏返しの制約が多い。**用途によっては、モデル同梱型のライブラリを選ぶほうが適切である。**

### `offline_stt` を選ぶ理由になるもの

- **アプリサイズが増えない。** モデルも推論エンジンも同梱しないため、各パッケージはブリッジコードのみである。
- **モデルの取得・更新・削除をOSが管理する。** 自前でモデル配布基盤を用意しなくてよい。
- **音声も書き起こし結果もネットワークに出ない**(NFR-2)。Webでは `processLocally = true` を強制し、サーバー認識へのサイレントフォールバックを禁止している。
- Web(Chrome)を含む4プラットフォームを**同一のDart APIで**扱える。

### `offline_stt` の不利な点(先に読むこと)

- **モデルを同梱しないということは、初回利用時にモデルが端末に無い可能性があるということである。** ダウンロードの同意UIと待ち時間、そして「端末の都合で使えない」という状態(`unavailable`)をアプリ側で扱う必要がある。モデル同梱型にはこの状態が存在しない。
- **最低OSバージョンが高い。** iOS 26 / macOS 26 / Android 12(API 31)/ Chrome 142。特にiOS・macOSの下限は、現時点で採用できるユーザー母数を大きく制限する(requirements.md §9 のリスク表にも記載がある)。
- **精度がしきい値に届いていない。** 上記「精度について」のとおり、検証できた3プラットフォームすべてで design.md §7 のしきい値を下回った(ja-JP 66.7%)。原因は未確定だが、**「OSネイティブだから十分な精度が出る」と期待して採用してはいけない**段階である。
- **Linuxは対象外**である。
- **マイク入力のリアルタイム認識は対象外**である(v1はファイル入力専用)。
- **土台のOS APIがalpha / Experimental段階**のものを含むため、ライブラリは0.x系で公開している(NFR-5)。

### モデル同梱型(sherpa-onnx / whisper.cpp / Vosk 等)を選ぶべき場合

次のいずれかに当てはまるなら、モデル同梱型を検討したほうがよい。

- **古いOSバージョンを含む幅広い端末を対象にしたい。** `offline_stt` のOSバージョン下限は妥協できない制約である。モデル同梱型はOSの音声認識機能に依存しないため、この制約から自由になる。
- **認識に使うモデルを自分で選び、固定したい。** `offline_stt` はモデルをOSに委ねるため、モデルの種類も更新タイミングも選べず、OS更新で認識結果が変わりうる。再現性が要るなら不向きである。
- **Linuxを対象にしたい。**
- **初回起動時のモデルダウンロードや同意ダイアログを避けたい。** アプリに同梱してあればその導線自体が不要になる。

逆に、**アプリサイズを抑えることが最優先で、対象端末を新しめのOSに絞れて、モデルの選択権を必要としない**なら `offline_stt` が噛み合う。

> 代替ライブラリ側の個別の性能・対応言語・ライセンス・Flutterバインディングの有無については、本READMEでは断定しない。実測していないためである。採用判断の際はそれぞれの公式ドキュメントで最新の情報を確認すること。ここで示したのは**比較すべき軸**(モデル同梱の有無 / OSバージョン下限 / モデル選択権 / 言語指定 / 対象プラットフォーム / アプリサイズ)である。

## モノレポ構成

**Melos + Dart Pub Workspaces**(Melos 8系)を採用している。ルート `pubspec.yaml` の `workspace:` キーで全パッケージを列挙し、`melos:` キーにMelosのスクリプト定義を集約している(`melos.yaml` は使わない)。

```
offline_stt/
├── pubspec.yaml                          … workspace定義 + melos設定
├── packages/
│   ├── offline_stt/                      … エントリパッケージ(利用者はこれのみに依存)
│   ├── offline_stt_platform_interface/   … 共通抽象・データ型・例外(純Dart)
│   ├── offline_stt_android/              … Kotlin実装(標準 android.speech.SpeechRecognizer)
│   ├── offline_stt_darwin/               … Swift実装(iOS/macOS共用、SpeechAnalyzer)
│   └── offline_stt_web/                  … Dart JS interop実装(Web Speech API)
└── apps/
    └── example/                          … example app
```

federated pluginのエンドースメント構成(`offline_stt` の `flutter.plugin.platforms` で各プラットフォームに `default_package` を指定し、各実装パッケージは `implements: offline_stt` を宣言)は requirements.md §6 / design.md §1 に従っている。

## セットアップ・コマンド

```bash
# 依存解決(初回・依存追加時)
melos bootstrap
# または Dart Pub Workspaces のみで: dart pub get

# 全パッケージの静的解析
melos run analyze

# test/ を持つパッケージでユニットテストを実行
melos run test

# フォーマット差分チェック(Pigeon生成物 *.g.dart は対象外)
melos run format
```

`melos` は `~/.pub-cache/bin/melos` にインストールされている想定。PATHに無ければフルパスで実行する。

## CI(GitHub Actions、Issue #25)

`.github/workflows/ci.yml` は `push`(main)と `pull_request` で以下を実行する。

| ジョブ | ランナー | 内容 |
|---|---|---|
| analyze-test | ubuntu-latest | `melos run analyze` / `melos run test` / `melos run format` |
| build (android) | ubuntu-latest | `apps/example` の `flutter build apk --debug` |
| build (web) | ubuntu-latest | `apps/example` の `flutter build web` |
| build (macos) | macos-26 | `apps/example` の `flutter build macos --debug` |
| build (ios) | macos-26 | `apps/example` の `flutter build ios --no-codesign --debug` |

**CIが検証すること**: 全パッケージの静的解析・ユニットテスト・フォーマット、および `apps/example` の各プラットフォーム向けコンパイル(ビルド検証のみ)。

**CIが検証しないこと(design.md §7 の方針)**: 認識E2E(実際の音声ファイルが正しく文字起こしされるか)。以下のとおり実機依存であることが実測済みであり、CI環境では原理的に再現できないため、リリース前の手動チェックリストで運用する。

- iOS: シミュレータでは `SpeechTranscriber.isAvailable` が `false` になり、SpeechAnalyzerによる認識自体が利用できない(`spikes/darwin/RESULTS.md`)
- Android: オンデバイス認識には実機と、対象ロケールの言語パックが端末にダウンロード済みであることが必要である(`spikes/android/RESULTS.md`)
- Web: ブラウザの言語パック(約60MB)取得と実ブラウザ環境が必要であり、ヘッドレスCIでは再現しない(`spikes/web/RESULTS.md`)

**ランナー・SDKバージョンの調査結果**(2026-09時点):

- `macos-26` ラベルは 2026-02-26 にGitHub ActionsでGA済み(既定Xcode 26.4.1、26.5等も選択可能)であり、requirements.md NFR-4「iOS 26 / macOS 26 以上」を満たすビルド環境として利用できる。

**ローカルで検証済みのビルド**:

| ビルド | 結果 |
|---|---|
| `flutter build web` | 成功 |
| `flutter build macos --debug` | 成功(Xcode 26.6 / macOS 26.5.1) |
| `flutter build ios --no-codesign --debug` | 成功(Xcode 26.6) |
| `flutter build apk --debug` | 成功(JDK 17。Issue #51 でコミットした `apps/example/android` に対して実行) |

Android のローカルビルドには **JDK 17 が必要である**。検証に使ったマシンの既定 JDK は 26.0.1 であり、同梱の Kotlin コンパイラがそのバージョン文字列を解釈できず `java.lang.IllegalArgumentException: 26.0.1` で失敗する。次のように JDK 17 を明示して実行した。

```bash
cd apps/example
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home flutter build apk --debug
```

CI の Android ジョブが `actions/setup-java` で JDK 17 を用意しているのと同じ理由である(`android/build.gradle` の `sourceCompatibility` は 17)。

**Swift の言語モードについて**: `offline_stt_darwin.podspec` は `s.swift_version = '5.0'` を指定している。Swift 6 言語モード(strict concurrency)では、Pigeon が生成する `Pigeon.g.swift` のトップレベル `var`(`pigeonPigeonMethodCodec`)が `is not concurrency-safe because it is nonisolated global shared mutable state` としてコンパイルエラーになる。Pigeon 27.3.0 と最新の 29.0.2 のどちらでも同じコードが生成されるため、Pigeon の更新では解決しない。Swift 5 モードでも async/await と actor は使えるため、design.md §4.2 の SpeechAnalyzer 連携(M2)には支障がない。

**その他の注意点**:

- ネイティブプロジェクトは **4プラットフォームすべてリポジトリにコミット済み**である(ios / macos / web は Issue #41、android は Issue #51)。**CIジョブ内で `flutter create` を実行することはもう無い。** いずれも Flutter 3.41.9 の `flutter create . --platforms=<platform> --org com.moongift` の出力をそのままコミットしてある(**生成時点のバージョンであり、CI が使う版とは別である**。CI は現在 3.47.5。`flutter create` の生成物は SDK 更新のたびに作り直す性質のものではないため、生成時点のまま据え置いている)。
- macOS/iOSのDeployment Target引き上げ(26.0、`offline_stt_darwin.podspec` の要求)は、ネイティブプロジェクトをコミットした時点で反映済みであり、CI内での `sed` は不要になったため削除した。
- `apps/example/android` をコミット対象に含めたのは、(a) 他の3プラットフォームと扱いを揃えるため、(b) `minSdk 31` の要件をリポジトリ内で表明でき、CI内の `sed` による書き換えという間接的な手当を無くせるため、(c) 実機E2E(Issue #50)を行う人が `flutter create` を自分で再実行せずに `flutter build apk` できるため、の3点である。
- `apps/example/android/app/build.gradle.kts` の `minSdk` は `flutter.minSdkVersion`(生成時点の Flutter 3.41.9 の既定は 24)ではなく **`31` を直接書いてある**。`offline_stt_android` が要求する 31(requirements.md NFR-4: Android 12 / API 31 以上)より低いと、マニフェストのマージが `uses-sdk:minSdkVersion 24 cannot be smaller than version 31 declared in library [:offline_stt_android]` で失敗することを CI の実行で実際に確認している(Issue #82)。**以前は CI 内の `sed` で引き上げていたが、Issue #51 でこのステップは削除した。** macOS/iOS の Deployment Target を `sed` で引き上げるステップを Issue #41 で削除したのと同じ理由である。

## プラットフォーム別の追加セットアップ

- Android / iOS / macOS / Web: 追加のセットアップは不要(モデルダウンロードの同意UIはいずれのプラットフォームでもアプリ側の責務である。requirements.md §8)。

## 継続運用のドキュメント(`docs/`)

`requirements.md` / `design.md` / `tasks.md` が**何を作るか**を、
`E2E_CHECKLIST.md` が**リリース前にどう検証するか**を決めるのに対し、
`docs/` 配下は**公開後に継続して回す運用**を扱う。読み手も頻度も違うため
分けてある。

| 文書 | 内容 | 対応Issue |
|---|---|---|
| [docs/MONITORING.md](./docs/MONITORING.md) | 依存プラットフォーム(Android標準SpeechRecognizer + Google Play services / Chromeオンデバイス Web Speech / Apple Speech framework)とOSベータの変更監視手順。何を・どこで・どの頻度で見て、何を再実行するか | #67 |
| [docs/VERSION_POLICY.md](./docs/VERSION_POLICY.md) | リポジトリ内で固定しているバージョンの一覧(どのファイルの何行目に何が書いてあるか)と、破壊的変更が起きたとき・固定値を動かすときの手順 | #68 |
| [docs/FUTURE_EXTENSIONS.md](./docs/FUTURE_EXTENSIONS.md) | 将来拡張3件(タイムスタンプ / マイク入力 / 同時複数セッション)の設計レベルの評価。各プラットフォームAPIが何を提供しているか、何が必要か、今何が塞いでいるか | #69 |

**いずれも文書であって実行実績ではない。** #67 の四半期監視は一度も実行
されておらず、#68 の手順も一度も回っていない。#69 はどれも未着手である。

## 現状

`offline_stt_platform_interface` と Web / Darwin(iOS・macOS)/ Android の各実装が入っている(tasks.md の M1〜M3)。エントリパッケージ `offline_stt` は現時点で利用者向けのファサードクラスをまだ持たず、example app は暫定的に `OfflineTranscriberPlatform.instance` を直接使用している(`apps/example/pubspec.yaml` のコメント参照)。
