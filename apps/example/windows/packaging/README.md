# apps/example の MSIX パッケージ化(Issue #59)

このディレクトリは `flutter create` の生成物ではない。`apps/example` を **MSIX** としてパッケージ化するために、リポジトリ側で用意したファイルを置いている。

```
packaging/
├── Package.appxmanifest   … systemAIModels capability を宣言したマニフェスト
├── Assets/                … MSIX が参照する画像(PLACEHOLDER.txt 参照。実体は未同梱)
└── README.md              … このファイル
```

手順の一般論・根拠・記載例の解説は [`packages/offline_stt_windows/README.md`](../../../../packages/offline_stt_windows/README.md) にまとめてある。ここには example app 固有の事情だけを書く。

> **未検証**: 本リポジトリに Windows 実機が無いため、以下の手順は一度も実行していない。`flutter build windows` すら実行していない(CI が初回の検証になる)。

## なぜこのディレクトリが要るのか

`flutter build windows` が生成するのは **パッケージ化されていない素の Win32 EXE** であり、MSIX ではない。一方 `Microsoft.Windows.AI.Speech` のモデルへアクセスするには `systemAIModels` capability の宣言が必要で、それを書ける場所は MSIX の `Package.appxmanifest` しか無い。

つまり **`flutter build windows` だけでは example app の文字起こしは動かない**。EXE としては起動するが、`checkModel()` は `unavailable`(`CapabilityMissing` 由来)を返すか、`downloadModel()` が `E_ACCESSDENIED` で失敗するはずである(どちらになるかは未確認。`packages/offline_stt_windows/README.md` §2)。

CI の `flutter build windows --debug` は**コンパイルが通ることしか検証していない**。MSIX 化と実際の認識動作は Issue #58 の実機検証の対象である。

## 推奨手順: winapp CLI(未検証)

Microsoft は Flutter 向けの公式手順を用意している(`packages/offline_stt_windows/README.md` §4.0)。**このプラグインは `winapp init` が展開する `.winapp/include` を自動検出して Windows AI 実装をビルドするため、`winapp init` を実行しないと example app でも音声認識は動かない**(モデル状態の照会・モデル取得・文字起こしが明示的なエラーになる)。

```powershell
cd apps\example
winget install Microsoft.winappcli --source winget
winapp init          # プロンプトの「Setup SDKs」で "Stable SDKs" を選ぶ
flutter build windows --release
winapp run .\build\windows\x64\runner\Release   # 開発時: 識別だけ与えて起動
```

`winapp init` は `Package.appxmanifest` も生成する。その場合、本ディレクトリの `Package.appxmanifest` から **`systemAIModels` capability の宣言(`xmlns:systemai` / `IgnorableNamespaces` / `<systemai:Capability>`)と `MaxVersionTested`** を生成物へ移すこと。これらが無いとモデルにアクセスできない。

## 手順: MakeAppx で手動パッケージングする場合(未検証)

```powershell
cd apps\example

# 1. Flutter のビルド出力を作る
flutter build windows --release
#    出力: build\windows\x64\runner\Release\example.exe ほか

# 2. マニフェストとアセットを出力ディレクトリへ重ねる
copy windows\packaging\Package.appxmanifest build\windows\x64\runner\Release\AppxManifest.xml
#    MakeAppx はレイアウト内の AppxManifest.xml を読む。Package.appxmanifest の
#    名前のままではマニフェストとして認識されない。
xcopy /E /I windows\packaging\Assets build\windows\x64\runner\Release\Assets
#    Assets\ の実体(StoreLogo.png 等)は同梱していない。
#    windows\packaging\Assets\PLACEHOLDER.txt を参照して用意すること。

# 3. MSIX を作る
MakeAppx.exe pack /d build\windows\x64\runner\Release /p example.msix

# 4. 署名する(サイドロードには署名が必須)
SignTool.exe sign /fd SHA256 /a /f mycert.pfx /p <password> example.msix
```

Visual Studio の「Windows アプリケーション パッケージ プロジェクト」(`.wapproj`)を使う方法もある。長所・短所の比較は `packages/offline_stt_windows/README.md` §4 を参照。

## 書き換えが必要な箇所

`Package.appxmanifest` の次の値は、署名に使う証明書に合わせて書き換える必要がある。

| 要素・属性 | 現在の値 | 備考 |
|---|---|---|
| `Identity/@Name` | `MoonGift.OfflineSttExample` | 任意。ただしインストール済みの他パッケージと衝突しないこと |
| `Identity/@Publisher` | `CN=MOONGIFT-OfflineSTT-Example-SelfSigned` | **署名証明書のサブジェクトと完全一致**させる。不一致だとインストールが失敗する |
| `Application/@Executable` | `example.exe` | `windows/CMakeLists.txt` の `BINARY_NAME`(= `example`)に対応する。pubspec の `name` を変えたら追随させること |

`MaxVersionTested="10.0.26226.0"` は**下げてはならない**。公式ドキュメントは、これが古いとモデル読み込み時に "Not declared by app" エラーになると明記している。

## 実機で確認すること

1. MSIX がインストールでき、起動すること。
2. `systemAIModels` 宣言ありの MSIX で `checkModel()` が `available` または `downloadable` を返すこと(素の EXE 実行時・宣言なし MSIX との差分を取る。`spikes/windows/` の Issue #18 対比実験と同じ構図)。
3. 同意ダイアログ → `downloadModel()` → 完了 → `checkModel()` が `available` になること。ダウンロード中に **設定 > Windows Update** に進捗が現れるかどうか。
4. **設定 > システム > AI コンポーネント** から音声認識モデルを削除したあと、`checkModel()` が `downloadable` に戻り、再同意 → 再ダウンロードの導線が機能すること(`packages/offline_stt_windows/README.md` §6 の再同意フロー)。ここで `downloadable` ではなく `unavailable` が返る場合、それは `EnsureNeeded` という未確認の列挙値が実在していて `default` へ落ちていることを意味しうるので、`windows/model_availability.cpp` の写像に分岐を足す必要がある。
5. ja-JP / en-US の音声ファイルが実際にどの言語として認識されるか(ロケール指定 API が存在しないため、OS 設定依存になる)。
