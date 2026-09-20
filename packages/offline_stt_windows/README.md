# offline_stt_windows

`offline_stt` の Windows 実装(C++/WinRT + [Windows AI APIs の Speech Recognition](https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition))。

このパッケージは federated plugin の実装パッケージであり、**利用者が直接依存するものではない**(requirements.md §6 / design.md §1)。アプリ側は `offline_stt` にのみ依存すれば、`offline_stt` の `flutter.plugin.platforms.windows.default_package` によって自動的にこの実装が使われる。

ただし **Windows だけは、依存関係を書くだけでは動かない**。アプリを MSIX でパッケージ化し、`Package.appxmanifest` に `systemAIModels` capability を宣言する必要がある(requirements.md §8、design.md §4.4)。この文書はそのセットアップ手順である(Issue #57)。

> **この文書に書かれた手順は、一度も実行して確認していない。** 本リポジトリには Windows 実機が無く、MSIX の生成・インストール・実行は未実施である。記載内容は Microsoft 公式ドキュメントと `spikes/windows/` の調査結果から導いたものであり、「検証済み」ではない。実機での確定は Issue #58 に委ねている。文中では、公式ドキュメントで文言を確認できた事項と、そこから導いた判断とを区別して書いている。

---

## 1. 動作要件

requirements.md NFR-4 および公式ドキュメント(最終更新 2026-07-07)の Prerequisites より:

| 項目 | 要件 |
|---|---|
| OS | Windows 11, version 24H2 (build 26100) 以降 |
| WinAppSDK | 1.7.1 以降(NuGet の `Microsoft.WindowsAppSDK` では `1.7.250401001` 相当。本プラグインの既定は 1.7 系の最新サービシング `1.7.260224002`) |
| ハードウェア | NPU 搭載の Copilot+ PC、**または** 推奨 CPU 要件を満たす任意の Windows PC |
| パッケージ形態 | **MSIX**(`systemAIModels` capability 宣言つき) |

補足:

- **GPU はサポートされない**。NPU か CPU かの選択は OS が自動で行い、アプリから指定する手段は無い。
- Copilot+ PC(NPU)では音声認識モデルが**プリインストール**されている。CPU のみの PC では**プリインストールされておらず**、最初の `EnsureReadyAsync()`(= `downloadModel()`)呼び出し時に **Windows Update 経由でバックグラウンド取得**される。
- WinAppSDK のバージョン決定の経緯(M0 調査時点の `windows-app-sdk-2.0-experimental` モニカーとの齟齬がどう解消したか)は `windows/CMakeLists.txt` 冒頭のコメントに詳しい。

## 2. なぜ MSIX パッケージ化が必要なのか

`Microsoft.Windows.AI.Speech` のモデルは、アプリが `systemAIModels` capability を宣言している場合にのみアクセスできる。そして **capability を宣言する場所は MSIX パッケージの `Package.appxmanifest` しか無い**。したがって、このプラグインを使うアプリは MSIX でパッケージ化されていなければならない。

ここで Flutter 固有の問題がある。

> **Flutter の Windows アプリは、既定では「パッケージ化されていない Win32 アプリ」である。**
> `flutter build windows` が生成するのは `build/windows/x64/runner/<Configuration>/` 以下の素の EXE + DLL 一式であり、MSIX ではない。Flutter の公式ツールチェーンに MSIX を生成するコマンドは無い。

つまり **MSIX 化は `flutter build windows` の外側の工程である**。`flutter build windows` の出力を入力として、別途 MSIX を組み立てる必要がある(§4)。この一手間はライブラリ側で肩代わりできない(プラグインはアプリのパッケージ形態を決められない)ため、アプリ側の責務として明記する。

### 宣言しなかった場合に何が起きるか

公式ドキュメント(`get-started`)は `Microsoft.Windows.AI.AIFeatureReadyState.CapabilityMissing` の説明として次のように明記している。

> Model is not available to the current app due to a missing capability declaration. EnsureReadyAsync and CreateAsync will throw `winrt::hresult_access_denied` (add the systemAIModels capability to the app manifest).

ただしこの記述は `Microsoft.Windows.AI.Text.LanguageModel` についてのものであり、`SpeechRecognitionModel` について同一の記載は確認できていない(`spikes/windows/README.md`「`systemAIModels` capability を宣言しないとどうなるか」参照)。本プラグインはこの記述に従い、`E_ACCESSDENIED` を捕まえたときに「マニフェストに `systemAIModels` が無い可能性が高い」という旨をエラーメッセージへ含める(§8)。

なお `CapabilityMissing` という列挙値自体は WinAppSDK 2.0 以降で追加されたものであり、1.7 系で同じ値が返るのか、例外だけが飛ぶのかは未確認である。本プラグインの実装(`windows/model_availability.cpp`)は、全バージョンに存在する値だけを明示列挙し、残りを `default` で `unavailable` に倒すため、どちらであっても壊れない。

## 3. `Package.appxmanifest` の記載例

`flutter create` は `Package.appxmanifest` を生成しない。以下を自分で用意する。実際に動くファイルとしては [`apps/example/windows/packaging/Package.appxmanifest`](https://github.com/goofmint/offline_stt/blob/main/apps/example/windows/packaging/Package.appxmanifest) をそのまま雛形にできる。

既定の Desktop Bridge マニフェストからの**差分は次の4点だけ**である。

```xml
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  <!-- (1) systemai 名前空間を宣言する -->
  xmlns:systemai="http://schemas.microsoft.com/appx/manifest/systemai/windows10"
  <!-- (2) IgnorableNamespaces に systemai を足す -->
  IgnorableNamespaces="uap rescap systemai">

  <Dependencies>
    <!-- (3) MaxVersionTested を 10.0.26226.0 以降にする -->
    <TargetDeviceFamily Name="Windows.Universal" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26226.0" />
    <TargetDeviceFamily Name="Windows.Desktop"   MinVersion="10.0.17763.0" MaxVersionTested="10.0.26226.0" />
  </Dependencies>

  <Applications>
    <!-- Flutter のランナーは素の Win32 EXE なので Desktop Bridge 方式になる。
         Executable は windows/CMakeLists.txt の BINARY_NAME に対応する。 -->
    <Application Id="App" Executable="example.exe" EntryPoint="Windows.FullTrustApplication">
      ...
    </Application>
  </Applications>

  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
    <!-- (4) systemAIModels capability を宣言する -->
    <systemai:Capability Name="systemAIModels" />
  </Capabilities>
</Package>
```

**`MaxVersionTested` は必ず確認すること。** 公式ドキュメントは「古い値のままだとモデル読み込み時に "Not declared by app" エラーになる」と明記している。`systemAIModels` を書いたのに `CapabilityMissing` 相当の失敗が続く場合、真っ先に疑うべきはここである。

上記 (1)〜(4) は公式ドキュメント(`get-started` の「Edit the Package.appxmanifest file」節、および `speech-recognition` の Prerequisites)で文言そのものを確認している。一方 `Windows.FullTrustApplication` + `runFullTrust`(= 素の Win32 EXE の Desktop Bridge 方式)と `systemAIModels` の組み合わせは、公式サンプルが WinUI 3 / WPF / WinForms / .NET MAUI しか示していないため、**公式に確認できていない**(`spikes/windows/README.md` 要確認事項 9)。Flutter アプリは必ずこの組み合わせになるため、Issue #58 で最初に確認すべき点である。

## 4. MSIX パッケージ化の手段

`flutter build windows` の出力を MSIX にする方法は複数ある。どれも本リポジトリでは実行していない(Windows 機が無いため)。

### 0. winapp CLI(**Microsoft が Flutter 向けに公式手順を用意している。これを使うこと**)

Microsoft は `winapp` CLI という開発者ツールを提供しており、**Flutter 専用の手順ページまで用意している**: <https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/guides/flutter>

```powershell
winget install Microsoft.winappcli --source winget

# アプリのルート(pubspec.yaml のあるディレクトリ)で実行する。
# Package.appxmanifest / Assets / winapp.yaml と、
# WinAppSDK のヘッダー一式(.winapp/include)を生成する。
# プロンプトの「Setup SDKs」で "Stable SDKs" を選ぶこと。
winapp init

flutter build windows

# 署名も MSIX 化もせずに、パッケージ識別だけ与えて起動する(開発時)
winapp run .\build\windows\x64\runner\Release

# 配布用の MSIX を作る
winapp cert generate --if-exists skip
winapp pack .\dist --cert .\devcert.pfx
winapp cert install .\devcert.pfx   # 管理者権限。証明書ごとに1回
```

**このプラグインにとって `winapp init` は MSIX 化のためだけの手順ではない。** `winapp init` が展開する `.winapp/include` には WinAppSDK の C++/WinRT プロジェクションヘッダー(`winrt/Microsoft.Windows.AI.Speech.h` 等)が含まれており、**プラグインの `windows/CMakeLists.txt` はこのディレクトリを自動検出して Windows AI 実装をビルドする**。見つからない場合、プラグインは音声認識を行わず、すべての API 呼び出しが「`winapp init` を実行せよ」という明示的なエラーで失敗する(黙って `unavailable` を返すようなフォールバックはしない)。

したがって **既定の構成では、`winapp init` を実行していないアプリでこのプラグインは動かない。**

ただし `winapp init` そのものが必須なわけではない。必須なのは次の2つであり、`winapp init` はそれを一度に用意する最も簡単な手段にすぎない。

1. **WinAppSDK の C++/WinRT プロジェクションヘッダー**が読める場所にあること。`winapp init` 以外の方法で用意した場合は、CMake 変数 `OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR` にその場所を指定すれば同じように動く。
2. **`systemAIModels` capability を宣言した MSIX としてパッケージ識別が与えられていること**。これは §4 の A〜C のいずれの手段で用意しても構わない。

> **なぜ NuGet の PackageReference ではないのか。** 当初はプラグインの CMake から `VS_PACKAGE_REFERENCES` で `Microsoft.WindowsAppSDK` を参照する方式を実装したが、CI(windows-2025)で実際にビルドしたところ `error C1083: Cannot open include file: 'winrt/Microsoft.Windows.AI.h'` で失敗した。WinAppSDK のプロジェクションヘッダーは Windows SDK には含まれず、NuGet パッケージ内の `.winmd` から `cppwinrt.exe` が生成するものであり、CMake が生成する `.vcxproj` に PackageReference を足すだけでは復元も生成も走らなかった。詳細は `windows/CMakeLists.txt` の冒頭コメントに記録してある。

以下の A〜C は `winapp` CLI を使わない場合の代替手段である。

### A. Visual Studio の「Windows アプリケーション パッケージ プロジェクト」(.wapproj)

最も素性が確かな方法。`.wapproj` に `flutter build windows` の出力ディレクトリを参照させ、`Package.appxmanifest` を差し替えてビルドする。Microsoft の Desktop Bridge 公式手順そのものであり、署名・バージョニング・アップロード用バンドル生成まで一貫して面倒を見てくれる。

欠点は Visual Studio(または Build Tools + 「ユニバーサル Windows プラットフォーム開発」ワークロード)が必要になること、そして Flutter のビルド出力を外部から参照する形になるため `.wapproj` を手で書く必要があることである。`spikes/windows/packaging/WindowsSTTSpikePackage.wapproj` に、素の Win32 EXE を対象とした `.wapproj` の例がある(これも未検証)。

**`.wapproj` を使う場合は、次の設定をパッケージングプロジェクトに追加すること。**

```xml
<PropertyGroup>
  <AppxOSMinVersionReplaceManifestVersion>false</AppxOSMinVersionReplaceManifestVersion>
  <AppxOSMaxVersionTestedReplaceManifestVersion>false</AppxOSMaxVersionTestedReplaceManifestVersion>
</PropertyGroup>
```

これが無いと、Visual Studio がビルド時に `Package.appxmanifest` の `MaxVersionTested` をプロジェクト側の値で上書きしうる。§3 のとおり `MaxVersionTested` が古いままだと、`systemAIModels` を正しく宣言していてもモデルの読み込みが「Not declared by app」で失敗する。

### B. `MakeAppx.exe` + `SignTool.exe` による手動パッケージング

Windows SDK に含まれるコマンドラインツールだけで完結する。おおよそ次の形になる。

```powershell
# 1. Flutter のビルド出力を集める
flutter build windows --release
# 出力: build\windows\x64\runner\Release\

# 2. その中に Package.appxmanifest と Assets\ を置く
copy windows\packaging\Package.appxmanifest build\windows\x64\runner\Release\AppxManifest.xml
#    MakeAppx はレイアウト内の AppxManifest.xml を読む。Package.appxmanifest の
#    名前のままではマニフェストとして認識されない。
xcopy /E /I windows\packaging\Assets build\windows\x64\runner\Release\Assets

# 3. MSIX を作る
MakeAppx.exe pack /d build\windows\x64\runner\Release /p example.msix

# 4. 署名する(サイドロードには署名が必須)
SignTool.exe sign /fd SHA256 /a /f mycert.pfx /p <password> example.msix
```

CI に載せやすいのが利点。欠点は `.wapproj` が自動でやってくれることを全部自分で管理する必要があること(アセットのサイズ要件、バンドル、アーキテクチャ)である。**上記のコマンド列は公式ドキュメントの一般的な `MakeAppx` 手順から構成したものであり、Flutter の出力ディレクトリに対してそのまま通るかは未確認である。**

### C. `msix` pub package

Flutter コミュニティには `flutter pub run msix:create` で MSIX を生成する pub package が存在する。手軽だが、**`systemAIModels` のような独自名前空間つき capability 要素(`<systemai:Capability>`)を出力できるかは確認していない**。単純な capability 名の列挙しかできない場合、`xmlns:systemai` の宣言も `IgnorableNamespaces` への追加もできず、このプラグインの要件を満たせない。

使うのであれば、**生成された MSIX を展開して `AppxManifest.xml` に §3 の (1)〜(4) がすべて入っていることを目視確認すること**。入っていなければ A か B に切り替える。「たぶん入っているだろう」で進めると、実行時に `CapabilityMissing` / `E_ACCESSDENIED` として現れ、原因の切り分けに時間を取られる。

### サイドロード

いずれの方法でも、開発中のサイドロードには署名済み MSIX と、その証明書が「信頼されたルート証明機関」または「信頼された人」に入っていることが必要である。`Identity` の `Publisher` 属性は証明書のサブジェクトと**完全一致**していなければならない。不一致だとインストール時に弾かれる。

## 5. モデルの取得とユーザー同意(FR-2)

requirements.md FR-2 / §8 および design.md §3 は「**ライブラリは内部で暗黙にモデルをダウンロードしない**」「同意 UI はアプリ側の責務」と定めている。Windows AI の推奨 UX パターンもこれと一致する。

正しい呼び出し順序:

```
checkModel(locale)
  ├─ available    → transcribeFile() を呼んでよい
  ├─ downloadable → 【同意ダイアログを出す】→ 同意が得られたら downloadModel()
  │                  → 完了後に再度 checkModel()
  ├─ downloading  → 待つ
  └─ unavailable  → 端末・OS・マニフェストの問題。アプリからは解消できない
```

### 同意ダイアログに書くべきこと

公式ドキュメントが推奨する内容は次の4点である。`downloadModel()`(= `EnsureReadyAsync()`)を呼ぶ**前**に提示する。

1. 追加の音声認識モデル(オプションの AI コンポーネント)がダウンロードされること
2. ダウンロードは **Windows Update 経由でバックグラウンドで**行われること
3. 進捗は **設定 > Windows Update** で確認できること
4. モデルは後から **設定 > システム > AI コンポーネント** で削除できること

文言ガイドライン(requirements.md §8 と公式ドキュメントの両方が同じことを言っている): **具体的なモデル名やベンダー名を出さず**、「音声認識モデル」「オプションの AI モデル」といった一般名称で呼ぶこと。

参照実装は [`apps/example/lib/src/download_consent_dialog.dart`](https://github.com/goofmint/offline_stt/blob/main/apps/example/lib/src/download_consent_dialog.dart) にある。Windows では上記4点を含む Windows 専用の文面に切り替えている。

## 6. 再同意フロー(モデルが削除されたとき)

**これは Windows 固有の、見落としやすい状態遷移である。**

ユーザーは **設定 > システム > AI コンポーネント** から、一度取得した音声認識モデルをいつでも削除できる。削除されると次のようになる。

```
[以前 available だった] → ユーザーが AI コンポーネントからモデルを削除
  → 次の checkModel() は downloadable を返す
  → transcribeFile() を呼ぶと ModelUnavailableException になる
  → 【同意ダイアログを出し直す】→ downloadModel() → 再度 checkModel()
```

したがってアプリ側は次を守る必要がある。

- **モデル状態をアプリ起動時に1度だけ確認して記憶しない。** 文字起こしを開始する直前に `checkModel()` を呼び直すこと。`available` は永続的な性質ではない。
- **同意は1度きりのものとして扱わない。** 「以前同意したから」という理由で同意 UI を飛ばして `downloadModel()` を呼ぶのは、公式の推奨 UX パターンに反する。削除はユーザーの明示的な意思表示なので、再取得にも改めて同意を求める。
- `downloadModel()` の完了後は必ず `checkModel()` で `available` を確認してから `transcribeFile()` へ進む(design.md §3 の状態遷移)。

### ドキュメント間の食い違いについて

公式ドキュメントの Recommended UX pattern は、削除後の状態を `NotReady` **または `EnsureNeeded`** と書いている。一方 design.md §5 の注記は「`EnsureNeeded` という値は実際の `AIFeatureReadyState` enum には存在しない」と記録している(実際の7値は `Ready` / `NotReady` / `NotSupportedOnCurrentSystem` / `DisabledByUser` / `CapabilityMissing` / `NotCompatibleWithSystemHardware` / `OSUpdateNeeded`)。

**この食い違いはまだ解消していない。** どちらが正しいかを実機で確認せずにどちらか一方を採用することはしない。本プラグインの実装は全バージョンに存在する値のみを明示列挙し、残りを `default` で `unavailable` に倒すため、`EnsureNeeded` という値が実在してもしなくても壊れない。ただし**もし実在した場合、それは `default` に落ちて `unavailable` になり、`downloadable` にはならない**。その場合は削除後の再取得導線がアプリから見えなくなるため、`model_availability.cpp` の写像へ明示的な分岐を足す必要がある。確定は Issue #58 に委ねている。

## 7. `checkModel()` の状態写像と既知の制約

`GetReadyState()` が返す `AIFeatureReadyState`(7値)から requirements.md FR-1 の4値への写像は次のとおり。★ は文書化された対応ではなく本実装の判断である(根拠は `windows/model_availability.h` のコメント)。

| `AIFeatureReadyState` | `ModelState` | |
|---|---|---|
| `Ready` | `available` | |
| `NotReady` | `downloadable` | ★ |
| `DisabledByUser` | `unavailable` | ★ アプリからは解消不能。Windows の設定で再度有効化が必要 |
| `NotSupportedOnCurrentSystem` | `unavailable` | |
| `CapabilityMissing` | `unavailable` | ★ 実体はマニフェスト不備。§2 参照 |
| `NotCompatibleWithSystemHardware` | `unavailable` | |
| `OSUpdateNeeded` | `unavailable` | ★ |
| (将来追加される値) | `unavailable` | ★ |

### 制約1: `downloading` は自プロセスのダウンロードしか見えない

`AIFeatureReadyState` には `downloading` に一意対応する値が無い(design.md §4.4)。本実装は「**このプラグイン自身が `EnsureReadyAsync()` を実行している間だけ** `checkModel()` が `downloading` を返す」という形で補っている。その帰結:

- **別のアプリ、あるいは同じアプリの別プロセスが開始したダウンロードは見えない。** その間 `checkModel()` は `NotReady` 由来の `downloadable` を返しうる。
- **アプリを再起動するとこの情報は失われる。** OS 側のダウンロードが継続していても `downloading` には戻らず、`downloadable` に見える。

より正確にするには「`EnsureReadyAsync()` を呼ばずにダウンロード中かどうかを知る API」が必要だが、そのような API は `Microsoft.Windows.AI.Speech` に存在しないことをドキュメント調査で確認している。アプリ側は、`downloadable` が返ったからといって必ずしも「まだ何も始まっていない」とは限らない、という前提で UI を組むこと(OS が Windows Update 経由でバックグラウンド取得している最中かもしれない)。ダウンロード進捗の正確な確認先は、アプリ内ではなく **設定 > Windows Update** である。

### 制約2: ダウンロード進捗は常に不定進捗

`downloadModel()` が返す `DownloadProgress` は、Windows では**常に `fraction: null`**(不定進捗)である。`SpeechRecognitionModelProgress.Progress` という値自体は存在するが、**その値域がドキュメントに一切記載されていない**(0.0〜1.0 である保証が無い)うえ、`Status` が持つ `Installing` / `Caching` / `Loading` の各フェーズごとに 0→1 を繰り返すのか全体で単調増加するのかも記載が無い。根拠のない数値を `fraction`(design.md §2.2 が「0.0〜1.0」と定義)として素通ししたり、フェーズを 3 等分するような補正をかけたりはしない(詳細は `windows/model_acquisition.h`)。

アプリ側は Windows では不定進捗のプログレスインジケータを出すこと。Web の `install()` に対する扱いと同じである(requirements.md FR-2)。

### 制約3: `locale` 引数は無視される

`Microsoft.Windows.AI.Speech` 名前空間には**ロケール・言語を指定する API が1つも存在しない**ことがドキュメント調査で確定している(design.md §8 未決事項2、`spikes/windows/RESULTS.md`)。したがって `checkModel(locale)` / `transcribeFile(request.locale)` に渡したロケールは、Windows 実装では**状態判定にも認識にも使われない**。

**どの言語で認識されるかは OS 側の設定に依存する。** OS 表示言語に連動するのか、既定の入力言語に連動するのか、複数言語を同時に扱えるのかは、いずれもドキュメントに記載が無く未確認である。ja-JP の音声が実際に認識されるかどうかも**未検証**である(requirements.md §9 のリスク表に記載のとおり)。

この設計の帰結として、Windows 実装は `LocaleUnsupportedException` を**発生させない**。ロケールを指定する手段が無い以上、「そのロケールが非対応である」と判定する手段も無いためである(`windows/windows_transcribe_error.h`)。

## 8. エラーの見分け方

design.md §5 のエラーマッピング表 Windows 列に対応する。

| 例外 | Windows での発生源 |
|---|---|
| `ModelUnavailableException` | `NotReady` の状態で `transcribeFile()` を呼んだ / `EnsureReadyAsync()` の失敗 |
| `DecodeFailedException` | Media Foundation による wav 変換の失敗(HRESULT が `0xC00D....` 帯) |
| `DeviceUnsupportedException` | `NotSupportedOnCurrentSystem` 等 |
| `CancelledException` | 認識の中断(Stream の cancel) |
| `PlatformException_` | 上記のいずれにも分類できないもの(ネイティブ側のコードは `platformError`) |
| `LocaleUnsupportedException` | **発生しない**(§7 制約3) |

`systemAIModels` の宣言漏れ(`E_ACCESSDENIED`)は `PlatformException_` に分類される。`DeviceUnsupportedException` ではない点に注意する。これは「端末が非対応」ではなく「アプリのマニフェスト不備」であり、FR-1 の4値・FR-6 の6値にこれを表す専用の値が無いためである。原因に到達できるよう、メッセージに `systemAIModels` への言及を含めている(`windows/windows_transcribe_error.cpp`)。

**HRESULT の分類は未検証である。** 各 API が実際にどの HRESULT を返すかは一度も観測できていない。現在の分類は公式ドキュメントの記述と Media Foundation の HRESULT ファシリティ規約(`MF_E_*` は `0xC00D....`)に基づく推定である。


> **追記(CI で判明した事実)**: 下記のうち「CMake 経由の NuGet 復元と C++/WinRT プロジェクションヘッダー生成が成立するか」は、CI(windows-2025)で実際にビルドして **成立しないことが分かった**(`error C1083: Cannot open include file: 'winrt/Microsoft.Windows.AI.h'`)。そのため §4.0 の winapp CLI 方式へ切り替えてある。また `<experimental/coroutine>` の非推奨エラー(MSVC 14.51 の `error C2338: STL1011`)も同時に判明し、WinRT 実装のビルドでは C++20 を要求するようにした。**ただし WinRT 実装そのもののコンパイルは依然として一度も通っていない。** CI は winapp CLI を持たないため、WinRT 実装をビルドしないからである。

## 9. 未検証事項

この文書と Windows 実装全体について、Windows 実機でしか確定できない事項:

> **既に決着している項目(再試行しないこと)**: 「CMake 経由での WinAppSDK NuGet 復元と C++/WinRT プロジェクションヘッダー生成」は**未検証ではなく、CI(windows-2025)で実際に失敗することが確認済み**である(`error C1083: Cannot open include file: 'winrt/Microsoft.Windows.AI.h'`)。そのため §4.0 の `.winapp/include` 方式へ切り替えてある。この経路を再試行する必要はない。

1. **MSIX 化そのもの。** 本リポジトリの `Package.appxmanifest` で MSIX を生成し、インストールし、起動するところまで一度も実施していない。
2. Desktop Bridge(`Windows.FullTrustApplication` + `runFullTrust`)と `systemAIModels` capability の組み合わせが実際に機能するか(公式サンプルは WinUI 3 / WPF / WinForms / .NET MAUI のみ)。
3. `flutter build windows` の出力に対する `MakeAppx` / `.wapproj` / `msix` pub package それぞれの適用可否。
5. `EnsureNeeded` の実在(§6)。
6. `SpeechRecognitionModelProgress.Progress` の値域とフェーズごとの挙動(§7 制約2)。
7. ロケール指定 API が無い状態で、実際にどの言語で認識されるか。ja-JP の認識可否・精度(§7 制約3)。
8. `BatchRecognition.RecognizeFromFile` が受理する音声フォーマット(design.md §8 未決事項1。ドキュメントに記載が無い。本実装は Media Foundation で wav へ変換してから渡すことでこれを回避している)。
9. 各 API が返す HRESULT の実際の値と、§8 の分類の妥当性。
10. 1.7 系で `CapabilityMissing` が実際に返るのか、例外だけが飛ぶのか。

これらは Issue #58(Windows 実機 E2E)の対象である。
