# Changelog

## 0.1.0

初回リリース。Windows 実装(C++/WinRT、design.md §4.4)。

> **このパッケージは一度も実行されていない。** 本リポジトリに Windows 機が
> 無いため、`flutter build windows` によるWinRT実装のコンパイル、MSIX化、
> インストール、認識のいずれも未実施である。CI は WinRT バックエンドを
> 除外した構成のみをコンパイルしている。下記の「追加」は実装した内容の
> 記述であって、動作を確認したという意味ではない。

### 追加

- モデル管理: `SpeechRecognitionModel.GetReadyState()` が返す
  `AIFeatureReadyState` を `ModelState` の4値へ写像し、取得は
  `EnsureReadyAsync()` で行う。
- デコード: Media Foundation による wav(16kHz・モノラル・16-bit PCM)
  への変換。
- 文字起こし: `BatchRecognition.RecognizeFromFile`。バッチ認識であるため
  final セグメントを1回だけ通知する。
- Pigeon の C++ 生成器が `@EventChannelApi` に未対応であるため、ストリームは
  `@FlutterApi()` のコールバック4本で代替し、配送先の管理を
  `WindowsStreamRouter` が担う。
- MSIX パッケージ化と `systemAIModels` capability 宣言のセットアップ手順
  (README.md)。参照実装は `apps/example/windows/packaging/`。

### 既知の制約

- **アプリ側の MSIX パッケージ化が必須である。** `flutter build windows` の
  出力は素の Win32 アプリであり、`systemAIModels` capability を宣言できる
  場所が無い。加えて `winapp init` が展開する WinAppSDK の C++/WinRT
  プロジェクションヘッダーが無いと、本プラグインは Windows AI 実装を
  ビルドせず、モデル状態の照会・モデル取得・文字起こしが明示的なエラーで失敗する(黙って
  `unavailable` を返すフォールバックはしない)。
- **`locale` 引数は無視される。** `Microsoft.Windows.AI.Speech` には
  ロケール・言語を指定する API が存在しないことがドキュメント調査で確定
  している(design.md §8 未決事項2)。したがって
  `LocaleUnsupportedException` は発生しない。どの言語で認識されるかは
  OS 設定に依存し、**未確認である**。
- **`downloading` は自プロセスのダウンロードしか見えない。**
  `AIFeatureReadyState` に対応する値が無いため、本実装が
  `EnsureReadyAsync()` を実行している間だけ `downloading` を返す。
- **ダウンロード進捗は常に不定進捗である**(`fraction: null`)。
  `SpeechRecognitionModelProgress.Progress` の値域がドキュメントに記載
  されていないため、根拠のない数値を素通ししない。
- **HRESULT の分類は推定である。** 各APIが実際に返す HRESULT は一度も
  観測できていない。
- 実機E2Eは Issue #58。README.md §9 に、実機でのみ確定できる事項を
  10項目列挙している。
