# 破壊的変更への追従とバージョン固定の更新方針

対応 Issue: #68。関連: [MONITORING.md](./MONITORING.md)(Issue #67)、
requirements.md NFR-4「最低動作環境」・NFR-5「バージョニング」。

## この文書の位置づけ

[MONITORING.md](./MONITORING.md) が「**依存先が変わっていないかをどう見に
行くか**」を決めるのに対し、本書は「**変わっていた / 壊れたときに何をするか**」
と「**リポジトリ内で固定している値をいつどう動かすか**」を決める。

**本書は方針書であって、実行記録ではない。** ここに書いた手順を実際に回した
実績はまだ無い(「実行記録」節を参照)。

## 1. 今、何をどこで固定しているか

値を変えるときは、**必ず下の表で「同時に直す必要がある場所」を確認する**。
同じ値が複数箇所に書かれているものが多く、片方だけ直すと食い違う。

### 1.1 Flutter / Dart ツールチェーン

| 固定しているもの | 値 | 場所 |
|---|---|---|
| Flutter SDK(CIが使う版) | `3.47.5` / `stable` | `.github/workflows/ci.yml` の `env.FLUTTER_VERSION` / `FLUTTER_CHANNEL` |
| Flutter SDK(パッケージが要求する下限) | `>=3.47.0` | `packages/offline_stt{,_android,_darwin,_windows,_web}/pubspec.yaml` と `apps/example/pubspec.yaml` の `environment.flutter`(計6ファイル) |
| Dart SDK | `^3.9.0` | 上記6ファイル + `packages/offline_stt_platform_interface/pubspec.yaml` + ルート `pubspec.yaml`(計8ファイル) |
| melos | `8.2.2`(CI)/ `^8.2.2`(dev依存) | `.github/workflows/ci.yml` の `dart pub global activate melos 8.2.2`、ルート `pubspec.yaml` の `dev_dependencies.melos` |
| Pigeon | `^27.3.0` | `packages/offline_stt_{android,darwin,windows}/pubspec.yaml` の `dev_dependencies.pigeon` |

`apps/example/.metadata` に記録されている Flutter revision
`00b0c91f06209d9e4a41f71b7a512d6eb3b9c694` は、`flutter create` が
各プラットフォームプロジェクトを生成したときの版である(`flutter migrate`
が参照する)。手で書き換えるものではない。

> **Pigeon を 27 系に留めている理由は、実は記録されていない。** 現在
> `29.0.2` が出ている(`flutter pub outdated` で確認できる)。README に
> ある「Pigeon 27.3.0 と最新の 29.0.2 のどちらでも同じコードが生成される
> ため、Pigeon の更新では解決しない」という記述は、**Swift 6 言語モードの
> 問題が Pigeon 更新で解決しないこと**を言っているだけであり、27 に留める
> 積極的な理由にはなっていない。更新するかどうかは別途判断すること。

### 1.2 Android

Android は**プラグイン側とexample app側で別々のツールチェーンを使っている**。
これは `flutter create` が生成するアプリ側のテンプレートが、プラグイン側の
`android/build.gradle` より新しい世代であることによる。片方を上げても
もう片方は自動では上がらない。

| 固定しているもの | 値 | 場所 |
|---|---|---|
| `minSdk`(プラグイン) | `31` | `packages/offline_stt_android/android/build.gradle` |
| `minSdk`(example app) | `31` | `apps/example/android/app/build.gradle.kts` |
| `compileSdk`(プラグイン) | `35` | `packages/offline_stt_android/android/build.gradle` |
| Java `sourceCompatibility` / `targetCompatibility` | `17` | `packages/offline_stt_android/android/build.gradle`、`apps/example/android/app/build.gradle.kts` |
| CIのJDK | `17`(temurin) | `.github/workflows/ci.yml` の `actions/setup-java@v4` |
| Kotlin(プラグイン) | `2.1.0` | `packages/offline_stt_android/android/build.gradle` の `ext.kotlin_version` |
| Kotlin(example app) | `2.2.20` | `apps/example/android/settings.gradle.kts` |
| AGP(プラグイン) | `8.7.0` | `packages/offline_stt_android/android/build.gradle` の `classpath` |
| AGP(example app) | `8.11.1` | `apps/example/android/settings.gradle.kts` |
| Gradle wrapper(example app) | `8.14` | `apps/example/android/gradle/wrapper/gradle-wrapper.properties` |
| kotlinx-coroutines | `1.9.0` | `packages/offline_stt_android/android/build.gradle` |

`minSdk` の意味は requirements.md NFR-4(Android 12 / API 31 以上)に由来
する。**ただし `checkRecognitionSupport()` が API 33 で追加されたAPIである
ため、API 31/32 では `checkModel()` が常に `unavailable` を返す。**
すなわち「ビルドできる下限は 31、実際に動く下限は 33」であり、この差は
意図的に残してある(design.md §4.3)。`minSdk` を 33 へ上げるかどうかは
API変更ではなく対応端末範囲の方針判断であり、requirements.md NFR-4 の
改定を伴う。

> **ローカルビルドでは JDK 17 を明示する必要がある場合がある。** 検証に
> 使ったマシンの既定JDKは 26.0.1 であり、同梱のKotlinコンパイラがその
> バージョン文字列を解釈できず `java.lang.IllegalArgumentException: 26.0.1`
> で失敗する。`JAVA_HOME` を JDK 17 に向けて実行する(手順は
> `apps/example/README.md`)。

### 1.3 Darwin(iOS / macOS)

| 固定しているもの | 値 | 場所 |
|---|---|---|
| iOS / macOS Deployment Target(プラグイン) | `26.0` | `packages/offline_stt_darwin/darwin/offline_stt_darwin.podspec` の `s.ios.deployment_target` / `s.osx.deployment_target` |
| iOS Deployment Target(example app) | `26.0` | `apps/example/ios/Podfile`(`platform :ios, '26.0'`)と `apps/example/ios/Runner.xcodeproj/project.pbxproj`(3構成すべて) |
| macOS Deployment Target(example app) | `26.0` | `apps/example/macos/Podfile`(`platform :osx, '26.0'`)と `apps/example/macos/Runner.xcodeproj/project.pbxproj`(3構成すべて) |
| Swift 言語モード | `5.0` | 同 podspec の `s.swift_version` |

`26.0` は requirements.md NFR-4(iOS 26 / macOS 26 以上)に由来する。
SpeechAnalyzer がそのOSバージョンで追加されたAPIであるためであり、
下げる余地は無い。

`s.swift_version = '5.0'` は**回避策としての固定である**。Swift 6 言語モード
(strict concurrency)では Pigeon が生成する `Pigeon.g.swift` のトップレベル
`var pigeonPigeonMethodCodec` が
`is not concurrency-safe because it is nonisolated global shared mutable state`
としてコンパイルエラーになる。Pigeon 27.3.0 と 29.0.2 のどちらでも同じ
コードが生成されるため、Pigeon の更新では解決しない。**Pigeon 側が
生成コードを直したら、この固定は外せる。**

### 1.4 Windows

| 固定しているもの | 値 | 場所 |
|---|---|---|
| WinAppSDK の要求下限 | `1.7.1` 以降 | requirements.md NFR-4、`packages/offline_stt_windows/README.md` §1、`packages/offline_stt_windows/windows/CMakeLists.txt` の冒頭コメント |
| Windows の要求下限 | Windows 11 24H2(build 26100)以降 | 同上 |
| `MaxVersionTested` | `10.0.26226.0` | `apps/example/windows/packaging/Package.appxmanifest` |
| `TargetDeviceFamily` の `MinVersion` | `10.0.17763.0` | 同上 |
| WinAppSDKヘッダーの探索先 | `.winapp/include` の自動検出(`OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR` で上書き可) | `packages/offline_stt_windows/windows/CMakeLists.txt` |
| CMake | `cmake_minimum_required(VERSION 3.15)` | 同上 |

> **経緯(Issue #68 で見つけ、同じPRで解消した)。**
> かつて design.md §4.4、`packages/offline_stt_windows/README.md` §1、
> `.github/workflows/ci.yml` の冒頭コメントの3箇所が、「実装は1.7系の最新
> サービシング `1.7.260224002` を既定としている」と書いていた。
> **しかしその時点の `CMakeLists.txt` はNuGetのバージョンを一切参照して
> いなかった。** M4の途中で `VS_PACKAGE_REFERENCES` による NuGet
> PackageReference 方式がCIで失敗し(`error C1083: Cannot open include file:
> 'winrt/Microsoft.Windows.AI.h'`)、winapp CLI が展開する `.winapp/include`
> を自動検出する方式へ切り替えた際に、バージョン番号を書く場所自体が
> 無くなったためである。**3箇所とも現在は「実際に使われるバージョンは
> `winapp init` が展開したものに決まり、プラグイン側は下限を機械的に
> 強制していない」という事実に書き換え済みである。**
>
> したがって現時点で固定されているWinAppSDKのバージョンは存在しない。
> CMake側にバージョン検証を入れるかどうかは、Windows実機での検証
> (Issue #58)に合わせて判断する。

### 1.4-b Windows AI Speech は experimental チャンネルにしか無い(実機で確定)

**Issue #15〜#18 の作業中に、Windows 11 実機で確定した事実である。**

`winapp init --setup-sdks stable` が展開する WinAppSDK **2.5.1(安定版)**には
`Microsoft.Windows.AI.Speech` が**存在しない**。生成されるプロジェクション
ヘッダーは次のとおりで、Speech が無い。

```
Microsoft.Windows.AI.ContentSafety.h
Microsoft.Windows.AI.Foundation.h
Microsoft.Windows.AI.Imaging.h
Microsoft.Windows.AI.MachineLearning.h
Microsoft.Windows.AI.Text.h
Microsoft.Windows.AI.Video.h
```

`--setup-sdks experimental`(WindowsAppSDK.AI **2.4.8-experimental**)にすると
`Microsoft.Windows.AI.Speech.h` が現れ、WinRT 実装のコンパイルが通る。

**公式ドキュメントの記述と実際の出荷物が食い違っている。**
<https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition> の
Prerequisites は「WinAppSDK version: Version 1.7.1 or later」と書いているが、
安定版 1.7 系にも 2.5 系にも当該名前空間は入っていない。

**M0 の記録(`spikes/windows/RESULTS.md`)が「API リファレンスは
`windows-app-sdk-2.0-experimental` モニカーでのみ存在する」と書いていたのが
正しく、M4 実装時に本線ドキュメントの Prerequisites を根拠に
「齟齬は解消した」と判断したのは誤りだった。** SDK を実際に展開せず
ドキュメントだけで結論を出したことが原因である。

したがって現時点では:

- Windows 実装は **experimental チャンネルの WinAppSDK を要求する**
- requirements.md NFR-4 の「WinAppSDK 1.7.1以上」は**出荷物と一致しない**
- 利用者に experimental チャンネルを要求することの是非は、公開(Issue #65)の
  判断に直結する

### 1.5 Web

| 固定しているもの | 値 | 場所 |
|---|---|---|
| Chrome の要求下限 | `142` 以降(デスクトップ版) | requirements.md NFR-4、`packages/offline_stt_web/README.md` §1、README.md 対応状況マトリクス |
| `package:web` | `^1.1.0`(offline_stt_web)/ `^1.1.1`(example) | `packages/offline_stt_web/pubspec.yaml`、`apps/example/pubspec.yaml` |

**Chrome 142 は機械的に強制される固定ではない。** ビルド時にも実行時にも
バージョン番号を検査してはおらず、実装は
`SpeechRecognition.available()` の機能検出だけを見て `unavailable` を返す。
142 という数字はドキュメント上の記述にすぎない。

### 1.6 CI のランナーとアクション

| 固定しているもの | 値 | 場所 |
|---|---|---|
| ランナーラベル | `ubuntu-latest` / `windows-2025` / `macos-26` | `.github/workflows/ci.yml` の build マトリクス |
| GitHub Actions | `actions/checkout@v4` / `subosito/flutter-action@v2` / `actions/setup-java@v4` / `actions/cache@v4` | 同上 |

`ubuntu-latest` だけがメジャー固定になっていない。GitHubがラベルの指す
実体を差し替えたときに、こちらの変更なしに挙動が変わりうる唯一の箇所である。

## 2. 破壊的変更が起きたときの手順

「破壊的変更」には2種類ある。**扱いが違うので最初に切り分ける。**

- **(A) 外部プラットフォームAPI側の変更** — OS / ブラウザ / WinAppSDK の挙動が
  変わり、こちらのコードを変えていないのに動作が変わった。
- **(B) こちらが固定している値を動かした結果の破壊** — Flutter / Kotlin /
  AGP / Pigeon 等を上げたらビルドやテストが壊れた。

### 2.1 共通の順序

1. **事実を先に確定させる。** 何がどう変わったかを、公式ドキュメント
   または実測で確認する。リリースノートの文面だけで挙動を推定しない。
   確認先は [MONITORING.md](./MONITORING.md) 1節の表。
2. **影響範囲を書き出す。** 対象プラットフォーム、影響するFR / NFR、
   design.md の該当節(§4.x / §5 / §8)、公開API(design.md §2)に
   出るかどうか。
3. **公開APIに出るかどうかで扱いを分ける。**
   - 公開APIの形が変わらない → 実装パッケージ内で吸収する。
   - 公開APIの形が変わる → requirements.md / design.md の改定を伴う
     破壊的変更として扱う。requirements.md NFR-5 のとおり、本ライブラリは
     各OS APIがstable化するまで **0.x 系で公開する**方針であり、0.x では
     マイナー更新が破壊的変更を含みうる。破壊的変更そのものを避けるのでは
     なく、**CHANGELOG に何が壊れるかを明記する**ことで扱う。
4. **回避策を入れるなら、黙って倒さない。** リポジトリの方針として
   **フォールバックは禁止**である。値が取れないときに既定値で取り繕うのでは
   なく、明示的に失敗させる。現に Windows 実装は、WinAppSDK ヘッダーが
   見つからない場合に黙って `unavailable` を返すのではなく「`winapp init`
   を実行せよ」という明示的なエラーで失敗させている。正確には、CMake は
   ビルドを中止せず音声認識を無効にした実装(`speech_backend_unavailable.cpp`)
   を組み込み、そのバックエンドがモデル状態の照会・モデル取得・文字起こしを
   `kPlatformError` で失敗させる(`cancel()` は止める対象が無いため何もしない)。
5. **E2Eを再実行する。** 範囲の決め方は [MONITORING.md](./MONITORING.md) 3節。
6. **文書を直す。** 下記「どこを直すか」。
7. **推測を実測として書かない。** 確認できなかったことは「未確認」と書く。
   リポジトリ全体がこの方針で書かれており、対応状況マトリクス(README.md)
   も実測していない欄は「未検証」と明記している。

### 2.2 (A) 外部API側の変更への追従

上記に加えて次を行う。

- **その挙動に依存している実装を洗い出す。** 本ライブラリは「ドキュメントに
  無い実測された挙動」に依存している箇所が複数ある。いずれも壊れれば
  文字起こしが成立しなくなる。
  - Android: `onResults()` が `null` のとき直前の `onPartialResults()` の
    最上位候補を確定結果として採用する(design.md §4.3)
  - Android: `triggerModelDownload()` の完了を `checkRecognitionSupport()`
    の再照会で判定する(同上)
  - Web: `source.onended` で明示的に `recognition.stop()` を呼んで
    終了検出する(design.md §4.1・§8 未決事項4)
  - Web: `isFinal` が立たない場合に末尾のinterim結果を採用する(同上)
  - Windows: `RecognizeFromFile()` に渡す前に常に Media Foundation で
    16kHz・モノラル・16-bit PCM の wav へ変換する(design.md §8 未決事項1。
    **対応フォーマットもこの出力形式の妥当性も未確定のままである**)
- **依存先の要求下限が上がった場合**は requirements.md NFR-4 の改定に
  なる。対応端末・対応OSの範囲が狭まるため、実装判断ではなく要件判断
  として扱う。

### 2.3 (B) 固定値を動かすときの手順

1. **1つずつ動かす。** 複数のバージョンを同時に上げると、壊れたときに
   どれが原因か切り分けられない。
2. **表1.1〜1.6で「同時に直す場所」を確認する。** 同じ値が複数ファイルに
   書かれているものは片方だけ直さない。特に Dart SDK(8ファイル)と
   Flutter SDK(CI 1箇所 + pubspec 6箇所)。
3. **CIを通す。** `melos run analyze` / `melos run test` / `melos run format`
   / `melos run doc` と、5プラットフォームのビルド。
4. **CIでは検証できない部分を意識する。** 特に Windows ジョブは
   winapp CLI を持たないため **WinRT実装をコンパイルしていない**。
   CIが緑でも、Windows AI に触れる部分が壊れていないことの証明にはならない。
5. **E2Eを再実行する。** ビルドが通ることと認識が成立することは別である。
6. **変更の理由をコメントとして残す。** このリポジトリは
   `podspec` の `swift_version` や Windows の `CMakeLists.txt` のように、
   「なぜその値なのか」を固定箇所そのものに書く流儀で通っている。

### 2.4 どこを直すか

| 変わったもの | 直す場所 |
|---|---|
| 要求OS / SDK の下限 | requirements.md NFR-4 |
| APIの挙動・制約・エラー写像 | design.md §4.1〜§4.4 / §5 |
| 未決事項の解消 / 再発 | design.md §8 |
| 公開APIの形 | design.md §2、および各パッケージの dartdoc |
| プラットフォーム別の利用者向け注意 | 各 `packages/*/README.md`、ルート README.md「アプリ側に必要な対応」 |
| 対応状況・実測値 | README.md 対応状況マトリクス(**実測していない欄は「未検証」のまま**) |
| E2E手順 | `E2E_CHECKLIST.md` と `packages/*/E2E_CHECKLIST.md` |
| 監視対象そのもの | [MONITORING.md](./MONITORING.md) |
| 固定値 | 本書 1節の表 |

## 3. 実行記録

| 実施日 | 動かした / 壊れた固定値 | 対応 | E2E再実行 |
|---|---|---|---|
| — | — | — | **本書の手順を実際に回した実績は無い。** |

現時点で判明している未処理事項は次の2件である。

- ~~1.4節の `1.7.260224002` の記述が3箇所に残っているが、現在の
  `CMakeLists.txt` からは効いていない~~ → **本 PR で処理済み。**
  `design.md` §4.4 / `packages/offline_stt_windows/README.md` §1 /
  `.github/workflows/ci.yml` 冒頭コメントの3箇所から「既定は
  `1.7.260224002`」という記述を除き、**実際のバージョンは
  `winapp init` が `.winapp/include` へ展開したものに決まり、
  プラグイン側は下限を機械的に強制していない**という事実に書き換えた。
- 1.1節のとおり、Pigeon を `^27.3.0` に留める積極的な理由が記録されて
  いない(現在 `29.0.2` が存在する)。
