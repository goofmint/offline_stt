# Changelog

## 0.1.0

初回リリース。利用者が依存するエントリパッケージ(requirements.md §6)。

### 追加

- federated plugin のエンドースメント設定。`offline_stt` に依存するだけで
  Android / iOS / macOS / Web の各実装パッケージが自動的に
  選択される。
- `offline_stt_platform_interface` のデータ型・例外型の再エクスポート。
- 利用者向けファサード `OfflineTranscriber`。`checkModel()` /
  `downloadModel()` / `transcribeFile()` の3メソッドを持ち、
  `OfflineTranscriberPlatform.instance` へ委譲する。**利用者が
  `offline_stt_platform_interface` を直接依存に書く必要はない。**

### 既知の制約

- **認識精度は design.md §7 のしきい値に達していない。** 実測できた
  Darwin / Web / Android のいずれも、基準音声 jaJP_10s で包含率 66.7% で
  あり不成立である。原因は未確定である(design.md §7「注記」)。
