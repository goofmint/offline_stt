/// `offline_stt` エントリパッケージ。
///
/// 利用者はこのパッケージにのみ依存する(requirements.md §6)。
///
/// 公開APIは [OfflineTranscriber] と、`offline_stt_platform_interface` から
/// 再エクスポートしているデータ型・例外型である。利用者が
/// `offline_stt_platform_interface` を直接依存に書く必要は無い。
library;

export 'src/offline_transcriber.dart';

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
