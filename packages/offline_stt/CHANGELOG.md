# Changelog

## 0.1.0

初回リリース。pub.dev へ公開するのはこの1パッケージだけである
(requirements.md §6、Issue #91)。

### 追加

- Android / iOS / macOS / Web の実装を同梱した単一のFlutterプラグイン。
  アプリは `offline_stt` にのみ依存すればよい。実装の選択はコンパイル時の
  条件付きimport(Web か否か)と実行時の `Platform` 判定(Android /
  iOS / macOS)で行う。
- データ型・例外型(`ModelState` / `DownloadProgress` /
  `TranscribeRequest` / `TranscriptSegment` と例外階層)の公開。
- 利用者向けファサード `OfflineTranscriber`。`checkModel()` /
  `downloadModel()` / `transcribeFile()` の3メソッドを持ち、内部の
  プラットフォーム実装へ委譲する。

### 既知の制約

- **認識精度は design.md §7 のしきい値に達していない。** 実測できた
  Darwin / Web / Android のいずれも、基準音声 jaJP_10s で包含率 66.7% で
  あり不成立である。原因は未確定である(design.md §7「注記」)。
