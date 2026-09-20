# M0 検証スパイク: Windows(Windows AI APIs Speech Recognition)

対応 Issue: #15(モデル状態照会・取得)/ #16(ファイル入力文字起こし・フォーマット受理)/
#17(ロケール照会)/ #18(systemAIModels capability検証)。
対応する設計: design.md §4.4 Windows、§5 エラーマッピング(Windows列)、§7 テスト戦略・
評価基準(キーワード包含率)、§8 未決事項1・2。
対応するタスク: tasks.md「M0 検証スパイク」> Windows セクション。

> **本ディレクトリは macOS 上で開発された。Windows 機を一度も使用していないため、
> 以下のコードは一度もビルド・実行されていない。** ビルドが通ること・実際に動作する
> ことのいずれも確認できていない。コード中および本ドキュメント中の「要確認」は、
> Microsoft公式ドキュメント(learn.microsoft.com)で確認できなかった、実機での
> 検証が必要な事項を指す。実測値はすべて `RESULTS.md` に `(未実施 — Windows機なし)`
> として明記している。捏造した数値は一切含まれていない。

このディレクトリは、Flutterライブラリの実装(M4)に入る前に「Windows上で
Windows AI APIs の Speech Recognition(`Microsoft.Windows.AI.Speech`)による
ファイル入力オフライン文字起こしが実際に動くか」を確認するための、Flutter外の
単体 C++/WinRT コンソールアプリ(MSIXパッケージ化)である。`spikes/darwin/`
(SwiftPMスパイク)・`spikes/web/`(HTML/JSスパイク)とディレクトリ構成・文書の
粒度を揃えている。

## 前提

- **Windows 11, version 24H2 (build 26100) 以上**。design.md §4.4 / requirements.md
  §8 / NFR-4 に準拠。
- **WinAppSDK 1.7.1 以上**(requirements.md NFR-4の記載)。ただし本スパイクの文献
  調査では、`Microsoft.Windows.AI.Speech` 名前空間のAPIリファレンスページ自体が
  `windows-app-sdk-2.0-experimental` モニカーでのみ存在し、1.7 / 1.8 / 2.0(安定版)
  のいずれのモニカーにも掲載されていないことを確認した(RESULTS.md「ドキュメント
  調査で確定した事項」参照)。したがって実際に動作を確認するには、NuGetパッケージ
  マネージャーで「プレリリースを含める」を有効にし、Speech Recognition APIが
  含まれる最新のExperimentalチャンネル版 `Microsoft.WindowsAppSDK` を選定する必要が
  ある可能性が高い。これは requirements.md/design.md の「WinAppSDK 1.7.1以上」という
  記載との齟齬であり、詳細は本READMEおよびRESULTS.mdの「design.md/requirements.md
  との齟齬」に記録している。
- **MSIXパッケージ化が必須である理由**: Windows AI APIsの利用にはMSIXパッケージへの
  `systemAIModels` capability宣言が必須であることをMicrosoft公式ドキュメントで
  確認済み(下記「systemAIModels capabilityを宣言しないとどうなるか」参照)。
  素のWin32 EXEのまま(非MSIX)では `Not declared by app` 相当のエラーとなる
  (get-started.md「CapabilityMissing ... add the systemAIModels capability to the
  app manifest」より)。
- **ハードウェア**: Copilot+ PC(NPU搭載)ではモデルはプリインストール済み。
  CPUのみの機種でも動作するが、モデルは初回 `EnsureReadyAsync()` 呼び出し時に
  Windows Update経由でバックグラウンドダウンロードされる(GPUは非対応)。
  出典: https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition
  「Supported hardware」節。

## ディレクトリ構成

```
spikes/windows/
├── README.md                                   … 本ファイル
├── RESULTS.md                                   … ドキュメント調査結果(実測値は全て未実施)
├── .gitignore
├── WindowsSTTSpikeCli.vcxproj                   … C++/WinRTコンソールEXE(Core+Cli統合)
├── src/
│   ├── Core/
│   │   ├── pch.h / pch.cpp                       … 共通インクルード
│   │   ├── Support.h / .cpp                       … 共通エラー分類・基準音声パス解決・タイムアウト
│   │   ├── Json.h / .cpp                          … 依存追加を避けた最小手書きJSON
│   │   ├── ModelReadiness.h / .cpp                … Issue #15: GetReadyState/EnsureReadyAsync
│   │   ├── LocaleInquiry.h / .cpp                 … Issue #17: ロケール照会
│   │   ├── FileRecognition.h / .cpp               … Issue #16: TryCreateAsync/RecognizeFromFile
│   │   ├── KeywordScoring.h / .cpp                … design.md §7 キーワード包含率
│   │   ├── CapabilityCheck.h / .cpp               … Issue #18: capability検証
│   │   └── CliReport.h / .cpp                     … CLI出力・JSON化
│   └── Cli/
│       └── main.cpp                               … サブコマンド実装・エントリポイント
├── packaging/
│   ├── Package.appxmanifest                       … systemAIModels宣言「あり」
│   ├── Package.NoCapability.appxmanifest          … systemAIModels宣言「なし」(Issue #18対比用)
│   ├── WindowsSTTSpikePackage.wapproj             … MSIXパッケージングプロジェクト(あり版)
│   ├── WindowsSTTSpikePackage.NoCapability.wapproj … 同(なし版)
│   └── Assets/PLACEHOLDER.txt                     … 画像アセットについての注記(実ファイル未同梱)
├── scripts/
│   └── generate_mp3.sh                            … test-assets/baseline-audioのwavからmp3を生成
└── fixtures/mp3/                                   … 上記スクリプトの生成物(Issue #16フォーマット受理テスト用)
```

## ビルド方法(MSBuild を選択した理由)

**MSBuild(.vcxproj / .wapproj)を採用した。CMakeは採用しなかった。**

理由:

1. `Microsoft.WindowsAppSDK` NuGetパッケージは、C++/WinRTプロジェクション
   ヘッダー(`winrt/Microsoft.Windows.AI.Speech.h` 等)の自動生成を
   `Microsoft.Windows.CppWinRT` NuGetパッケージのMSBuildターゲット
   (`.targets`/`.props`)経由で行う。これはMicrosoft公式ドキュメントの
   get-started.mdが示す手順(Visual StudioでNuGetパッケージマネージャーから
   `Microsoft.WindowsAppSDK` をインストールし、ビルドする)が前提とする
   標準的な統合方法である。
2. CMakeでも `cmake-msix`(サードパーティ、holepunchto/cmake-msix)等を使えば
   MSIXパッケージ自体は生成できることをWebSearchで確認したが、
   `Microsoft.Windows.AI.Speech` のプロジェクションヘッダー生成
   (`cppwinrt.exe` を WindowsAppSDK の winmd に対して手動実行する経路)を
   CMakeから行う公式・準公式の手順は見つからなかった。誤った手動呼び出しを
   書いて「動くはず」と主張することは本タスクの制約(推測実装の禁止)に反するため、
   MSBuildの標準統合を選んだ。
3. ただし、**本スパイクのvcxproj/wapprojはWindows機で一度も開けておらず、
   ビルドが通ることを確認できていない**(冒頭の注記のとおり)。特に以下は
   要確認である:
   - `Microsoft.WindowsAppSDK` / `Microsoft.Windows.CppWinRT` の正確な
     バージョン番号(`WindowsSTTSpikeCli.vcxproj` 内にプレースホルダで記載)。
   - VC++プロジェクトでの `PackageReference` 形式NuGet復元の可否
     (`RestoreProjectStyle=PackageReference` を設定しているが、環境によっては
     `packages.config` 形式への切り替えが必要な場合がある)。
   - `WindowsSTTSpikePackage.wapproj` の詳細設定(Visual Studioのプロジェクト
     ウィザードが生成する詳細を完全に再現できているかは未検証。
     `packaging/WindowsSTTSpikePackage.wapproj` 冒頭のコメント参照)。

**Visual Studioが無い環境でもビルドできるか**: 部分的に可能と考えられるが未検証。
`msbuild.exe` と `nuget.exe`(またはdotnet CLIのNuGet復元)がPATH上にあれば
`WindowsSTTSpikeCli.vcxproj` 単体(EXEのビルドのみ、MSIX化なし)はビルドできる
可能性がある。ただし `WindowsSTTSpikePackage.wapproj` が依存する
`Microsoft.AppXPackage.Targets` は、Visual Studioの「ユニバーサル Windows
プラットフォーム開発」ワークロード(またはそれに相当するWindows SDK
コンポーネント)のインストールに付随して配置されるものであり、
Visual Studio Build Tools(IDEなしのビルドツールのみ)でこのワークロードを
個別インストールした場合に同じパスへ配置されるかは未確認である。
したがって「Visual Studio IDE本体は不要だが、Visual Studio Build Tools +
該当ワークロードは必要」という位置づけを想定しているが、この境界線自体が
要確認事項である。

### ビルド手順(想定。未検証)

```powershell
cd spikes\windows

# NuGet復元(Microsoft.WindowsAppSDK / Microsoft.Windows.CppWinRT / icu.lib同梱のWindows SDK)
nuget restore WindowsSTTSpikeCli.vcxproj
# または: msbuild -t:restore WindowsSTTSpikeCli.vcxproj

# コンソールEXE単体ビルド(MSIX化なし。動作確認にはMSIX化が必須なので最終的には下記が必要)
msbuild WindowsSTTSpikeCli.vcxproj /p:Configuration=Debug /p:Platform=x64

# MSIXパッケージ化(systemAIModels宣言あり版)
msbuild packaging\WindowsSTTSpikePackage.wapproj /p:Configuration=Debug /p:Platform=x64

# MSIXパッケージ化(systemAIModels宣言なし版。Issue #18対比用)
msbuild packaging\WindowsSTTSpikePackage.NoCapability.wapproj /p:Configuration=Debug /p:Platform=x64
```

生成されたMSIXをサイドロードでインストールし(未署名の場合は開発者モードの
有効化、またはテスト証明書での署名が必要。この署名手順自体も要確認)、
インストール後のアプリとして各サブコマンドを実行する。

## 各サブコマンドの実行方法

MSIXとしてインストール後、パッケージ化されたアプリ内から
`WindowsSTTSpikeCli.exe <command> [options]` を実行する(コンソールアプリだが
MSIX内で実行する必要がある。Desktop BridgeパッケージのEXEは、インストール後は
スタートメニューからの起動、または `explorer.exe shell:AppsFolder\<PackageFamilyName>!App`
形式のAppUserModelIdを介した起動が一般的である。コマンドライン引数を渡しながらの
起動方法の詳細はWindows機での確認が必要)。

| サブコマンド | 内容 | 対応Issue |
|---|---|---|
| `model-state` | `SpeechRecognitionModel.GetReadyState()` を1回呼び、raw値とFR-1の4値写像を出力する | #15 |
| `model-ensure [--timeout <seconds>]` | `EnsureReadyAsync()` を実行し、`Progress`ハンドラのコールバック回数・`Progress.Status`遷移を記録する(進捗の粒度の実測) | #15 |
| `locale` | ロケール指定APIが存在しないことの確認結果と、OS側のロケール設定(`GetUserDefaultLocaleName`等)を出力する | #17 |
| `capability-check` | `GetReadyState()`/`EnsureReadyAsync()` を呼び、`CapabilityMissing`状態またはaccess_denied例外の有無を記録する。`Package.appxmanifest`版と`Package.NoCapability.appxmanifest`版の両方で実行し比較する | #18 |
| `transcribe <clipId> [--format wav\|m4a\|mp3] [--baseline-dir <path>] [--json]` | 1クリップを `TryCreateAsync` → `BatchRecognition.RecognizeFromFile` で認識し、所要時間・キーワード包含率を出力する | #16 |
| `format-test <clipId> [--baseline-dir <path>] [--json]` | 同一クリップの wav/m4a/mp3 を順に `RecognizeFromFile` へ渡し、受理/拒否を記録する(design.md §8 未決事項1) | #16 |
| `all [--baseline-dir <path>] [--timeout <seconds>] [--json]` | `test-assets/baseline-audio` の ja-JP/en-US × 10秒/3分 × wav/m4a の計8ファイルについて、モデル状態確認・認識・キーワード包含率スコアリングを一括実行する | #15/#16 |

`--json` を付けると、人間可読ログに加えて機械可読JSON(RESULTS.md転記用)を
追加出力する。

`test-assets/baseline-audio/` の探索は `spikes/darwin` 同様、実行カレント
ディレクトリから親をたどって自動検出する(`Support.h` の `ResolveBaselineAudioDir`)。
明示的に指定したい場合は `--baseline-dir <path>` を使う。

### Issue #16: mp3フィクスチャの準備

`test-assets/baseline-audio/` にはmp3が含まれないため(design.md §7注記のとおり
M0スコープはwav/m4aのみ)、`scripts/generate_mp3.sh` で `spikes/windows/fixtures/mp3/`
にwavから変換したmp3を生成済みである(共通資産`test-assets/`自体は変更していない)。
Windows実機では、`fixtures/mp3/*.mp3` を `test-assets/baseline-audio/` と同じ
ディレクトリ(または `--baseline-dir` で指定する任意のディレクトリ)へコピーしてから
`format-test` を実行すること。

## `systemAIModels` capability を宣言しないとどうなるか(Issue #18)

Microsoft公式ドキュメント(get-started.md、2026-09-20 WebFetchで確認)は、
`Microsoft.Windows.AI.AIFeatureReadyState.CapabilityMissing` の説明として次のように
明記している(WinAppSDK 2.0以降で利用可能な値):

> Model is not available to the current app due to a missing capability
> declaration. EnsureReadyAsync and CreateAsync will throw
> `winrt::hresult_access_denied` (add the systemAIModels capability to the app
> manifest).

これは `Microsoft.Windows.AI.Text.LanguageModel` についての記述であり、
`Microsoft.Windows.AI.Speech.SpeechRecognitionModel` について同一の記載は
確認できなかった(**要確認**。ただし両クラスとも同じ `Microsoft.Windows.AI`
名前空間の `AIFeatureReadyState` を共有しているため、同様のパターンが適用される
可能性が高いと考えられる)。

本スパイクの `capability-check` サブコマンドは、`GetReadyState()` の戻り値が
`CapabilityMissing` であるか、`EnsureReadyAsync()` が
`winrt::hresult_access_denied`(HRESULT `0x80070005`)を送出するかを見て判定する
(`src/Core/CapabilityCheck.cpp`)。この判定ロジック自体は Speech Recognition API
で未検証であるため、`packaging/Package.appxmanifest`(宣言あり)と
`packaging/Package.NoCapability.appxmanifest`(宣言なし)の両方でMSIXを作成し、
両方で `capability-check` を実行して結果を突き合わせることを実機検証の手順として
想定している。結果は RESULTS.md に記録すること(現状は両方とも
`(未実施 — Windows機なし)`)。

なお、`AIFeatureReadyState.CapabilityMissing` はWinAppSDK 2.0以降で追加された値
であり(learn.microsoft.comのAIFeatureReadyState列挙体ページに明記)、
requirements.mdが指定するWinAppSDK 1.7.1上でこの値が実際に返るのか、あるいは
別の挙動(例外が飛ぶだけでこの列挙値自体は存在しない等)になるのかは確認できて
いない。**要確認**。

## design.md §7 のしきい値(キーワード包含率)への参照

`src/Core/KeywordScoring.h` の `ScoringThresholds` にまとめている。design.md §7由来。

- ja-JP: 95%以上で合格、90〜94%で条件付き合格、90%未満で不成立
- en-US: 95%以上で合格、95%未満で不成立

正規化ルール(NFKC正規化 → 小文字化 → 句読点・記号除去 → 空白除去、ja-JPは
さらにひらがな→カタカナ畳み込み)は design.md §7 に従って実装した。使用したAPI
(Win32 `NormalizeString`、Windows同梱ICUの `u_charType`/`u_tolower`、
コードポイント演算によるひらがな→カタカナ畳み込み)の選定理由は
`src/Core/KeywordScoring.h` のコメントに詳しく記載している。

spikes/darwinの実測(8ファイル中8ファイルが不成立)を踏まえ、design.mdの
「M0出口判定で決めるべき事項」(しきい値・正規化規則・プリセット等の見直し)が
Windows側にも影響しうる。Windows側は実機が無いためこの検証自体ができていない。

## 要確認事項の一覧(実装時に必ず確認すること)

コード中に個別コメントで記載しているものを含め、以下は本スパイクでは確定できず
Windows実機・公式ドキュメントの追加調査が必要な事項である。

1. `Microsoft.WindowsAppSDK` / `Microsoft.Windows.CppWinRT` の正確なバージョン
   番号とチャンネル(Experimental/Stable)。
2. `RecognizeFromFile` が実際に受理する音声フォーマットの一覧(design.md §8
   未決事項1。ドキュメントに記載無し)。
3. `BatchRecognition.Recognize(Byte[])` が期待するバイト列の形式
   (生PCMか、エンコード済みファイルのバイト列をそのまま渡せるか)。
4. `SpeechRecognitionModelResult.ExtendedError` / `AIFeatureReadyResult.Error` /
   `AIFeatureReadyResult.ExtendedError` の正確な型(`winrt::hresult` 前提で
   実装したが未検証)。
5. `AIFeatureReadyState.CapabilityMissing` はWinAppSDK 2.0以降の値と明記されて
   おり、1.7.1環境での挙動。
6. `EnsureReadyAsync()` の `Progress` コールバックが実際にどの程度の頻度・粒度で
   発火するか(tasks.md「進捗の粒度」)。
7. `WindowsSTTSpikePackage.wapproj` の詳細設定がVisual Studio生成物と同等か。
8. MSIXの署名・サイドロード手順(未署名での動作可否、開発者モードの要否)。
9. Desktop Bridge(`Windows.FullTrustApplication` + `runFullTrust`)と
   `systemAIModels` capabilityの組み合わせが公式にサポートされるか
   (公式サンプルはWinUI3/WPF/WinForms/.NET MAUIのみを示している)。
10. コンソールアプリのMSIXパッケージに対する、コマンドライン引数付きの起動方法。

## design.md §8 未決事項1・2 への回答

- **未決事項1(RecognizeFromFileの対応フォーマット)**: ドキュメント調査だけでは
  確定できなかった。`BatchRecognition.RecognizeFromFile` のAPIリファレンス
  ページにはフォーマットに関する記載が一切無い。`format-test` サブコマンドに
  よる実機検証が必要(RESULTS.md「実機でのみ確認可能な事項」参照)。
- **未決事項2(ロケール指定可否)**: ドキュメント調査で確定できた。
  `Microsoft.Windows.AI.Speech` 名前空間の全クラス・全メンバーを確認した結果、
  ロケール・言語を指定するAPIは存在しない(`src/Core/LocaleInquiry.h` 参照)。
  「無いことの実機での帰結」(実際にどの言語で認識するか)は別途実機確認が必要。

## `spikes/darwin` / `spikes/web` / `spikes/android` との対応

基準音声セット(`test-assets/baseline-audio/`)・キーワード包含率の算出式・
しきい値は他プラットフォームのスパイクと共通である。CLIのサブコマンド構成
(`model-state`/`transcribe`/`all` 等)は `spikes/darwin` の
`darwin-stt-spike` サブコマンド構成に対応させている。
