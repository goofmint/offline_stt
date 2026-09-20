# Changelog

## 0.1.0

初回リリース。`offline_stt` の共通プラットフォームインターフェース
(design.md §2.1)。

### 追加

- `OfflineTranscriberPlatform`: `checkModel()` / `downloadModel()` /
  `transcribeFile()` の3メソッドからなる抽象クラス。
  `plugin_platform_interface` の `PlatformInterface` によりトークン検証を
  行い、`implements` による実装を禁じる。
- データ型(design.md §2.2): `ModelState`(4値)、`TranscribeRequest`、
  `TranscriptSegment`、`DownloadProgress`。
- 例外階層(requirements.md FR-6): `TranscribeException` を基底とする
  sealed class 階層。`ModelUnavailableException` /
  `LocaleUnsupportedException` / `DecodeFailedException` /
  `DeviceUnsupportedException` / `CancelledException` /
  `PlatformException_`。
- `TranscribeSessionGuard`(`lib/src/session_guard.dart`): セッション排他
  (design.md §3、同時1本まで)をネイティブ実装パッケージ間で共有する
  ための mixin。**公開バレルには意図的に含めていない**(利用者向けAPIでは
  なく実装パッケージ間の共有実装であるため)。
