package com.moongift.offline_stt_android

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * offline_stt のAndroidネイティブ側エントリポイント。
 *
 * Pigeon生成コード(`pigeons/offline_stt_events.dart` から生成、Issue #24)の
 * `OfflineSttHostApi`(MethodChannel)・`OfflineSttStreamEvents`
 * (EventChannel、design.md §2.3)を、`OfflineSttApiImpl`
 * (標準android.speech.SpeechRecognizer連携の実装本体、design.md §4.3
 * (wt73版)、Issue #42〜#49)と結びつける(offline_stt_darwinの
 * OfflineSttDarwinPlugin.swiftのKotlin版)。
 */
class OfflineSttAndroidPlugin : FlutterPlugin {
    private var api: OfflineSttApiImpl? = null
    private var segmentsWrapper: SegmentsEventWrapper? = null
    private var downloadProgressWrapper: DownloadProgressEventWrapper? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        val segments = SegmentsEventWrapper()
        val downloadProgress = DownloadProgressEventWrapper()
        val apiImpl = OfflineSttApiImpl(
            context = binding.applicationContext,
            segmentsWrapper = segments,
            downloadProgressWrapper = downloadProgress,
        )
        // EventChannel自体がキャンセルされた場合の保険(EventChannelWrappers.kt参照)。
        segments.onCancelHandler = { apiImpl.cancelFromEventChannel() }
        downloadProgress.onCancelHandler = { apiImpl.cancelFromEventChannel() }

        api = apiImpl
        segmentsWrapper = segments
        downloadProgressWrapper = downloadProgress

        OfflineSttHostApi.setUp(messenger, apiImpl)
        SegmentsStreamHandler.register(messenger, segments)
        DownloadProgressStreamHandler.register(messenger, downloadProgress)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OfflineSttHostApi.setUp(binding.binaryMessenger, null)
        api?.cancel()
        api = null
        segmentsWrapper = null
        downloadProgressWrapper = null
    }
}
