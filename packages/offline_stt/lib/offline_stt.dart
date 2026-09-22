/// `offline_stt` パッケージ。
///
/// 録音済み音声ファイルをOSネイティブAPIのみでオフライン文字起こしする
/// (requirements.md §6)。Android / iOS / macOS / Web の実装を1つの
/// パッケージに同梱しており、利用者はこのライブラリだけをimportすればよい。
///
/// 公開APIは [OfflineTranscriber] と、それが受け渡しするデータ型・例外型で
/// ある。`src/` 配下は実装詳細であり、直接importしてはならない。
library;

export 'src/download_progress.dart' show DownloadProgress;
export 'src/exceptions.dart'
    show
        CancelledException,
        DecodeFailedException,
        DeviceUnsupportedException,
        LocaleUnsupportedException,
        ModelUnavailableException,
        PlatformException_,
        TranscribeException;
export 'src/model_state.dart' show ModelState;
export 'src/offline_transcriber.dart' show OfflineTranscriber;
export 'src/transcribe_request.dart' show TranscribeRequest;
export 'src/transcript_segment.dart' show TranscriptSegment;
