/// `offline_stt` プラグインの共通プラットフォームインターフェース。
///
/// design.md §2(§2.1 platform_interface、§2.2 データ型)が本パッケージの
/// 契約の出典である。実装がこのパッケージ単体で完結する純Dartパッケージ
/// であり、Flutterプラグインではない。
library;

export 'src/download_progress.dart';
export 'src/exceptions.dart';
export 'src/model_state.dart';
export 'src/offline_transcriber_platform.dart';
export 'src/transcribe_request.dart';
export 'src/transcript_segment.dart';
