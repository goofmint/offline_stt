# offline_stt

録音済み音声ファイルを、OSネイティブの音声認識APIのみでオフライン文字起こしするFlutterライブラリ(モノレポ)。詳細な要件・設計は [requirements.md](./requirements.md) / [design.md](./design.md) / [tasks.md](./tasks.md) を参照。

このREADMEは最小限の構成案内のみを記載する。本格的なREADME(対応状況マトリクス等)はIssue #60〜#62で整備する。

## モノレポ構成

**Melos + Dart Pub Workspaces**(Melos 8系)を採用している。ルート `pubspec.yaml` の `workspace:` キーで全パッケージを列挙し、`melos:` キーにMelosのスクリプト定義を集約している(`melos.yaml` は使わない)。

```
offline_stt/
├── pubspec.yaml                          … workspace定義 + melos設定
├── packages/
│   ├── offline_stt/                      … エントリパッケージ(利用者はこれのみに依存)
│   ├── offline_stt_platform_interface/   … 共通抽象・データ型・例外(純Dart)
│   ├── offline_stt_android/              … Kotlin実装(ML Kit GenAI Speech Recognition)
│   ├── offline_stt_darwin/               … Swift実装(iOS/macOS共用、SpeechAnalyzer)
│   ├── offline_stt_windows/              … C++/WinRT実装(Windows AI Speech Recognition)
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
| build (windows) | windows-2025 | `apps/example` の `flutter build windows --debug` |
| build (macos) | macos-26 | `apps/example` の `flutter build macos --debug` |
| build (ios) | macos-26 | `apps/example` の `flutter build ios --no-codesign --debug` |

**CIが検証すること**: 全パッケージの静的解析・ユニットテスト・フォーマット、および `apps/example` の各プラットフォーム向けコンパイル(ビルド検証のみ)。

**CIが検証しないこと(design.md §7 の方針)**: 認識E2E(実際の音声ファイルが正しく文字起こしされるか)。以下のとおり実機依存であることが実測済みであり、CI環境では原理的に再現できないため、リリース前の手動チェックリストで運用する。

- iOS: シミュレータでは `SpeechTranscriber.isAvailable` が `false` になり、SpeechAnalyzerによる認識自体が利用できない(`spikes/darwin/RESULTS.md`)
- Android: エミュレータでは `checkStatus()` が `UNAVAILABLE` になる(AICore非搭載。`spikes/android/RESULTS.md`)
- Web: ブラウザの言語パック(約60MB)取得と実ブラウザ環境が必要であり、ヘッドレスCIでは再現しない(`spikes/web/RESULTS.md`)

**ランナー・SDKバージョンの調査結果**(2026-09時点):

- `macos-26` ラベルは 2026-02-26 にGitHub ActionsでGA済み(既定Xcode 26.4.1、26.5等も選択可能)であり、requirements.md NFR-4「iOS 26 / macOS 26 以上」を満たすビルド環境として利用できる。
- `windows-2025` ラベル(Windows Server 2025)もGA済み。requirements.md NFR-4「Windows 11 24H2 (build 26100)」とOSビルド世代は揃うが、GitHub Hosted RunnerにWindows 11クライアント版は存在せず、Server版である点に注意。
- `offline_stt_windows/windows/CMakeLists.txt` のWinAppSDK取り込み方式はM4で二転した。当初はCMakeの `VS_PACKAGE_REFERENCES` でNuGetのPackageReferenceを足す方式にしたが、**CIで実際にビルドして失敗した**(`error C1083: Cannot open include file: 'winrt/Microsoft.Windows.AI.h'`)。WinAppSDKのプロジェクションヘッダーはWindows SDKに含まれず、NuGetパッケージ内の `.winmd` から `cppwinrt.exe` が生成するものであり、CMakeが生成する `.vcxproj` にPackageReferenceを足すだけでは復元も生成も走らなかった。現在は winapp CLI(`winapp init`)がアプリ側に展開する `.winapp/include` を自動検出する方式である。
- **したがって、CIのWindowsジョブはWinRT実装をコンパイルしていない。** CIランナーは winapp CLI を持たないため、`speech_backend_winrt.cpp` / `model_availability.cpp` / `model_acquisition.cpp` / `recognition_session.cpp` はビルド対象から外れ、`speech_backend_unavailable.cpp` がリンクされる。CIが検証しているのはWinRTに触れない部分(Pigeon受け口・スレッド調停・エラー分類・Media Foundation変換)のコンパイルだけである。**WinRT実装のコンパイルは一度も通っていない。** 確認はIssue #58の実機検証に委ねている。

**ローカルで検証済みのビルド**:

| ビルド | 結果 |
|---|---|
| `flutter build web` | 成功 |
| `flutter build macos --debug` | 成功(Xcode 26.6 / macOS 26.5.1) |
| `flutter build ios --no-codesign --debug` | 成功(Xcode 26.6) |

android / windows はローカル環境の制約(JDK バージョン、OS)により未検証であり、CI が初回の検証となる。

**Swift の言語モードについて**: `offline_stt_darwin.podspec` は `s.swift_version = '5.0'` を指定している。Swift 6 言語モード(strict concurrency)では、Pigeon が生成する `Pigeon.g.swift` のトップレベル `var`(`pigeonPigeonMethodCodec`)が `is not concurrency-safe because it is nonisolated global shared mutable state` としてコンパイルエラーになる。Pigeon 27.3.0 と最新の 29.0.2 のどちらでも同じコードが生成されるため、Pigeon の更新では解決しない。Swift 5 モードでも async/await と actor は使えるため、design.md §4.2 の SpeechAnalyzer 連携(M2)には支障がない。

**その他の注意点**:

- ネイティブプロジェクトのうち **ios / macos / web(Issue #41)と windows(Issue #59)はリポジトリにコミット済み**である。android のみ、CIジョブ内で `flutter create . --platforms=android` により都度生成する(既存の `lib/` `pubspec.yaml` は保持される、公式にサポートされた再実行可能な操作)。
- `apps/example/windows` をコミット対象に含めたのは、**MSIXパッケージ化に必要な `Package.appxmanifest` が `flutter create` の生成物に含まれない**ためである。CIと同じ Flutter 3.41.9 で `flutter create . --platforms=windows --org com.moongift` を実行した出力をそのままコミットし、`flutter create` が作らないMSIX関連ファイルを `apps/example/windows/packaging/` に追加している。
- **CIのWindowsジョブが検証するのは `flutter build windows --debug` が通ること(コンパイル・リンク)だけであり、MSIXパッケージ化は検証しない。** `flutter build windows` が生成するのはパッケージ化されていない素のWin32 EXEであり、Windows AIのモデルへアクセスするのに必要な `systemAIModels` capability はMSIXの `Package.appxmanifest` にしか書けない。MSIX化は `flutter build windows` の外側の工程である(→ [packages/offline_stt_windows/README.md](./packages/offline_stt_windows/README.md))。Windows実機が無いため、MSIX生成・インストール・認識E2Eはいずれも未実施であり、Issue #58 の対象である。
- macOS/iOSのDeployment Target引き上げ(26.0、`offline_stt_darwin.podspec` の要求)は、ネイティブプロジェクトをコミットした時点で反映済みであり、CI内での `sed` は不要になったため削除した。
- Androidビルドジョブでは、`flutter create` が生成する既定の minSdk(24)が `offline_stt_android` の要求する 31(requirements.md NFR-4: Android 12 / API 31 以上)より低いため、CI内で 31 へ引き上げてからビルドしている。引き上げないとマニフェストのマージが `uses-sdk:minSdkVersion 24 cannot be smaller than version 31 declared in library [:offline_stt_android]` で失敗することを、CI の実行で実際に確認した。

## プラットフォーム別の追加セットアップ

- **Windows**: アプリを **MSIXでパッケージ化し、`Package.appxmanifest` に `systemAIModels` capability を宣言する**必要がある。依存関係を書くだけでは動かない唯一のプラットフォームである。手順・記載例・モデル削除時の再同意フロー・既知の制約は [packages/offline_stt_windows/README.md](./packages/offline_stt_windows/README.md) にまとめてある(Issue #57)。example app 固有の手順は [apps/example/windows/packaging/README.md](./apps/example/windows/packaging/README.md)。
- Android / iOS / macOS / Web: 追加のセットアップは不要(モデルダウンロードの同意UIはいずれのプラットフォームでもアプリ側の責務である。requirements.md §8)。

## 現状

`offline_stt_platform_interface` と Web / Darwin(iOS・macOS)/ Android / Windows の各実装が入っている(tasks.md の M1〜M4)。ただし **Windows実装は一度もWindows実機で動かしていない**(Windows機が無い。Issue #58)。エントリパッケージ `offline_stt` は現時点で利用者向けのファサードクラスをまだ持たず、example app は暫定的に `OfflineTranscriberPlatform.instance` を直接使用している(`apps/example/pubspec.yaml` のコメント参照)。
