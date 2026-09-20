// iOS と macOS で Flutter のモジュール名が異なるため条件付きでimportする。
#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// offline_stt のDarwinネイティブ側エントリポイント(#33)。
///
/// Pigeon生成コード(`pigeons/offline_stt_events.dart` から生成、Issue #24)の
/// `OfflineSttHostApi`(MethodChannel)・`OfflineSttStreamEvents`
/// (EventChannel、design.md §2.3)を、`OfflineSttApiImpl`
/// (SpeechAnalyzer連携の実装本体、design.md §4.2)と結びつける。
public class OfflineSttDarwinPlugin: NSObject, FlutterPlugin {
  /// `register(with:)`はstaticメソッドであるため、ローカル変数に生成した
  /// インスタンスはそのままでは関数終了時に解放されてしまう。Pigeon生成の
  /// チャネルのメッセージハンドラ・EventChannelのStreamHandlerが`api`/
  /// 各ラッパーを強参照で保持するため通常は解放されないが、明示的に
  /// プラグインの生存期間(=アプリの生存期間)保持することを意図が
  /// 分かる形にするため、staticプロパティで保持する。
  private static var sharedInstance: OfflineSttDarwinPlugin?

  private var api: OfflineSttApiImpl!
  private var segmentsWrapper: SegmentsEventWrapper!
  private var downloadProgressWrapper: DownloadProgressEventWrapper!

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = OfflineSttDarwinPlugin()
    instance.setUp(with: registrar)
    sharedInstance = instance
  }

  private func setUp(with registrar: FlutterPluginRegistrar) {
    let segmentsWrapper = SegmentsEventWrapper()
    let downloadProgressWrapper = DownloadProgressEventWrapper()
    let api = OfflineSttApiImpl(
      segmentsWrapper: segmentsWrapper,
      downloadProgressWrapper: downloadProgressWrapper
    )
    // EventChannel自体がキャンセルされた場合の保険(EventChannelWrappers.swift
    // 参照)。
    segmentsWrapper.onCancelHandler = { [weak api] in api?.cancelFromEventChannel() }
    downloadProgressWrapper.onCancelHandler = { [weak api] in api?.cancelFromEventChannel() }

    self.api = api
    self.segmentsWrapper = segmentsWrapper
    self.downloadProgressWrapper = downloadProgressWrapper

    // iOSの`FlutterPluginRegistrar.messenger()`はメソッド、macOSの
    // `FlutterPluginRegistrar.messenger`はプロパティであり宣言が異なる。
    #if os(macOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif

    OfflineSttHostApiSetup.setUp(binaryMessenger: messenger, api: api)
    SegmentsStreamHandler.register(with: messenger, streamHandler: segmentsWrapper)
    DownloadProgressStreamHandler.register(with: messenger, streamHandler: downloadProgressWrapper)
  }
}
