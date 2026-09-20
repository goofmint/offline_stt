# RESULTS.md — M0 Windowsスパイク結果

対応 Issue: #15 / #16 / #17 / #18。対応する設計: design.md §4.4 Windows、§5 エラーマッピング、
§7 テスト戦略・評価基準、§8 未決事項1・2。

**本ファイルに実測値は一切含まれない。** 本スパイクはmacOS上で開発されており、Windows機を
一度も使用していない。ビルド・実行のいずれも行っていないため、動作結果・所要時間・認識精度
などの実測値欄はすべて `(未実施 — Windows機なし)` と明記する。本スパイクの唯一の実質的な成果は、
下記「ドキュメント調査で確定した事項」である。

## 検証環境

| 項目 | 値 |
|---|---|
| 実行日時 | (未実施 — Windows機なし) |
| ホストOS | (未実施 — Windows機なし)。本スパイクの作成自体はmacOS 26.5.1 (build 25F80), arm64 上で行った |
| Windows バージョン | (未実施 — Windows機なし)。要件: Windows 11, version 24H2 (build 26100) 以上 |
| WinAppSDK バージョン | (未実施 — Windows機なし)。requirements.md記載は1.7.1以上。ただし下記「ドキュメント調査で確定した事項」参照 |
| ハードウェア(NPU有無) | (未実施 — Windows機なし) |
| adb/デバイス相当の接続確認 | (未実施 — Windows機自体が存在しない) |

## Issue #15: モデル状態照会・取得(GetReadyState / EnsureReadyAsync)

| 項目 | 値 |
|---|---|
| `GetReadyState()` の初期値 | (未実施 — Windows機なし) |
| FR-1 4値への写像結果 | (未実施 — Windows機なし)。写像方針自体は `src/Core/ModelReadiness.h` にドキュメント調査に基づき実装済み |
| `EnsureReadyAsync()` 所要時間 | (未実施 — Windows機なし) |
| `Progress` コールバックの発火回数・粒度 | (未実施 — Windows機なし) |
| `SpeechRecognitionModelProgressStatus` の遷移順序 | (未実施 — Windows機なし) |

コードは実装済み(`src/Core/ModelReadiness.h` / `.cpp`)。ビルド未検証(README冒頭参照)。

## Issue #16: ファイル入力文字起こし・フォーマット受理テスト

| クリップID | 形式 | 認識結果 | 所要時間 | キーワード包含率 | 判定 |
|---|---|---|---|---|---|
| jaJP_10s | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_10s | mp3 | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | mp3 | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_10s | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_10s | mp3 | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_3m  | mp3 | (未実施) | (未実施) | (未実施) | (未実施) |

### フォーマット受理テスト(design.md §8 未決事項1)

| クリップID.形式 | 受理/拒否 | エラー詳細 |
|---|---|---|
| *.wav | (未実施) | (未実施) |
| *.m4a | (未実施) | (未実施) |
| *.mp3 | (未実施) | (未実施) |

mp3フィクスチャは `scripts/generate_mp3.sh` により `spikes/windows/fixtures/mp3/` へ
実際に生成済み(wav→mp3変換自体はmacOS上でffmpegを使い実行できるため、この生成物のみは
捏造ではなく実データである)。ただし `RecognizeFromFile` への投入・受理判定はWindows機が
必須のため未実施。

コードは実装済み(`src/Core/FileRecognition.h` / `.cpp`、CLIサブコマンド `transcribe` /
`format-test`)。ビルド未検証。

## Issue #17: ロケール照会

| 項目 | 値 |
|---|---|
| ロケール指定APIの有無 | **ドキュメント調査で確定(実機不要)**: 存在しない。下記「ドキュメント調査で確定した事項」参照 |
| `GetUserDefaultLocaleName()` 等の実測値 | (未実施 — Windows機なし) |
| ja-JPが実際に認識されるか(無指定での言語推定含む) | (未実施 — Windows機なし。「実機でのみ確認可能な事項」参照) |

コードは実装済み(`src/Core/LocaleInquiry.h` / `.cpp`)。ビルド未検証。

## Issue #18: systemAIModels capability 検証

| 項目 | 値 |
|---|---|
| capability宣言「あり」版での `GetReadyState()`/`EnsureReadyAsync()` 結果 | (未実施 — Windows機なし) |
| capability宣言「なし」版での `GetReadyState()`/`EnsureReadyAsync()` 結果 | (未実施 — Windows機なし) |
| `CapabilityMissing` / `hresult_access_denied` の観測有無 | (未実施 — Windows機なし) |

対比用の2種のMSIXマニフェスト(`packaging/Package.appxmanifest` /
`packaging/Package.NoCapability.appxmanifest`)とパッケージングプロジェクトは作成済み。
CLIサブコマンド `capability-check` も実装済み(`src/Core/CapabilityCheck.h` / `.cpp`)。
ビルド未検証。

## Windows 総合判定

**保留(未実施 — Windows機なし)。** design.md §7のキーワード包含率しきい値に照らした
精度判定を含め、認識そのものに関わる全ての判定はWindows実機が無ければ行えない。
Issue #15〜#18のコードはすべて実装済みであり、Windows機があれば README.md の手順で
(ビルドが通ることが確認できればという条件付きで)即座に実行できる状態にある。

---

## ドキュメント調査で確定した事項

本スパイクの唯一の実質的な成果。すべて2026-09-20にlearn.microsoft.comをWebFetch/WebSearchで
確認した内容であり、URLを付す。

### 名前空間・型・シグネチャ

- **`Microsoft.Windows.AI` 名前空間**(クラス: `AICapabilities`, `AIFeatureReadyResult`。
  列挙型: `AICapabilityCategory`, `AIFeatureReadyResultState`, `AIFeatureReadyState`)
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai

- **`Microsoft.Windows.AI.Speech` 名前空間**(クラス: `AudioConfiguration`,
  `BatchRecognition`, `SpeechAudioProvider`, `SpeechRecognitionModel`,
  `SpeechRecognitionModelResult`, `StreamingRecognition`,
  `StreamingRecognizedEventArgs`, `StreamingRecognizingEventArgs`。
  構造体: `SpeechRecognitionModelProgress`。列挙型: `SpeechRecognitionModelProgressStatus`)
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech
  — **重要**: このページのmonikerは `windows-app-sdk-2.0-experimental` のみで、
  1.7 / 1.8 / 2.0(安定版)のいずれにも掲載されていない(下記「齟齬」参照)。

- **`SpeechRecognitionModel.GetReadyState()`**: static、戻り値 `AIFeatureReadyState`。
  ```cppwinrt
  static AIFeatureReadyState GetReadyState();
  ```
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel.getreadystate

- **`SpeechRecognitionModel.EnsureReadyAsync()`**: static、戻り値
  `IAsyncOperationWithProgress<AIFeatureReadyResult, SpeechRecognitionModelProgress>`。
  ```cppwinrt
  static IAsyncOperationWithProgress<AIFeatureReadyResult, SpeechRecognitionModelProgress> EnsureReadyAsync();
  ```
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel.ensurereadyasync

- **`SpeechRecognitionModel.TryCreateAsync()`**: static、戻り値
  `IAsyncOperationWithProgress<SpeechRecognitionModelResult, SpeechRecognitionModelProgress>`。
  ```cppwinrt
  static IAsyncOperationWithProgress<SpeechRecognitionModelResult, SpeechRecognitionModelProgress> TryCreateAsync();
  ```
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel.trycreateasync

- **`SpeechRecognitionModelResult`**: プロパティは `ExtendedError` / `SpeechModel` の2つのみ。
  公式サンプル(下記)は `speechModelResult.SpeechModel == null` を失敗判定に使う。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelresult

- **`BatchRecognition`**: コンストラクタは `BatchRecognition(SpeechRecognitionModel)` の1つのみ。
  メソッドは `Recognize(Byte[])` と `RecognizeFromFile(String)` の2つ(いずれもロケール引数なし)。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.batchrecognition

- **`BatchRecognition.RecognizeFromFile(String)`**: 戻り値 `IAsyncOperation<hstring>`。
  ```cppwinrt
  IAsyncOperation<winrt::hstring> RecognizeFromFile(winrt::hstring const& filePath);
  ```
  パスを表す文字列を直接渡す(StorageFileではない)。フォーマットに関する記載はページ内に無い。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.batchrecognition.recognizefromfile

- **`AudioConfiguration`**: メンバーは `ForProvider(SpeechAudioProvider)` /
  `FromAudioDevice(String)` / `FromFile(String)` / `FromStream(IInputStream)` の4つ。
  ロケール指定に関わるメンバーは無い。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.audioconfiguration

- **`AIFeatureReadyState`**(7値。値と説明も含めて確認済み):
  `Ready`(0)/`NotReady`(1)/`NotSupportedOnCurrentSystem`(2)/`DisabledByUser`(3)/
  `CapabilityMissing`(4、WinAppSDK 2.0以降)/`NotCompatibleWithSystemHardware`(5、
  WinAppSDK 2.0以降)/`OSUpdateNeeded`(6、WinAppSDK 2.0以降)。
  design.md §4.4/§5が言及する「EnsureNeeded」という値はこの列挙体には存在しない
  (下記「齟齬」参照)。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.aifeaturereadystate

- **`AIFeatureReadyResultState`**: `InProgress`(0)/`Success`(1)/`Failure`(2)。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.aifeaturereadyresultstate

- **`AIFeatureReadyResult`**: プロパティは `Error` / `ErrorDisplayText` / `ExtendedError` /
  `PackageInstallationFailed` / `Status` の5つ。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.aifeaturereadyresult

- **`SpeechRecognitionModelProgress`**: `{ double Progress; SpeechRecognitionModelProgressStatus Status; }`
  の2フィールド。`Progress`フィールドの型は`double`であることを個別ページで確認済み。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelprogress
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelprogress.progress

- **`SpeechRecognitionModelProgressStatus`**(5値): `Installing`(0)/`Caching`(1)/
  `Loading`(2)/`CompletedSuccess`(3)/`CompletedFailure`(4)。
  https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelprogressstatus

### ロケール指定APIの有無(design.md §8 未決事項2)

**確定: 存在しない。** `Microsoft.Windows.AI.Speech` 名前空間の全クラス・全メンバーを
上記の各APIリファレンスページで突き合わせた結果、ロケール・言語を指定する引数・プロパティ・
メソッドは1件も存在しないことを確認した。`SpeechRecognitionModel` は引数なしの静的メソッドのみ、
`BatchRecognition` のコンストラクタは `SpeechRecognitionModel` のみを取り、
`AudioConfiguration` は音声ソース(デバイス/ファイル/ストリーム/プロバイダ)を指定するのみで
言語は指定しない。

### 使用パターン(公式サンプルコード、C#)

https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition の
「Batch recognition from an audio file」節に掲載されているサンプル:

```csharp
using Microsoft.Windows.AI;
using Microsoft.Windows.AI.Speech;

if (SpeechRecognitionModel.GetReadyState() != AIFeatureReadyState.Ready)
{
    await SpeechRecognitionModel.EnsureReadyAsync();
}

var speechModelResult = await SpeechRecognitionModel.TryCreateAsync();
if (speechModelResult.SpeechModel == null)
{
    throw new InvalidOperationException(
        $"Failed to create SpeechRecognitionModel: {speechModelResult.ExtendedError}");
}

var speechModel = speechModelResult.SpeechModel;
var batchRecognition = new BatchRecognition(speechModel);
string transcription = await batchRecognition.RecognizeFromFile("path/to/audio.wav");
```

design.md §4.4が示すパイプライン(`TryCreateAsync()` → `RecognizeFromFile(path)` →
最終テキスト1件)と一致することを確認した。バッチ認識は最終テキストを1回返すのみで、
partial/volatile結果に相当するイベントは `StreamingRecognition` 側にのみ存在する
(`Recognized`イベント)ことも同ページで確認した。

### systemAIModels capability の宣言方法

https://learn.microsoft.com/en-us/windows/ai/apis/get-started (2026-09-20 WebFetch)
「Edit the Package.appxmanifest file」節より、XML例をそのまま引用(要約ではなく原文):

```xml
<Capabilities>
   <systemai:Capability Name="systemAIModels"/>
</Capabilities>
```

```xml
xmlns:systemai="http://schemas.microsoft.com/appx/manifest/systemai/windows10"
IgnorableNamespaces="uap rescap systemai"
```

```xml
<TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26226.0" />
```

さらにVisual Studioが `MaxVersionTested` を上書きしないようにするための設定
(vcxproj/wapproj側):

```xml
<AppxOSMinVersionReplaceManifestVersion>false</AppxOSMinVersionReplaceManifestVersion>
<AppxOSMaxVersionTestedReplaceManifestVersion>false</AppxOSMaxVersionTestedReplaceManifestVersion>
```

これらはrequirements.md §8 / design.md §4.4の記述と完全に一致する。

### CapabilityMissing の挙動

https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.aifeaturereadystate
(AIFeatureReadyState.CapabilityMissingのDescription、原文引用):

> This value is available starting with Windows App SDK 2.0. Model is not
> available to the current app due to a missing capability declaration.
> EnsureReadyAsync and CreateAsync will throw `winrt::hresult_access_denied`
> (add the systemAIModels capability to the app manifest).

ただしこの記述は `Microsoft.Windows.AI.Text.LanguageModel` の文脈での言及であり
(get-started.mdの `LanguageModel.EnsureReadyAsync`/`LanguageModel.CreateAsync` の例と
併記されている)、`Microsoft.Windows.AI.Speech.SpeechRecognitionModel` について同一の
挙動が明記されたページは見つからなかった。両者が同じ `AIFeatureReadyState` を共有する
以上、同様のパターンが適用される可能性が高いと考えられるが、Speech固有の明記が無い点は
「実機でのみ確認可能な事項」として扱う。

### 前提条件・プリインストール状況

https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition
「Prerequisites」節より:

- Windows version: Windows 11, version 24H2 (build 26100) or later
- WinAppSDK version: Version 1.7.1 or later
- Hardware: Copilot+ PC with an NPU, or any Windows PC meeting the recommended
  CPU specifications

「Supported hardware」節より、NPU(Copilot+ PC)はモデルプリインストール済み、
CPUのみは非プリインストール(初回 `EnsureReadyAsync()` でWindows Update経由の
バックグラウンドダウンロード)、GPUは非対応(❌ Not supported)。

推奨CPU仕様(「Recommended CPU specifications」節): 4コア以上、3GHz以上、L3キャッシュ32MB以上
(ハードミニマムではなく推奨値)。

### NFKC正規化・Unicode一般カテゴリ判定に使用したAPI

- Win32 `NormalizeString`(NORM_FORM列挙体、`NormalizationKC`=0x5)。
  https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-normalizestring
- Windows 10 version 1903 (build 18362) 以降にOS同梱される ICU の C API
  (`icu.dll`/`icu.lib`/`<icu.h>`、`u_charType()`/`u_tolower()`)。
  https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu-
  「A new combined DLL, icu.dll, was added ... A new import library was added to
  the Windows 10 SDK: icu.lib」を確認済み。

### C++/WinRT 非同期パターン

https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/concurrency
(2026-09-20 WebFetch)で、コンソールアプリにおけるブロッキング `get()` 呼び出しパターンと、
`Completed` デリゲートによるイベント購読パターンの両方が公式に推奨されていることを確認した。
一方、`wait_for()` のような時限ブロッキング専用の拡張メソッドの存在はこのページでは
確認できなかったため、本スパイクの `Support.h::WaitOrCancel` は `Completed` デリゲート +
`std::condition_variable` + `Cancel()` の組み合わせで独自にタイムアウト保護を実装した
(`wait_for()`は使用していない)。

---

## 実機でのみ確認可能な事項

design.md §8 未決事項1・2のうち、ドキュメント調査だけでは確定できなかった事項、および
ドキュメントに明記が無く実機での挙動確認が必要な事項。

### 未決事項1: `RecognizeFromFile` の対応入力フォーマット

**ドキュメント調査だけでは確定できなかった。** `BatchRecognition.RecognizeFromFile`
および周辺(`BatchRecognition`, `AudioConfiguration`, 名前空間全体, get-started系ページ)の
どのページにも、対応するコンテナ・コーデックの一覧や制約に関する記載が無い。
`AudioConfiguration.FromFile(String)` という別メソッドも存在するが(README/コード参照)、
これがStreamingRecognition専用なのか、BatchRecognition側でも使えるのかもドキュメント上
不明である。wav / m4a / mp3 が受理されるかは、本スパイクの `format-test` サブコマンドを
Windows実機で実行しない限り確定できない。

### 未決事項2: ロケール指定可否

**ドキュメント調査で確定できた(上記「ドキュメント調査で確定した事項」参照)**:
ロケール指定APIはドキュメント上存在しない。

ただし、以下は実機でしか確認できない:

- ロケール指定APIが無い場合、`SpeechRecognitionModel` が実際にどの言語で認識するのか
  (OS表示言語、既定入力言語、システムロケールのいずれかに連動するのか、あるいは
  多言語混在対応の単一モデルなのか)は、ドキュメントに記載が無く実機での確認が必要。
- 上記の帰結として、ja-JPの音声が実際に高精度で認識されるかどうか(design.md §4.4の
  「言語指定APIの有無をM0で確認 ... 指定不能ならOS言語依存としてREADME明記、ja-JP検証が
  最優先」という要求のうち、後段の「ja-JP検証」自体はドキュメント調査だけでは満たせない)。

### その他、実機でのみ確認可能な事項

- Issue #15: `EnsureReadyAsync()` の `Progress` コールバックの実際の発火頻度・粒度
  (tasks.md「進捗の粒度」)。ドキュメントは型定義のみを示し、発火頻度についての記載は無い。
- Issue #18: `systemAIModels` capability宣言の有無による実際の挙動差(`SpeechRecognitionModel`
  について、`CapabilityMissing`状態が実際に返るか、`hresult_access_denied`が実際に送出されるか)。
- `SpeechRecognitionModelResult.ExtendedError` / `AIFeatureReadyResult.ExtendedError` /
  `AIFeatureReadyResult.Error` の正確な型(本スパイクは `winrt::hresult` 型を前提に実装したが
  未検証)。
- `WinAppSDK 1.7.1` 環境で `Microsoft.Windows.AI.Speech` 名前空間のAPI群が実際に利用できるか
  (下記「齟齬」参照。APIリファレンスページ自体が2.0-experimentalモニカーでしか存在しない)。
- MSIXパッケージのビルド・署名・サイドロードの具体的手順、および本スパイクが作成した
  `.vcxproj`/`.wapproj`が実際にビルドを通るか。

## 実行環境の制約

- **本タスクはmacOS上で実施されており、Windows機は一切存在しない。** そのため上記の
  すべての「(未実施)」項目は、実測してもいないのに数値を作文する(捏造する)ことを
  避けるために意図的に空欄化している。
- ビルド・実行のいずれも行っていないため、`WindowsSTTSpikeCli.vcxproj` /
  `WindowsSTTSpikePackage.wapproj` がそのままビルドを通るという保証は無い。README
  「ビルド方法」「要確認事項の一覧」に記載した不確実性を解消したうえで実行する必要がある。
- **Windows機があれば、README.mdの「ビルド手順」「各サブコマンドの実行方法」に記載した
  手順で即座に実行できる状態にある。** コードは Issue #15〜#18 のすべてについて実装済みであり、
  実行して得られる結果を本ファイルの該当欄(`(未実施 — Windows機なし)` の各行)にそのまま
  転記できる形式(表構造・JSON出力)まで整えてある。
- mp3フィクスチャ生成(`scripts/generate_mp3.sh`)のみは、Windows非依存の処理(ffmpegによる
  wav→mp3変換)であるため実際に実行し、`fixtures/mp3/` に成果物が存在する。

## design.md / requirements.md との齟齬

1. **WinAppSDKのバージョンとチャンネルの不整合。** requirements.md NFR-4 / §8および
   design.md §4.4はいずれも「WinAppSDK 1.7.1以上」と記載しているが、本スパイクが
   WebFetchで確認した限り、`Microsoft.Windows.AI.Speech` 名前空間・
   `SpeechRecognitionModel`・`BatchRecognition`等の個別APIリファレンスページは
   いずれも `windows-app-sdk-2.0-experimental` というモニカーでのみ存在し、
   1.7 / 1.8 / 2.0(安定版)のいずれのモニカーにも掲載されていなかった
   (`Microsoft.Windows.AI` 名前空間直下の `AIFeatureReadyState` 等、より基盤的な
   型は1.7/1.8/2.0(安定版)を含む全モニカーに掲載されている点との対比が明確である)。
   これは、Speech Recognition APIが2026-09-20時点でまだExperimentalチャンネル限定の
   機能である可能性を示唆する。requirements.md/design.mdの「1.7.1以上」という記述を
   そのまま実装に採用すると、該当バージョンではAPI自体が存在せずビルドできない
   可能性がある。M4実装着手前に、実際にNuGetパッケージマネージャーで
   `Microsoft.WindowsAppSDK` の各バージョン(1.7.1系、1.8系、2.0安定版、
   2.0-experimental系)を確認し、Speech Recognition APIが実際にどのバージョンから
   利用できるかを実機で確定させることを推奨する。

2. **design.md §4.4/§5の「EnsureNeeded」という状態名がAPIに存在しない。**
   design.md §4.4は「モデル管理: `GetReadyState()` → FR-1」、§5エラーマッピング表は
   「ModelUnavailable ← NotReady / EnsureNeeded で未同意」と記載しているが、
   本スパイクが確認した `AIFeatureReadyState` 列挙体の実際のフィールドは
   `Ready`/`NotReady`/`NotSupportedOnCurrentSystem`/`DisabledByUser`/
   `CapabilityMissing`/`NotCompatibleWithSystemHardware`/`OSUpdateNeeded` の7つで
   あり、「EnsureNeeded」という名前の値は存在しない。get-started.mdの説明文中に
   「NotReady or EnsureNeeded」という言い回しが登場するが、これは非公式な
   言い換え(「EnsureReadyAsyncの呼び出しが必要な状態」程度の意味の説明的表現)であり、
   実際のAPI値ではないと判断した。design.mdの記述はこの説明文をそのまま列挙値と
   誤認した可能性がある。design.md §4.4/§5の該当箇所を「NotReady」単独、または
   「NotReady(EnsureReadyAsyncの呼び出しが必要な状態)」のような表現に修正することを
   提案する。

3. **design.mdはFR-1の4値(available/downloadable/downloading/unavailable)への写像を
   前提としているが、`AIFeatureReadyState`(7値)には「downloading」に一意に対応する
   値が存在しない。** `NotReady`はダウンロード開始「前」の状態であり、ダウンロード
   「中」であることを知るには、`EnsureReadyAsync()`実行中に
   `SpeechRecognitionModelProgress.Status`(`Installing`/`Caching`/`Loading`等)を
   観測する必要がある。すなわち「downloading」はAPIの状態照会(`GetReadyState`)からは
   得られず、能動的にダウンロードを開始した後の進捗イベントからしか得られない。
   design.md §4.4にこの非対称性の記載が無いため、M4実装時の注意点として追記することを
   提案する(本スパイクでは `src/Core/ModelReadiness.h` のコメントに記録した)。

4. **design.md §4.4は`AIFeatureReadyState`を4値相当として扱っているように読めるが、
   実際は7値であり、うち3値(`CapabilityMissing`/`NotCompatibleWithSystemHardware`/
   `OSUpdateNeeded`)はWinAppSDK 2.0以降でのみ利用可能と明記されている。** 上記1の
   バージョン不整合と合わせて、design.mdが前提とするWinAppSDK 1.7.1上でこれらの値が
   実際にどう扱われるか(単に返らない、別の値に丸められる等)は未確認である。

5. **`BatchRecognition.Recognize(Byte[])` というオーバーロードの存在は
   design.mdに記載が無い。** `RecognizeFromFile(String)`とは別に、生バイト列を
   直接渡すメソッドが存在することを確認した。design.md §4.4のパイプライン
   (「(必要時) Media Foundation で wav へ変換」→「RecognizeFromFile(path)」)は
   常にファイルパス経由を前提としているが、Media Foundationでのフォーマット変換結果を
   一時ファイル化せず`Recognize(Byte[])`へ直接渡す経路も選択肢になりうる
   (バイト列の期待フォーマットは未確認。「実機でのみ確認可能な事項」参照)。

## フォローアップ(反映先。本ファイル自体の役目ではなく、呼び出し元が別途実施)

- `tasks.md` M0 Windows の該当4項目は、Windows実機入手後に本READMEの手順を実行するまで
  すべて未着手のまま据え置くべきである(本スパイクはコード実装のみを完了させた)。
- `requirements.md` §4 FR-1 / FR-5対応表のWindows列は、本ファイルの「実機でのみ確認可能な
  事項」がすべて解消された後に更新すること。
- `design.md` §8 未決事項1・2は、未決事項2(ロケール指定可否)のみ「APIとして存在しない」
  ことをドキュメント調査で確定できたため、design.md本体への反映を検討すること。未決事項1
  (対応フォーマット)は実機確認まで未確定のまま据え置くこと。
- `design.md` §4.4/§5の「EnsureNeeded」表記、および「downloading」状態の扱いについて、
  上記「齟齬」2・3の是正を検討すること。
