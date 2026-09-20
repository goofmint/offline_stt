# offline_stt_platform_interface

`offline_stt` の共通プラットフォームインターフェースを定義する純Dartパッケージである(Flutterプラグインではない)。

## 役割

- `OfflineTranscriberPlatform` 抽象クラス(`plugin_platform_interface` によるtoken検証を伴う標準構成)
- データ型: `ModelState` / `DownloadProgress` / `TranscribeRequest` / `TranscriptSegment`
- 例外階層: `TranscribeException`(sealed class)とその派生

各プラットフォーム実装パッケージ(`offline_stt_android` / `offline_stt_darwin` / `offline_stt_windows` / `offline_stt_web`)はこのパッケージに依存し、`OfflineTranscriberPlatform` を継承したうえで `OfflineTranscriberPlatform.instance` を自身に差し替えることで登録する。

## 契約の出典

本パッケージの型・メソッドは **design.md §2(§2.1 platform_interface、§2.2 データ型)を唯一の権威ある契約として** 実装している。design.md にない型・メソッドは追加しない。

状態遷移(`[unavailable]` / `[downloadable]` → `[downloading]` → `[available]` → セッション)とセッション排他(同時1本、2本目は `StateError`)の規則は design.md §3 を参照。規則自体は本パッケージのdocコメントに明記しているが、網羅テストと排他ロジックの実装は別Issueで行う。

## 既知の差異

`TranscribeRequest` は design.md §2.2 の現行定義(`path` / `locale` の2フィールド)をそのまま実装している。`playbackRate` フィールドは design.md には存在しないため未実装である。
