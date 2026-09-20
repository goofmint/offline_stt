/// `offline_stt` エントリパッケージ。
///
/// 利用者はこのパッケージにのみ依存する(requirements.md §6)。
///
/// 注記: 本パッケージの公開API(`OfflineTranscriber` 等の利用者向けクラス)は
/// Issue #21(モノレポ雛形作成)の対象外である。現時点では
/// `offline_stt_platform_interface` の型を再エクスポートするのみであり、
/// 各プラットフォーム実装(offline_stt_android 等)へ処理を委譲する具体的な
/// 公開APIクラスは後続Issueで実装する。
library;

export 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart'
    show
        CancelledException,
        DecodeFailedException,
        DeviceUnsupportedException,
        DownloadProgress,
        LocaleUnsupportedException,
        ModelState,
        ModelUnavailableException,
        PlatformException_,
        TranscribeException,
        TranscribeRequest,
        TranscriptSegment;
