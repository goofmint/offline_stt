# offline_stt_windows E2E 手動チェックリスト

対応 Issue: #66(収録)、#58(実機E2Eの実施)。対応する設計: design.md §7
「テスト戦略」、§4.4 Windows、§5 エラーマッピング表 Windows列。共通の前提・
包含率の算出方法・しきい値は
[リポジトリルートの E2E_CHECKLIST.md](../../E2E_CHECKLIST.md) を参照。

---

> # ⚠ この手順書は**一度も実行されていない**
>
> **本リポジトリに Windows 機は存在しない。** 以下はいずれも未実施である。
>
> - 開発機での `flutter build windows`(WinRTバックエンドを含む構成)
> - MSIX パッケージ化、署名、インストール
> - `checkModel()` / `downloadModel()` / `transcribeFile()` の実行
> - 音声認識そのもの
>
> CI(windows-2025)がコンパイルするのは **WinRTバックエンドを除外した構成
> だけ**である(CIランナーに `winapp` CLI が無く、WinAppSDK の C++/WinRT
> プロジェクションヘッダーが得られないため)。したがって
> `speech_backend_winrt.cpp` / `model_availability.cpp` /
> `model_acquisition.cpp` / `recognition_session.cpp` は**一度もコンパイルが
> 通っていない**。
>
> 本書は「実行して確認した結果」ではなく、**Windows 機が手に入ったときに
> 最初から順に実施するための未実行の手順**である。各項目の期待値は
> Microsoft 公式ドキュメントと `spikes/windows/RESULTS.md` のドキュメント
> 調査から導いたものであり、**実測による裏付けは一切ない**。

---

## なぜCIで検証できないのか

1. **Windows機が無い。** 認識に関わる判定は全て実機でしか行えない
   (spikes/windows/RESULTS.md「Windows 総合判定」)。
2. **GitHub Hosted Runner に Windows 11 クライアント版が無い。**
   `windows-2025` は Windows Server であり、requirements.md NFR-4 が言う
   Windows 11 24H2 クライアントそのものではない。
3. **CI は MSIX 化を検証しない。** `flutter build windows` が生成するのは
   パッケージ化されていない素の Win32 EXE であり、`systemAIModels`
   capability は MSIX の `Package.appxmanifest` にしか書けない。MSIX 化は
   `flutter build windows` の外側の工程である。

## 前提

- **OS**: Windows 11, version 24H2 (build 26100) 以降。
- **WinAppSDK**: 1.7.1 以降。
- **ハードウェア**: NPU 搭載の Copilot+ PC、または推奨CPU要件を満たす
  Windows PC。GPU はサポートされない。
- **Copilot+ PC(NPU)ではモデルがプリインストールされている。CPUのみの
  PC ではされておらず、最初の `EnsureReadyAsync()` で Windows Update 経由の
  バックグラウンド取得になる。** どちらの機種で検証したかを必ず記録する
  こと(手順の結果が変わる)。
- セットアップ手順(`winapp init`、MSIX化、`systemAIModels` の宣言)は
  本パッケージの [README.md](README.md) を参照。**その手順自体も未検証で
  ある。**

## 手順

### 0. ビルドとパッケージ化(ここが最初の関門)

**この手順0を通すこと自体が、本リポジトリで初めての試みになる。**

1. `apps/example` で `winapp init` を実行し、`.winapp/include` に WinAppSDK の
   C++/WinRT プロジェクションヘッダー(`winrt/Microsoft.Windows.AI.Speech.h`
   等)が展開されることを確認する。
2. `flutter build windows --release` を実行する。
   - プラグインの `windows/CMakeLists.txt` が `.winapp/include` を自動検出し、
     **WinRT実装を含めてビルドすること**を確認する。検出されない場合、
     プラグインは音声認識を行わず、モデル状態の照会・モデル取得・文字起こしが「`winapp init` を実行
     せよ」という明示的なエラーで失敗する(フォールバックはしない)。
   - **WinRT実装のコンパイルが通ること自体が未確認である。** `<experimental/
     coroutine>` の非推奨(MSVC 14.51 の `error C2338: STL1011`)対策として
     C++20 を要求するようにしてあるが、その先は未知である。
3. MSIX を生成し、署名し、インストールする(README.md §3・§4)。
   - 生成された MSIX を展開し、`AppxManifest.xml` に README.md §3 の
     (1)〜(4) がすべて入っていることを**目視確認する**。
   - `Identity` の `Publisher` が証明書のサブジェクトと完全一致している
     ことを確認する(不一致だとインストール時に弾かれる)。
4. **Desktop Bridge(`Windows.FullTrustApplication` + `runFullTrust`)と
   `systemAIModels` capability の組み合わせが機能するかを確認する。**
   公式サンプルは WinUI 3 / WPF / WinForms / .NET MAUI しか示しておらず、
   Flutter アプリが必ず取るこの組み合わせは公式に確認できていない。
   **ここが失敗した場合、以降の手順は全て実施できない。**

### 1. 可用性チェック(checkModel)

1. MSIX でインストールした example app を起動し、`checkModel('ja-JP')` を
   実行する。
2. ネイティブ側は `SpeechRecognitionModel.GetReadyState()` が返す
   `AIFeatureReadyState` を写像する。期待される対応(★は本実装の判断で
   あり、文書化された対応ではない):

   | `AIFeatureReadyState` | `ModelState` | |
   |---|---|---|
   | `Ready` | `available` | |
   | `NotReady` | `downloadable` | ★ |
   | `DisabledByUser` | `unavailable` | ★ |
   | `NotSupportedOnCurrentSystem` | `unavailable` | |
   | `CapabilityMissing` | `unavailable` | ★ 実体はマニフェスト不備 |
   | `NotCompatibleWithSystemHardware` | `unavailable` | |
   | `OSUpdateNeeded` | `unavailable` | ★ |

3. **実際に返った `AIFeatureReadyState` の生の値をログに記録する。**
   以下は実機でしか確定できない:
   - WinAppSDK 1.7 系で `CapabilityMissing` が実際に返るのか、例外だけが
     飛ぶのか(`CapabilityMissing` は 2.0 以降で追加された値である)
   - `EnsureNeeded` という値が実在するか。公式の Recommended UX pattern は
     削除後の状態を `NotReady` **または `EnsureNeeded`** と書いているが、
     design.md §5 の注記は実際の enum にその値は無いと記録している。
     **実在した場合、本実装では `default` に落ちて `unavailable` になり、
     `downloadable` にはならない。** その場合は削除後の再取得導線がアプリ
     から見えなくなるため、`windows/model_availability.cpp` の写像へ明示的な
     分岐を足す必要がある。
4. **`systemAIModels` 宣言漏れの挙動を確認する。** capability を外した
   MSIX を作り、`E_ACCESSDENIED` が `PlatformException_`(`DeviceUnsupported`
   ではない)として届き、メッセージに `systemAIModels` への言及が含まれる
   ことを確認する。
5. **`locale` 引数が無視されることを確認する。** `Microsoft.Windows.AI.Speech`
   にロケール指定APIは存在しない(design.md §8 未決事項2)。`ja-JP` と
   `xx-XX` で `checkModel()` の戻り値が変わらないことを確認する。
   `LocaleUnsupportedException` は発生しない。

### 2. downloadModel

1. `checkModel()` が `downloadable` を返した場合、example app の
   **Windows専用の同意ダイアログで明示的に同意したうえで**
   `downloadModel(locale)` を実行する。同意文面には以下4点が含まれている
   こと(requirements.md §8):
   1. 追加の音声認識モデルがダウンロードされること
   2. **Windows Update 経由でバックグラウンドで**行われること
   3. 進捗は **設定 > Windows Update** で確認できること
   4. モデルは後から **設定 > システム > AI コンポーネント** で削除できる
      こと
2. `DownloadProgress.fraction` が**常に `null`(不定進捗)**であることを
   確認する。`SpeechRecognitionModelProgress.Progress` の値域はドキュメントに
   記載が無いため、本実装は素通ししない。
3. 完了後に `checkModel()` を再実行し `available` になることを確認する。

### 3. 再同意フロー(Windows固有)

1. **設定 > システム > AI コンポーネント** から音声認識モデルを削除する。
2. `checkModel()` が `downloadable` を返すことを確認する
   (手順1の `EnsureNeeded` の件が絡む項目である)。
3. `transcribeFile()` を呼ぶと `ModelUnavailableException` になることを
   確認する。
4. example app が同意ダイアログを**出し直す**ことを確認する
   (「以前同意したから」で飛ばさないこと)。

### 4. `downloading` 状態の既知の制約

1. `downloadModel()` 実行中に `checkModel()` を呼ぶと `downloading` が
   返ることを確認する。
2. **アプリを再起動すると `downloading` は失われ、`downloadable` に見える**
   ことを確認する(本実装は自プロセスの `EnsureReadyAsync()` 実行中だけを
   `downloading` とするため)。これは仕様であり不具合ではない。
   OS側のダウンロード進捗の正確な確認先は **設定 > Windows Update** である。

### 5. 文字起こし実行(transcribeFile)

基準音声8ファイル(ja-JP / en-US × 10秒 / 3分 × wav / m4a)すべてについて
実行する。

1. **【最重要】ja-JP の音声が実際に認識されるかを確認する。** ロケールを
   指定する手段が無いため、どの言語で認識されるかは OS 設定に依存する。
   OS 表示言語に連動するのか、既定の入力言語に連動するのか、複数言語を
   同時に扱えるのかは**いずれも未確認である**。OS の言語設定を変えながら
   挙動を記録すること。
2. `BatchRecognition.RecognizeFromFile` はバッチ認識であるため、
   **`isFinal: true` のセグメントが1件だけ届き、partial は届かない**
   (design.md §4.4、requirements.md FR-3)。この動作を確認する。
3. Media Foundation による wav 変換が m4a / mp3 等で成立することを確認する
   (本実装は `RecognizeFromFile` の対応フォーマットがドキュメント化されて
   いない問題を、事前に wav へ変換することで回避している。design.md §8
   未決事項1)。
4. 処理時間を記録する(NFR-1。実時間より速いかどうかは未測定である)。
5. **`TranscribeRequest.playbackRate` はWindowsでは無視される**(Web専用
   オプション)。

### 6. キャンセル

1. 3分クリップの文字起こし実行中に購読を `cancel()` する。
2. それ以降 `TranscriptSegment` が届かないこと、直後に別の
   `transcribeFile()` を開始できることを確認する。
3. **`WindowsStreamRouter` の配送先管理を確認する。** Pigeon の C++ 生成器が
   `@EventChannelApi` に未対応であるため、Windows だけはストリーム識別子の
   無い `@FlutterApi()` コールバック4本で代替している。キャンセル後の
   コールバックが誤って別のストリームへ配送されないことを確認する。

### 7. セッション排他(design.md §3)

1. `transcribeFile()` の Stream を購読したまま、2本目の `transcribeFile()` を
   購読する。
2. 2本目が Stream エラー(`StateError`)で即座に終了することを確認する。

### 8. エラーパス(design.md §5 Windows列)

| 例外 | 発火方法 | 備考 |
|---|---|---|
| `ModelUnavailableException` | `NotReady` の状態で `transcribeFile()` を呼ぶ | |
| `DecodeFailedException` | テキストファイルを `.wav` として渡す | HRESULT が `0xC00D....` 帯になるという**推定**の検証を兼ねる |
| `DeviceUnsupportedException` | 要件を満たさないPCで実行する | |
| `CancelledException` | 手順6のキャンセル | |
| `PlatformException_` | `systemAIModels` 宣言漏れ(`E_ACCESSDENIED`)等 | |
| `LocaleUnsupportedException` | — | **発生しない**(手順1の5.) |

**各APIが実際に返す HRESULT を全て記録すること。** 現在の分類は公式
ドキュメントの記述と Media Foundation の HRESULT ファシリティ規約に基づく
**推定であり、一度も観測されていない**。

### 9. キーワード包含率の記録

ルートの E2E_CHECKLIST.md の正規化ルールに従って算出し、記録する。
**Windows では一度も測定されていない**ため、比較対象となる過去の値は無い。

## 合否基準

- **手順0が通らない限り、本チェックリストは合否以前に実施できない。**
- 手順1〜8は**すべて期待どおりに動作すること**。バグがあれば不合格。
- 手順9(包含率)は記録項目である。**原因未調査のまま合格扱いにしては
  ならない**(design.md §7)。

## 実機でのみ確定できる事項(README.md §9 の再掲)

本チェックリストは以下を確定させることを目的とする。すべて未確定である。

1. MSIX 化そのもの
2. Desktop Bridge + `systemAIModels` の組み合わせが機能するか
3. `flutter build windows` の出力に対する各パッケージング手段の適用可否
4. WinRT実装のコンパイルが通るか
5. `EnsureNeeded` の実在
6. `SpeechRecognitionModelProgress.Progress` の値域とフェーズごとの挙動
7. ロケール指定APIが無い状態で、実際にどの言語で認識されるか。ja-JP の
   認識可否・精度
8. `BatchRecognition.RecognizeFromFile` が受理する音声フォーマット
9. 各APIが返す HRESULT の実際の値と、エラー分類の妥当性
10. WinAppSDK 1.7 系で `CapabilityMissing` が実際に返るのか
