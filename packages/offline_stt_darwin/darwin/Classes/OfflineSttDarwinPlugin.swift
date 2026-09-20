import Flutter

/// offline_stt のDarwinネイティブ側エントリポイント(雛形)。
///
/// Pigeonスキーマ確定(design.md §2.3)後、MethodChannel/EventChannelの
/// ハンドラ登録・SpeechAnalyzer連携をここに実装する(design.md §4.2、M2)。
/// `spikes/darwin/Sources/DarwinSTTSpikeCore/` の検証済みロジックを移植の
/// 出発点とする。
public class OfflineSttDarwinPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // TODO(M2): Pigeon生成のAPI実装をここに接続する。
    }
}
