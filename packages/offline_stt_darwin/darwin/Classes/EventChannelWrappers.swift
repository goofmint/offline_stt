// EventChannelWrappers.swift
// Pigeon生成の`SegmentsStreamHandler`/`DownloadProgressStreamHandler`
// (Pigeon.g.swift、いずれも`PigeonEventChannelWrapper<T>`のサブクラス)を
// さらにサブクラス化したもの。`segments` / `downloadProgress` の2本の
// EventChannel(design.md §2.3)を実装するための薄いラッパーであり、
// Flutter側の購読状態(sink)を保持する以外のロジックは持たない。
//
// `SegmentsStreamHandler.register(with:streamHandler:)`等の静的登録メソッド
// (Pigeon.g.swift)は、汎用の`PigeonEventChannelWrapper<TranscriptSegment>`
// ではなく`SegmentsStreamHandler`型そのものを要求するため、本ファイルの
// クラスは`PigeonEventChannelWrapper<T>`ではなくこれらの具象クラスを
// 直接継承している。
//
// ## design.md §6「FlutterEventSinkへはmain actor経由で送る」の満たし方
// `PigeonEventSink.success/error/endOfStream`はFlutterEventSinkをそのまま
// 呼ぶため、メインスレッド(Flutterのプラットフォームスレッド)から呼ぶ
// 必要がある。Speechフレームワークの非同期処理(AsyncSequence消費・KVO
// 通知)がどのスレッドで完了するかは保証されないため、本ラッパーの送出
// メソッドは常に`DispatchQueue.main.async`を介して送出する。
// (Swift 5言語モード(`offline_stt_darwin.podspec`)のため`@MainActor`
// アイソレーションではなくGCDで統一している。Flutterのプラットフォーム
// スレッドはメインスレッドと同一であるため、動作上の意味は`@MainActor`と
// 変わらない。)
#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif
import Foundation

final class SegmentsEventWrapper: SegmentsStreamHandler {
  private var sink: PigeonEventSink<TranscriptSegment>?

  /// 当該EventChannel自体がキャンセルされた(Flutter側の購読解除・エンジン
  /// 破棄等)場合に呼ばれる。design.md §3の「2. 2本目のセッションの拒否
  /// 方法」等はDart側(`recognition_session.dart`)が明示的に`cancel()`
  /// HostApiを呼ぶことで担保しているが、Dart側の後始末が何らかの理由で
  /// 走らなかった場合の保険として、ネイティブ側のTaskも合わせて止める。
  var onCancelHandler: (() -> Void)?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<TranscriptSegment>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    self.sink = nil
    onCancelHandler?()
  }

  func send(_ segment: TranscriptSegment) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.success(segment)
    }
  }

  func sendError(_ error: DarwinTranscribeError) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.error(
        code: error.pigeonCode.wireCode,
        message: error.detailMessage,
        details: nil
      )
    }
  }

  func sendEndOfStream() {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.endOfStream()
    }
  }
}

final class DownloadProgressEventWrapper: DownloadProgressStreamHandler {
  private var sink: PigeonEventSink<DownloadProgress>?

  /// `SegmentsEventWrapper.onCancelHandler`と同様の保険用フック。
  var onCancelHandler: (() -> Void)?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<DownloadProgress>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    self.sink = nil
    onCancelHandler?()
  }

  func send(fraction: Double?, completed: Bool) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.success(DownloadProgress(fraction: fraction, completed: completed))
    }
  }

  func sendError(_ error: DarwinTranscribeError) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.error(
        code: error.pigeonCode.wireCode,
        message: error.detailMessage,
        details: nil
      )
    }
  }

  func sendEndOfStream() {
    DispatchQueue.main.async { [weak self] in
      self?.sink?.endOfStream()
    }
  }
}
