/// パッケージ内部で共有する共通型のバレル(design.md §2.1・§2.2)。
///
/// 旧 `offline_stt_platform_interface` パッケージの公開バレルに相当する。
/// 単一パッケージへ統合した後も、抽象 [OfflineTranscriberPlatform] と
/// データ型・例外型は各プラットフォーム実装(`src/android/` /
/// `src/darwin/` / `src/web/`)から同じ一式として参照されるため、
/// 参照点をこのファイルに集約している。
///
/// **公開APIではない。** 利用者向けの公開バレルは `lib/offline_stt.dart`
/// である。`TranscribeSessionGuard`(`src/session_guard.dart`)は
/// ネイティブ実装だけが使う内部実装であるため、ここには含めない。
library;

export 'download_progress.dart';
export 'exceptions.dart';
export 'model_state.dart';
export 'offline_transcriber_platform.dart';
export 'transcribe_request.dart';
export 'transcript_segment.dart';
