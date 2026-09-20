// EventChannelWrappers.kt
// Pigeon生成の`SegmentsStreamHandler`/`DownloadProgressStreamHandler`
// (Pigeon.g.kt)をさらにサブクラス化したもの。`segments` /
// `downloadProgress` の2本のEventChannel(design.md §2.3)を実装するための
// 薄いラッパーであり、Flutter側の購読状態(sink)を保持する以外のロジックは
// 持たない(offline_stt_darwinのEventChannelWrappers.swiftのKotlin版)。
//
// ## design.md §6「AndroidはRecognitionListenerのコールバックもメイン
// スレッドへ届くため、EventChannelへの転送はそのまま行える」の満たし方
// Darwinとは異なり、Speechフレームワークの非同期処理の完了スレッドが
// 不定なSwiftとは事情が違い、`SpeechRecognizer`はメインスレッドから生成・
// 操作する契約であり`RecognitionListener`のコールバックも同じスレッド
// (Flutterのプラットフォームスレッドと同一)へ届く。そのため本ラッパーは
// Darwin版のような明示的な`DispatchQueue.main.async`相当のdispatchを行わず、
// 呼び出し元がメインスレッド上で呼ぶ限りそのままsinkを呼ぶ。
package com.moongift.offline_stt_android

class SegmentsEventWrapper : SegmentsStreamHandler() {
    private var sink: PigeonEventSink<TranscriptSegment>? = null

    /**
     * EventChannel自体がキャンセルされた(Flutter側の購読解除・エンジン
     * 破棄等)場合に呼ばれる。design.md §3の排他制御等はDart側
     * (`recognition_session.dart`)が明示的に`cancel()`HostApiを呼ぶことで
     * 担保しているが、Dart側の後始末が何らかの理由で走らなかった場合の
     * 保険として、ネイティブ側のJobも合わせて止める。
     */
    var onCancelHandler: (() -> Unit)? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<TranscriptSegment>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        this.sink = null
        onCancelHandler?.invoke()
    }

    fun send(segment: TranscriptSegment) {
        sink?.success(segment)
    }

    fun sendError(error: AndroidTranscribeError) {
        sink?.error(error.pigeonCode.wireCode, error.detailMessage, null)
    }

    fun sendEndOfStream() {
        sink?.endOfStream()
    }
}

class DownloadProgressEventWrapper : DownloadProgressStreamHandler() {
    private var sink: PigeonEventSink<DownloadProgress>? = null

    /** [SegmentsEventWrapper.onCancelHandler]と同様の保険用フック。 */
    var onCancelHandler: (() -> Unit)? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<DownloadProgress>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        this.sink = null
        onCancelHandler?.invoke()
    }

    fun send(fraction: Double?, completed: Boolean) {
        sink?.success(DownloadProgress(fraction = fraction, completed = completed))
    }

    fun sendError(error: AndroidTranscribeError) {
        sink?.error(error.pigeonCode.wireCode, error.detailMessage, null)
    }

    fun sendEndOfStream() {
        sink?.endOfStream()
    }
}
