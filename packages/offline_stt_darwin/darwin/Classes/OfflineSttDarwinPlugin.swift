import Flutter

/// offline_stt のDarwinネイティブ側エントリポイント(雛形)。
///
/// Pigeon生成コード(`pigeons/offline_stt_events.dart` から生成、Issue #24)の
/// `OfflineSttHostApi`(MethodChannel)・`OfflineSttStreamEvents`
/// (EventChannel、design.md §2.3)は同ディレクトリの `Pigeon.g.swift` を
/// 参照。SpeechAnalyzer連携の実装本体はM2で行う(design.md §4.2)。
/// `spikes/darwin/Sources/DarwinSTTSpikeCore/` の検証済みロジックを移植の
/// 出発点とする。
public class OfflineSttDarwinPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // TODO(M2): `OfflineSttHostApi` プロトコルに準拠したクラスを
        // `OfflineSttHostApiSetup.setUp(binaryMessenger:api:)` で登録する。
    }
}
