# Changelog

## 0.1.0

初回リリース。利用者が依存するエントリパッケージ(requirements.md §6)。

### 追加

- federated plugin のエンドースメント設定。`offline_stt` に依存するだけで
  Android / iOS / macOS / Windows / Web の各実装パッケージが自動的に
  選択される。
- `offline_stt_platform_interface` のデータ型・例外型の再エクスポート。

### 既知の制約

- **利用者向けのfacadeクラス(`OfflineTranscriber` 等)はまだ存在しない。**
  現時点では `OfflineTranscriberPlatform.instance` を直接使う必要がある
  (`apps/example` も暫定的にそうしている)。facade の実装は後続の
  Issue に委ねている。
- **Windows はアプリ側の追加セットアップが必須である。** MSIX パッケージ化と
  `systemAIModels` capability の宣言、および `winapp init` によるWinAppSDK
  ヘッダーの配置が必要である。手順は `offline_stt_windows` の README を
  参照(この手順自体が未検証である点も同READMEに明記している)。
- **認識精度は design.md §7 のしきい値に達していない。** 実測できた
  Darwin / Web / Android のいずれも、基準音声 jaJP_10s で包含率 66.7% で
  あり不成立である。原因は未確定である(design.md §7「注記」)。
