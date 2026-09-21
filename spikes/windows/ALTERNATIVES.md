# ALTERNATIVES.md — Windows バックエンドの代替案調査

対応: `spikes/windows/RESULTS.md`（M0 ドキュメント調査）、requirements.md §3・§4（FR-3/FR-4/FR-5）・
§5（NFR-2/NFR-3/NFR-4）、docs/FUTURE_EXTENSIONS.md。

## この文書の位置づけと出典の区別

`Microsoft.Windows.AI.Speech` が stable チャンネルに存在しないことが Windows 11 実機で確定したため、
**stable チャンネルだけで FR/NFR を満たす代替バックエンドが存在するか**を調べた記録である。
実装は一切行っていない。Windows 機上で何かを実行した結果もここには含まれない
（実機で確定した事項は下記「実機で確定している前提」の3点のみであり、それは呼び出し元の測定である）。

本文中の主張は次の3つに分けて書く。**推測で埋めない。**

- **[確定]** — learn.microsoft.com / microsoft.com のドキュメント、または本リポジトリの実測に基づく。URLを付す。
- **[推定]** — ドキュメントから論理的に導けるが、そのものずばりの記述は見つからなかったもの。
- **[不明]** — 調べても確定できなかったもの。実機検証が必要。

---

## 1. 問題

### 1.1 実機で確定している前提（呼び出し元による Windows 11 実機測定、10.0.26200 / 25H2）

1. `winapp init --setup-sdks stable`（WinAppSDK **2.5.1 stable**）が生成する projection ヘッダに
   `Microsoft.Windows.AI.Speech.h` は**含まれない**。含まれるのは
   `Microsoft.Windows.AI.{ContentSafety,Foundation,Imaging,MachineLearning,Text,Video}.h` のみ。
2. `winapp init --setup-sdks experimental`（WindowsAppSDK.AI **2.4.8-experimental**）には
   `Microsoft.Windows.AI.Speech.h` が含まれ、本プラグインの WinRT 実装はこれに対してクリーンにコンパイルできる。
3. ホストは Windows 11 build 10.0.26200（25H2）であり、NFR-4 の下限（24H2 / 26100）は満たしている。

### 1.2 ドキュメント側の記述と実機の齟齬

- **[確定]** Speech Recognition の公式ドキュメントは Prerequisites に
  「**WinAppSDK version:** Version 1.7.1 or later」と書いている。
  https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition
- **[確定]** Windows AI APIs のインデックスページも、機能とリリースの対応表で
  「[**Version 1.7.1 (1.7.250401001)**] - All other APIs」とだけ書いており、Speech Recognition を
  experimental 扱いしていない。同ページのハードウェア対応表にも Speech Recognition の行がある。
  https://learn.microsoft.com/en-us/windows/ai/apis/
- **[確定]** 一方、WinAppSDK 2.0 系のリリースノートで `Microsoft.Windows.AI.Speech` が現れるのは
  **experimental チャンネルのみ**である。`2.2 Experimental 9 (2.2.2-Experimental9)` の
  「Speech Recognition APIs [Experimental]」が初出で、`2.3 Experimental A (2.3.2-ExperimentalA)` の
  新規API一覧に `Microsoft.Windows.AI.Speech` 名前空間の全型が列挙されている。
  stable チャンネル（2.0〜2.5.1）のリリースノートには Speech の記載が一切ない。
  https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-2-0?pivots=experimental
  https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-2-0?pivots=stable
- **[確定]** APIリファレンスページのモニカーが `windows-app-sdk-2.0-experimental` のみであることは
  M0 スパイクで既に確認済み（spikes/windows/RESULTS.md「齟齬」1）。

すなわち **実機の観測が正しく、`speech-recognition.md` の「1.7.1 or later」という記述が誤っている**。
M0 スパイクが「1.7.1という記述が正しかった」と判定した箇所（requirements.md NFR-4 の注記）は失効している。

### 1.3 本調査が満たすべき制約（交渉の余地がないもの）

| ID | 内容 | 本調査での意味 |
|---|---|---|
| FR-3 | 録音済み音声**ファイル**の文字起こし（マイク入力ではない） | ファイルまたはアプリ供給ストリームを入力にできること |
| FR-4 | デコードはOS純正デコーダのみ | FFmpeg等の同梱不可。Media Foundation は可 |
| NFR-2 | 完全オフライン。音声もテキストも端末外に出さない | クラウドASR・オンライン文法は即不採用 |
| NFR-3 | 認識モデル・推論エンジンを同梱しない | モデルファイルをアプリが配布する方式は即不採用 |
| NFR-4 | Windows 11 24H2 (build 26100) 以上 | — |
| FR-5 | ja-JP が動作すること | 認識エンジン（TTS音声ではない）の日本語対応が必要 |

加えて、本調査の発端である制約として **experimental チャンネルへの依存は不可**（プロジェクトオーナーの判断）。

---

## 2. 候補一覧（制約適合マトリクス）

| # | 候補 | チャンネル/供給元 | FR-3 ファイル入力 | NFR-2 オフライン | NFR-3 モデル非同梱 | ja-JP | 総合 |
|---|---|---|---|---|---|---|---|
| 1 | `Windows.Media.SpeechRecognition`（UWP/WinRT） | Windows SDK（stable） | ✗ 手段なし | ✗ 既定文法はオンライン | ○ | △ | **不成立** |
| 2 | **SAPI 5（COM, `ISpRecognizer` + `ISpStream`）** | Windows 同梱（非推奨扱い） | ○ `BindToFile` | ○ [推定] | ○ FOD | ○ FOD 存在 | **唯一の候補** |
| 3 | `System.Speech.Recognition` (.NET) | NuGet / .NET | ○ `SetInputToWaveFile` | ○（#2と同一エンジン） | ○ | ○（#2と同じ） | 実質#2。C++から到達困難 |
| 4 | `Microsoft.Windows.AI.MachineLearning`（Windows ML） | WinAppSDK 2.x stable | ○ | ○ | **✗ アプリがモデルを供給** | — | **不成立** |
| 5 | Azure Speech SDK（クラウド） | Azure | ○ | **✗** | ○ | ○ | **不成立** |
| 5b | Azure Embedded Speech（オフライン） | Azure（限定アクセス） | ○ | ○ | **✗ モデルをアプリが配布** | ○ | **不成立** |
| 6 | Live Captions / Voice Access | Windows 同梱 | — | ○ | ○ | Live Captions は○ | **公開APIなし** |
| 7 | WebView2 + Edge オンデバイス Web Speech | Edge Canary/Dev + フラグ | ○ | ○ | ○ | **✗ 未対応（6言語のみ）** | 将来候補 |
| 8 | `Microsoft.Windows.AI.Speech`（現行実装） | WinAppSDK experimental | ○ | ○ | ○ | [不明] | オーナー判断により除外 |

---

## 3. 候補ごとの評価

### 3.1 `Windows.Media.SpeechRecognition`（UWP/WinRT、Windows SDK同梱）

**結論: ファイル入力の手段は存在しない。加えて既定の口述文法はオンラインであり NFR-2 にも反する。不成立。**

- **[確定]** `SpeechRecognizer` クラスの全メンバーを API リファレンスで確認した。メソッドは
  `Close` / `CompileConstraintsAsync` / `Dispose` / `RecognizeAsync` / `RecognizeWithUIAsync` /
  `StopRecognitionAsync` / `TrySetSystemSpeechLanguageAsync` の7つ、プロパティは
  `Constraints` / `ContinuousRecognitionSession` / `CurrentLanguage` / `State` /
  `SupportedGrammarLanguages` / `SupportedTopicLanguages` / `SystemSpeechLanguage` /
  `Timeouts` / `UIOptions` の9つ。**音声ソースを指定する引数・プロパティ・メソッドは1件もない。**
  `StateChanged` イベントの説明が「during audio capture」となっているとおり、入力は既定の音声入力デバイスである。
  https://learn.microsoft.com/en-us/uwp/api/windows.media.speechrecognition.speechrecognizer
  同名前空間に `AudioConfiguration` 相当の型も存在しない。
- **[確定]** 既定の口述（dictation）文法・Web検索文法は**オンライン**である。公式ドキュメントは
  「When you use these grammars, **a remote web service performs the recognition** and returns the
  results to the device.」「These predefined grammars ... **require a network connection**.」
  「If you also want to support dictation ... confirm that **Online speech recognition**
  (Settings > Privacy > Speech) is enabled.」と明記する。
  https://learn.microsoft.com/en-us/windows/apps/develop/input/speech-recognition
  オフラインで使えるのはリスト文法（`SpeechRecognitionListConstraint`）と SRGS 文法だけであり、
  これらは「アプリが語彙を列挙する」方式であって、任意の録音の書き起こしには使えない。
- **[確定]** MSIX パッケージID が必須（「Speech recognition requires MSIX package identity.
  ... Unpackaged apps cannot use these APIs.」同上）。
- 補足: Windows AI の Speech Recognition ドキュメントは `NotSupportedOnCurrentSystem` のときの
  フォールバック先としてこの UWP API を挙げているが、上記のとおり**本ライブラリの用途（ファイル入力・
  オフライン）にはフォールバックにならない**。

### 3.2 SAPI 5（COM: `ISpRecognizer` / `ISpStream` / `SpBindToFile`）

**結論: 制約をすべて満たしうる唯一の候補。ただし Windows Speech Recognition は2023年12月に
非推奨（deprecated）と公表されており、ドキュメントは archived 扱いである。**

#### 3.2.1 ファイル入力は公式に存在する

- **[確定]** 「Using WAV File Input with SR Engines (SAPI 5.4)」に手順と C++ サンプルが載っている。
  手順は (1) `CLSID_SpStream` を CoCreateInstance → `ISpStream::BindToFile(...SPFM_OPEN_READONLY...)`、
  (2) `CLSID_SpInprocRecognizer` で **InProc** の `ISpRecognizer` を生成、
  (3) `ISpRecognizer::SetInput(stream, TRUE)`、(4) `CreateGrammar` → `LoadDictation(NULL, SPLO_STATIC)`
  → `SetDictationState(SPRS_ACTIVE)`、(5) `SPEI_RECOGNITION` / `SPEI_SR_END_STREAM` を受け取る、というもの。
  同ページは想定ユースケースとして明示的に
  「**Offline transcription applications** (e.g., convert voice mail to email)」を挙げている。
  https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ee431813(v=vs.85)
- **[確定]** 同ページは「SAPI will negotiate mismatched engine/input audio formats using
  **system audio codecs**」とも書いており、フォーマット変換をOS側のコーデックに委ねられる
  （FR-4 と矛盾しない）。ただし `ISpStream::BindToFile` が受けるのは WAV（RIFF）であり、
  m4a / mp3 は **Media Foundation で PCM WAV へデコードしてから渡す**必要がある [推定]。
  これは design.md §4.4 が `RecognizeFromFile` 用に想定していた変換経路と同じである。
- **[確定]** FR-3 が求める「partial 結果 + 最終結果」のうち、SAPI が返すのは確定イベント
  （`SPEI_RECOGNITION`）である。仮説イベント `SPEI_HYPOTHESIS` も列挙体に存在するが、
  ファイル入力時の発火挙動は **[不明]**。なお1本のストリームから複数回 `SPEI_RECOGNITION` が
  発生しうることは明記されている（「Transcription applications can potentially record multiple
  recognitions on a single audio stream」同上）。したがって「複数セグメントを逐次 emit し、
  `SPEI_SR_END_STREAM` で完了」という形が自然であり、FR-3 の Stream 契約には素直に載る [推定]。
- **[確定]** `SPEI_SR_END_STREAM` によりファイル終端を検知できる。Android / Web で問題になった
  「終了が検出できない」「確定結果が返らない」という構図（requirements.md FR-3）とは異なり、
  終端の検知手段が API に明示されている。

#### 3.2.2 ja-JP の認識エンジンは存在する（TTS音声とは別物）

ここが本調査の要点である。SAPI の TTS 音声（ja-JP_Haruka 等）と、**音声認識エンジン**は別の FOD である。

- **[確定]** 言語 Features on Demand には Text-to-speech とは独立に
  「**Speech recognition** — Recognizes voice input, used by Cortana and Windows Speech Recognition.
  Sample package name: `Microsoft-Windows-LanguageFeatures-Speech-fr-fr-Package~...cab`
  Sample capability name: `Language.Speech~~~fr-FR~0.0.1.0`」という区分が存在する。
  依存関係は「The basic and text-to-speech components of the same language」。
  https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-language-fod
- **[確定]** 同ページからリンクされている LP-to-FOD 対応表（Microsoft の配布ファイル）を実際に
  ダウンロードして機械的に集計したところ、`FOD Area = Speech` を持つ cab のソース言語は
  **de-de / en-gb / en-us / es-es / es-mx / fr-ca / fr-fr / it-it / ja-jp / pt-br / zh-cn / zh-tw の12言語**
  であり、その中に **`Microsoft-Windows-LanguageFeatures-Speech-ja-jp-Package.cab`（Installed LPs）** が
  存在する。
  https://download.microsoft.com/download/7/6/0/7600F9DC-C296-4CF8-B92A-2D85BAFBD5D2/Windows-10-1809-FOD-to-LP-Mapping-Table.xlsx
  **注意**: このファイル名は Windows 10 1809 である。Windows 11 の FOD ドキュメントが現在も
  「List of all language-related Features on Demand」としてこれを参照しているが、
  **Windows 11 24H2 時点で ja-JP の Speech FOD が同じ形で存在し続けているかは実機で確認するまで [不明]** である。
- **[確定]** 言語機能のビットマップに Speech が独立した値として現在も定義されている
  （`Basic Typing = 0x1 / Fonts = 0x2 / Handwriting = 0x4 / **Speech = 0x8** / TextToSpeech = 0x10 /
  OCR = 0x20 / ...`）。ja-JP を例に挙げた照会コマンドも掲載されている。
  https://learn.microsoft.com/en-us/windows/client-management/mdm/language-pack-management-csp
- **[確定]** Windows 11 では標準ユーザーでも設定アプリから言語機能を取得できる
  （「Starting in Windows 11, standard users can acquire Language Feature-on-Demand packages from
  Time & Language page in the Settings app.」FOD ページ）。PowerShell からは
  `Install-Language ja-JP`（例がドキュメントに掲載されている。`-ExcludeFeatures` を付けなければ
  関連する FOD も入る）で導入できる。
  https://learn.microsoft.com/en-us/powershell/module/languagepackmanagement/install-language
  ただし**アプリ内から非対話で導入をトリガーできるか**（FR-2 `downloadModel` に相当）は **[不明]**。
  設定アプリへのディープリンク誘導に退化する可能性が高い [推定]。

#### 3.2.3 オフライン性

- **[推定]** InProc の `ISpRecognizer` は端末内のエンジン（FOD で導入されたもの）をプロセス内で駆動する
  方式であり、ネットワークを使うという記述はどの SAPI ドキュメントにも無い。3.1 の UWP 側が
  「remote web service」と明記しているのと対照的である。ただし**「送信しない」と明記した一次資料は
  見つからなかった**ため [推定] とする。NFR-2 は本プロダクトの存在理由であるから、
  採用を決めるなら実機でネットワークキャプチャを取って確かめるべきである。

#### 3.2.4 非推奨であること（最大のリスク）

- **[確定]** Windows のクライアント非推奨機能一覧に、2023年12月付で次の記載がある（原文引用）:
  > Windows speech recognition is deprecated and is no longer being developed. This feature is being
  > replaced with voice access. Voice access is available for Windows 11, version 22H2, or later devices.
  > Currently, voice access supports five English locales: English - US, English - UK, English - India,
  > English - New Zealand, English - Canada, and English - Australia.

  https://learn.microsoft.com/en-us/windows/whats-new/deprecated-features
- **[確定]** 同ページ冒頭の定義により、deprecated は「もう積極的に開発されていない。将来のアップデートで
  削除されうる」という意味であって、**現時点で削除されたという意味ではない**
  （削除済みのものは removed-features 側に載る。WSR は removed 側には載っていない）。
- **[確定]** SAPI 5.3 / 5.4 の API ドキュメントは learn.microsoft.com の `previous-versions` 配下にあり、
  メタデータが `is_archived: true` / `ms.topic: archived`、最終更新が 2012年である。
  https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms720151(v=vs.85)
- **[不明]** 「WSR（UI機能）の非推奨」と「SAPI ランタイム + Speech FOD エンジンの存続」が
  どこまで連動するか。非推奨エントリが指しているのは UI 機能（設定ウィザード、`Win+Ctrl+S`）であり、
  `sapi.dll` と認識エンジンの提供停止については何も述べていない。**Windows 11 24H2 で
  `CLSID_SpInprocRecognizer` が生成でき、ja-JP のレコグナイザートークンが列挙できるかは実機でしか
  確認できない。**

#### 3.2.5 精度について

- **[不明]** SAPI の日本語エンジン（いわゆる Microsoft Speech Recognizer 8.0 系）の書き起こし精度は
  一次資料に数値がない。設計年代から見て Windows AI の NPU モデルや SpeechAnalyzer より劣る可能性は
  高いが、**推測であり根拠を持たない**。design.md §7 のしきい値に照らした判定は実測が必須である。
  なお他の3プラットフォームも同一基準音声で 66.7% にとどまっており（requirements.md §3）、
  「SAPI だから不合格」と決め打ちできる状態ではない。

#### 3.2.6 Flutter プラグインからの到達性

- **[確定]** SAPI は COM であり、C++/WinRT ではなく素の COM（`sapi.h` / `sphelper.h`）で使う。
  Flutter Windows プラグインは C++ のため、追加ランタイムなしで直接呼べる [推定]。
  MSIX パッケージ化も `systemAIModels` capability も不要になる（requirements.md §8 の
  Windows 向け利用者制約が大きく軽くなる）という副次的な利点がある [推定]。

### 3.3 `System.Speech.Recognition.SpeechRecognitionEngine`（.NET）

**結論: ファイル入力は確かにあるが、実体は SAPI のマネージドラッパーであり、
C++ プラグインからは到達困難。3.2 に対する追加の利点がない。**

- **[確定]** `SetInputToWaveFile(string path)` が存在し、`DictationGrammar` を読み込んで
  `RecognizeAsync()` する公式サンプルが掲載されている。`SetInputToAudioStream` /
  `SetInputToWaveStream` もある。アセンブリは `System.Speech.dll`、現在は NuGet パッケージ
  `System.Speech`（ドキュメント上のバージョンは v11.0.0-rc.1）として .NET 側で維持されている。
  https://learn.microsoft.com/en-us/dotnet/api/system.speech.recognition.speechrecognitionengine.setinputtowavefile
- **[推定]** `System.Speech` は SAPI 上の薄いラッパーであり、使う認識エンジンは 3.2 と同一
  （したがって言語可用性の問題も同一）である。ドキュメントに「SAPI のラッパーである」という
  明示的な一文は見つけられなかったため [推定] とする。
- **[確定]** Windows 専用かつ .NET 専用である。Flutter Windows プラグインは C++ で書かれるため、
  これを使うには CLR をホストするか、別プロセスの .NET ヘルパーを同梱して IPC する必要がある。
  前者は配布・起動コスト、後者は「ブリッジコードのみ」という §6 のパッケージ方針に反する。
  **同じエンジンに、より重い経路で到達するだけ**なので採らない。

### 3.4 `Microsoft.Windows.AI.MachineLearning`（Windows ML）

**結論: アプリがモデルを用意する前提の API であり、NFR-3 に正面から反する。不成立。**

- **[確定]** Windows ML は ONNX Runtime の Windows 版であり、提供するのは**ランタイムと実行プロバイダー**である。
  モデルについては「**Use models you already have** — bring models from PyTorch, TensorFlow,
  scikit-learn, Hugging Face, and more.」、配布については
  「**Distribute models for Windows ML** - Choose between **including a model in your app package** or
  **downloading it separately**」と明記されている。
  https://learn.microsoft.com/en-us/windows/ai/new-windows-ml/overview
- **[確定]** Microsoft が Windows ML 経由で音声認識モデルを提供しているという記載はない。
  組み込みモデルによる機能は Windows AI APIs 側（=候補8）の担当であり、Windows ML は
  「Custom models - Direct Windows ML API access for advanced scenarios」と位置づけられている（同上）。
- したがって Windows ML を使うことは「whisper.cpp / sherpa-onnx と同じことを ONNX Runtime でやる」という
  意味になり、**本ライブラリの差別化点（NFR-3、README の比較表、docs/FUTURE_EXTENSIONS.md）を
  自ら捨てることになる。** 候補として検討しない。

### 3.5 Azure Speech SDK / クラウド一般

**結論: NFR-2 に反する。不成立。** 音声を端末外に出す時点で本プロダクトの存在理由が消える。

参考として、Azure には**オフライン**版（Embedded Speech）が存在するが、これも不成立である。

- **[確定]** 「Microsoft **limits access** to embedded speech. You can apply for access through the ...
  embedded speech **limited access review**.」
- **[確定]** 「For embedded speech, **you need to download the speech recognition models** ... Instead of a
  cloud resource, **you use the models and voices that you download to your local device**.」
  設定は `EmbeddedSpeechConfig.FromPaths(...)` でモデルの**ローカルパス**を指定し、
  `SetSpeechRecognitionModel(name, EMBEDDED_SPEECH_MODEL_LICENSE)` でライセンスキーを渡す。
  ja-JP モデルは提供言語一覧に含まれる。
  https://learn.microsoft.com/en-us/azure/ai-services/speech-service/embedded-speech
- すなわち**モデルの取得・配布・ライセンス管理がアプリ（＝本ライブラリの利用者）の責務になる**。
  NFR-3 に反し、かつ限定アクセス審査という配布上の障害もある。不成立。

### 3.6 Live Captions / Voice Access（Windows 11 組み込みの文字起こし）

**結論: 公開APIは見つからなかった。不成立。**

- **[確定]** Live Captions は完全にオンデバイスであり、日本語を含む言語をサポートし、
  初回に言語ファイルのダウンロードを求める。
  「All processing of audio and generation of captions from detected voice data occurs on-device.
  Audio, voice data, and captions never leave your device and are not shared to the cloud or with Microsoft.」
  「live captions will ask for your consent to process voice data on your device and prompt you to
  download language files to be used by on-device speech recognition.」
  https://support.microsoft.com/en-us/windows/use-live-captions-to-better-understand-audio-b52da59c-14b8-4031-aeeb-f6a47e6055df
  **つまり Windows 11 は日本語のオンデバイス認識モデルを実際に持っている。**
  しかしこのページにも Windows SDK にも、**開発者向けAPIの記載は無い**。
- **[確定]** Voice Access は現状5〜6の英語ロケールのみ（前掲 deprecated-features の引用）。
  そもそも「PCを音声で操作する」機能であって文字起こしAPIではない。
- **[確定]** Windows AI APIs のインデックスは「Planned features」として
  「**Live Translation (Not yet supported)**」を挙げているのみで、Live Captions の API 化には触れていない。
  https://learn.microsoft.com/en-us/windows/ai/apis/
- UI Automation で Live Captions のウィンドウからテキストを吸い出す非公式手法がコミュニティに存在するが、
  公開APIではなく、ライブラリの土台にはできない。**[不明]**: 将来 API 化される予定があるかどうか
  （公開されたコミットメントは見つからなかった）。

### 3.7 WebView2 + Edge のオンデバイス Web Speech（新規に発見した候補）

**結論: 今は使えない（ja-JP 未対応・Canary/Dev のフラグ付き機能）。ただし将来の有力候補であり、
既存の Web 実装を再利用できるという点で他と性質が違う。**

- **[確定]** Microsoft Edge は Web Speech API の `SpeechRecognition` にオンデバイスモデルを実装しており、
  `processLocally = true`、`SpeechRecognition.available({langs, processLocally})`、`install()` という、
  **本リポジトリの Web 実装が Chrome 向けに使っているのと完全に同じ API 形状**である。
  ファイル入力も `AudioContext` → `MediaStreamDestinationNode` → `recognition.start(track)` という
  同じ手順が公式サンプルとして載っている。
  https://learn.microsoft.com/en-us/microsoft-edge/web-platform/speech-recognition-api
- **[確定]** しかし現時点の制約が厳しい:
  - 「The local speech recognition model is available in **Microsoft Edge Canary or Dev
    (version 150.0.4076 or later)**」であり、さらに `edge://flags` の
    「Speech Recognition with on-device model」を **Enabled** にする必要がある。
  - 対応言語は「en-US / de-DE / it-IT / pt-PT / es-ES / ko-KR」の**6言語のみ**で、
    **ja-JP は含まれない**（「Language support is expected to expand in future versions.」とある）。
- **[確定]** プライバシーについては「The speech input into the model **never leaves the device**」と明記。
- **[不明]** WebView2 ランタイムでこの機能が使えるか（WebView2 は Edge stable 系であり、
  Canary/Dev 限定・フラグ必須の機能が使えるとは考えにくい [推定]。フラグを
  `AdditionalBrowserArguments` で渡せるかも未確認）。
- **[不明]** ja-JP 対応がいつ入るか。公開されたコミットメントは見つからなかった。
- 評価: **これは候補8（WinAppSDK experimental）と同型の問題**である。「stable では使えない機能」という点で
  同じであり、しかも ja-JP がまだ無い分だけ候補8より遠い。ただし、いずれ ja-JP が stable Edge に来れば、
  **Windows 実装を `_web` パッケージの JS とほぼ共有できる**という大きな利点がある。追跡する価値はある。

### 3.8 `Microsoft.Windows.AI.Speech`（現行実装・experimental）

オーナー判断により除外されているが、「出荷アプリで使えるのか」という問いには独立に答えておく（§5）。

---

## 4. `Microsoft.Windows.AI.Speech` が stable に来る時期

**結論: 公開されたコミットメントは存在しない。時期は [不明] であり、推測しない。**

- **[確定]** リリースチャンネル表における experimental の定義は
  「Early-stage features under active development. **APIs may change, be removed, or never ship.**
  Intended for exploration and feedback only.」、リリース頻度は「Published as needed」。
  https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels
- **[確定]** 同表の最新版は Stable **2.5.1**（2026-09-16）、Preview **2.0 Preview2**（2026-03-31）、
  Experimental **2.4.1-experimental**（2026-08-25）。Speech は 2.2.2-experimental9（2026年6月頃）で
  導入されてから、**preview チャンネルにも stable チャンネルにも一度も現れていない**（§1.2 参照）。
- **[確定]** experimental のリリースノートに、stable/preview への移行時期を述べた記述は無い。
- **[確定]** microsoft/WindowsAppSDK リポジトリを検索した範囲（`Microsoft.Windows.AI.Speech` を含む
  issue は1件のみ）では、stable 化のロードマップを述べた issue / discussion は見つからなかった。
  唯一の該当 issue は不具合報告である:
  「Microsoft.Windows.AI.Speech speech recognition API crashes with 0xC000001D: Illegal Instruction」
  （2.2.2-experimental9、`asrmodelapi.dll` が Illegal Instruction でクラッシュ、
  `GetReadyState()` は成功してしまう）。**2026-09-21 時点で open のまま**であり、
  Microsoft からの回答も付いていない。
  https://github.com/microsoft/WindowsAppSDK/issues/6561
- したがって「いつ stable になるか」は答えられない。**「未定である」ことが答えである。**
  加えて上記 issue は、experimental 段階の Speech API が
  **非対応CPU上で事前検出できずプロセスごと落ちる**状態であることを示している。
  これは仮に experimental を採用した場合の品質リスクとして重い。

---

## 5. experimental チャンネルを出荷アプリで使えるか（オーナー判断とは独立に）

**結論: Microsoft は experimental を「サポート対象外」と明示している。出荷してはならないという
明文の禁止規定は見つからなかったが、サポートも API の存続保証も無い。**

- **[確定]** リリースチャンネル表の「Supported?」列は Stable のみ **Yes**、Preview と Experimental は
  いずれも **No**。説明文は「Intended for exploration and feedback only.」。
  Stable の説明は「**Production-ready channel intended for apps in market.** Includes only stable,
  supported APIs suitable for long-term use.」。
  https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels
- **[確定]** サポートポリシーは「Support is **conditional on using the latest Windows App SDK patch
  update** and a supported operating system.」であり、サービス対象として列挙されているのは
  2.0 / 1.8 / 1.7 … という**安定版の系列のみ**。experimental は寿命表にすら載っていない。
  また「Your use of **out-of-support** Windows App SDK versions may put your applications at risk.」
  とある（同上）。
- **[不明]** Microsoft Store の提出ポリシーが experimental WinAppSDK を明示的に拒否するかどうか。
  ストアポリシー側にその旨の記述は見つけられなかった。**pub.dev で配布するライブラリという形態では
  ストア審査は直接の問題にならない**が、本ライブラリの利用者がストア配布する場合に問題になりうる、
  という点は [不明] のまま残る。
- 実務上の帰結: experimental を採ると、**(a) API が予告なく変わる / 消える、(b) 不具合が起きても
  サポートが受けられない（§4 の open issue がその実例）、(c) 利用者アプリが experimental 版
  WinAppSDK への依存を強いられる**、の3つを利用者に転嫁することになる。
  requirements.md NFR-5 は「各OS APIのstable化までstableを名乗らない」としており 0.x 系での公開は
  想定内だが、**0.x であることと、サポート対象外チャンネルに依存することは別の話である。**

---

## 6. 推奨

### 6.1 正直な結論

**stable チャンネルだけで FR-3 / FR-4 / NFR-2 / NFR-3 / NFR-4 / ja-JP をすべて満たすことが
「確認できている」選択肢は、現時点で存在しない。**

唯一、制約に矛盾しない候補は **SAPI 5（候補2）** だが、これは
「条件を満たすことが確定した」のではなく「**満たさないと確定した項目が今のところ無い**」という状態である。
具体的には次の3点が未確定のまま残っており、そのどれか1つでも外れると候補2も消える。

1. Windows 11 24H2/25H2 で `CLSID_SpInprocRecognizer` が生成でき、ja-JP のレコグナイザーが
   列挙・選択できるか（Speech FOD が現在も ja-JP で提供されているか）。
2. ja-JP のディクテーションが WAV ファイル入力で実際にテキストを返すか。その精度が
   design.md §7 のしきい値に対してどうか。
3. 認識中にネットワーク送信が発生しないか（NFR-2 の実測確認）。

### 6.2 まず行うべきこと（推奨）

**Windows 実機はもう手元にある。候補2の可否は、1〜2日の小さな検証で決着する。** 推奨する手順:

1. **レコグナイザートークンの列挙**（数時間）。`SPCAT_RECOGNIZERS` カテゴリのトークンを列挙し、
   各トークンの `Language` 属性を出力する。ja-JP（LCID 0x411）のトークンが出るか。
   出なければ `設定 > 時刻と言語 > 言語と地域` で日本語の「音声認識」機能を追加、
   あるいは `Install-Language ja-JP` を実行して再列挙する。**ここで ja-JP が出なければ候補2は終わり**であり、
   それ以上の実装コストはかからない。
2. **WAV ファイル入力での ja-JP ディクテーション**（半日〜1日）。§3.2.1 のサンプルをほぼそのまま使い、
   既存の `spikes/windows/fixtures/` の jaJP_10s を食わせて `SPEI_RECOGNITION` のテキストを取る。
   同時に Windows のリソースモニター等でネットワーク送信の有無を見る（NFR-2 の確認）。
3. 上記が通ったら、既存の M0 判定基準（キーワード包含率、design.md §7）で精度を測る。
   **他の3プラットフォームが 66.7% であることを踏まえ、同じ基準音声・同じ判定規則で比較する。**

この検証コードは既存スパイク（`src/Core/FileRecognition.*`）とは別物になるが、
COM のボイラープレートを含めても 200〜300 行程度であり、ドキュメントに C++ サンプルが
そのまま載っている分、Windows AI 版より書くのは容易である [推定]。

### 6.3 候補2を採用した場合の実装コストと設計上の影響

| 項目 | 影響 |
|---|---|
| FR-1 `checkModel(locale)` | `SPCAT_RECOGNIZERS` のトークン列挙で `available` / `unavailable` は判定できる [推定]。`downloadable` の判定は FOD の入手可能性を問い合わせる手段が [不明] で、`downloading` に至っては対応する概念が無い。**Windows AI 版（7値→4値）とは別の、もっと粗い写像になる** |
| FR-2 `downloadModel(locale)` | **アプリ内から非対話に起動する手段が [不明]**。`ms-settings:regionlanguage` へのディープリンク誘導に退化する可能性が高い [推定]。進捗は取れない |
| FR-3 `transcribeFile` | ○。`SPEI_RECOGNITION` を複数回 emit、`SPEI_SR_END_STREAM` で完了。キャンセルはストリームの `Close()` で可能 [推定] |
| FR-4 デコード | Media Foundation で m4a/mp3 → 16bit PCM WAV に変換してから `BindToFile`。design.md §4.4 が既に想定していた経路と同じ |
| FR-5 ロケール指定 | **Windows AI 版より良くなる。** Windows AI にはロケール指定APIが存在しない（RESULTS.md で確定済み）が、SAPI はレコグナイザートークンを言語で選べる [推定]。requirements.md FR-6 の「Windows では `localeUnsupported` が原理的に発生しない」という記述は失効し、むしろ普通に発生するようになる |
| 利用者への制約（§8） | **MSIX 化も `systemAIModels` capability も不要になる** [推定]。代わりに「日本語の音声認識機能（言語FOD）が端末に入っている必要がある」という新しい前提を README に書くことになる |
| 既存コード | `src/Core/ModelReadiness.*` / `FileRecognition.*` / `LocaleInquiry.*` / `CapabilityCheck.*` は Windows AI 前提であり、**ほぼ全面的に書き直しになる** |

### 6.4 候補2が不成立だった場合の選択肢

推奨を作文しないために、選択肢だけを並べる。**優先順位の決定はオーナーの判断である。**

1. **v1 から Windows を外す。** requirements.md §3「対象外」に Linux と並べて Windows を入れ、
   README の対応マトリクスに理由（「OSネイティブのオフライン・ファイル入力ASRが stable API として
   存在しないため」）を明記する。**コストはドキュメント修正のみで最小。** 失うのは Windows ユーザーである。
2. **Windows は API 安定化まで待つ（コードは残し、実行時 `unavailable` を返す）。** 1 との違いは、
   実装済みの WinRT コードを捨てずに experimental ビルドでのみ有効化できるようにしておく点。
   「いつ来るか未定」（§4）なので、待つ期間は見積もれない。
3. **制約を1つ緩める。** 緩めるコストが小さい順に:
   - **「stable チャンネルのみ」を緩める**（= 候補8を採る）。技術的コストは**ゼロ**である
     （実機でコンパイルが通ることが確認済み）。代償は §5 のとおりサポート外依存と、
     利用者に experimental WinAppSDK を強いること、および §4 の open issue が示す品質リスク。
   - **NFR-3（モデル非同梱）を緩める**（= sherpa-onnx 等を Windows だけで使う）。技術的には確実に動き、
     ja-JP も精度も担保しやすいが、**本ライブラリの存在理由そのもの**（requirements.md §2、
     README の比較表）を Windows で放棄することになる。プラットフォームごとに「モデルを同梱するか」が
     変わるライブラリは説明が破綻しやすい。
   - **NFR-2（オフライン）を緩める**。これは検討に値しない。プロダクトが別物になる。

### 6.5 リスク（推奨経路 = 6.2 を採った場合）

| リスク | 影響 | 備考 |
|---|---|---|
| ja-JP の Speech FOD が 24H2 以降で提供されていない | 候補2が即座に消える | §3.2.2。根拠が 1809 世代の対応表しかない。**6.2 の手順1で最初に潰れる** |
| WSR 非推奨が SAPI ランタイム／エンジンの削除にまで及ぶ | 出荷後に Windows Update で壊れる | §3.2.4。非推奨は2023年12月公表。削除予告は無いが、**「削除されない」という保証も無い** |
| ja-JP 認識精度がしきい値に全く届かない | 実装しても使い物にならない | §3.2.5。他3プラットフォームも 66.7% で不成立中であり、判定基準自体の見直しが先という可能性もある |
| 認識中にネットワーク送信がある | NFR-2 違反で即不採用 | §3.2.3 が [推定] どまりであるため、実測で確かめる必要がある |
| FR-2（モデルダウンロード）がAPIとして成立しない | 共通API契約の一部が Windows で機能しない | §6.3。設定アプリ誘導に退化した場合、`Stream<double>` という戻り値型の意味が Windows では失われる |

---

## 7. 確定できなかったことの一覧（実機または将来の公表待ち）

1. Windows 11 24H2/25H2 における ja-JP Speech FOD（`Language.Speech~~~ja-JP`）の提供有無。
2. Windows 11 24H2/25H2 で `CLSID_SpInprocRecognizer` が生成可能かどうか。
3. SAPI 認識時のネットワーク送信の有無（NFR-2）。
4. SAPI ja-JP エンジンの書き起こし精度。
5. ファイル入力時の `SPEI_HYPOTHESIS`（partial 相当）の発火有無。
6. アプリ内から言語FODの導入を非対話にトリガーする手段（FR-2）。
7. `System.Speech` が SAPI の薄いラッパーであることの一次資料による裏付け。
8. `Microsoft.Windows.AI.Speech` が stable / preview に来る時期（公開コミットメントなし）。
9. Microsoft Store のポリシーが experimental WinAppSDK 依存アプリを拒否するかどうか。
10. WebView2 で Edge のオンデバイス Web Speech が利用可能かどうか、および ja-JP 対応の時期。
11. Live Captions のエンジンが将来 API 公開されるかどうか。
