// OfflineSttApiImpl.kt
// `OfflineSttHostApi`(Pigeon生成、Pigeon.g.kt)の実装本体。
// design.md §4.3(wt73版)、requirements.md FR-1〜FR-3 FR-6(Issue #43〜#48)
// に対応する(Darwin実装のOfflineSttApiImpl.swiftのKotlin版)。
//
// `checkModel`/`downloadModel`/`transcribeFile`/`cancel`いずれも
// `SpeechRecognizer.createOnDeviceSpeechRecognizer()`を要求するため、
// design.md §4.3(wt73版)注記9のとおりメインスレッドから呼び出す必要がある。
// `OfflineSttHostApi`のメソッドはFlutterのプラットフォームスレッド
// (Android上はメインスレッドと同一)から呼ばれるため、追加のスレッド切替は
// 不要である。
package com.moongift.offline_stt

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class OfflineSttApiImpl(
    private val context: Context,
    private val segmentsWrapper: SegmentsEventWrapper,
    private val downloadProgressWrapper: DownloadProgressEventWrapper,
) : OfflineSttHostApi {

    // Dispatchers.Main.immediate: design.md §4.3(wt73版)注記9のとおり
    // SpeechRecognizerはメインスレッドから操作する必要があるため。
    // SupervisorJob: checkModel呼び出しがdownloadModel/transcribeFileの
    // 失敗で巻き添えにならないようにする。
    private val mainScope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())

    private var currentTranscriptionJob: Job? = null
    private var currentDownloadJob: Job? = null

    override fun checkModel(locale: String, callback: (Result<ModelState>) -> Unit) {
        mainScope.launch {
            // **例外を必ず callback へ渡す。** `mainScope.launch` の中で
            // 例外が外へ抜けると、Pigeon のコールバックが呼ばれないまま
            // コルーチンが異常終了し、Dart 側は応答を待ち続けるか
            // アプリごと落ちる(実機で確認した)。
            try {
                callback(Result.success(ModelAvailability.checkModel(context, locale)))
            } catch (e: CancellationException) {
                throw e
            } catch (e: AndroidTranscribeError) {
                callback(Result.failure(e.toFlutterError()))
            } catch (e: Exception) {
                callback(
                    Result.failure(
                        AndroidTranscribeError.PlatformError("$e").toFlutterError(),
                    ),
                )
            }
        }
    }

    override fun supportedLocales(callback: (Result<List<String>>) -> Unit) {
        mainScope.launch {
            // `checkModel` と同じ理由で例外を必ず callback へ渡す。
            // `mainScope.launch` の中で例外が外へ抜けると、Pigeon の
            // コールバックが呼ばれないままコルーチンが異常終了し、Dart 側は
            // 応答を待ち続けるかアプリごと落ちる。
            try {
                callback(Result.success(ModelAvailability.supportedLocales(context)))
            } catch (e: CancellationException) {
                throw e
            } catch (e: AndroidTranscribeError) {
                callback(Result.failure(e.toFlutterError()))
            } catch (e: Exception) {
                callback(
                    Result.failure(
                        AndroidTranscribeError.PlatformError("$e").toFlutterError(),
                    ),
                )
            }
        }
    }

    override fun downloadModel(locale: String) {
        currentDownloadJob?.cancel()
        currentDownloadJob = mainScope.launch { runDownload(locale) }
    }

    override fun transcribeFile(request: TranscribeRequest) {
        // design.md §3のセッション排他(v1では同時1本まで)はDart側
        // `TranscribeSessionGuard`が担うため、通常この時点で前のJobが
        // 生きていることはない。念のため多重起動を防ぐ。
        currentTranscriptionJob?.cancel()
        currentTranscriptionJob = mainScope.launch { runTranscription(request) }
    }

    override fun cancel() {
        currentTranscriptionJob?.cancel()
        currentDownloadJob?.cancel()
    }

    /**
     * `segments` EventChannel自体がキャンセルされた場合の保険
     * (`EventChannelWrappers.kt`のドキュメントコメント参照)。
     *
     * 停止するのは文字起こしJobのみである。2本のEventChannelは独立して
     * いるため、片方の購読解除でもう片方を巻き添えにしてはならない
     * (例: ja-JPの文字起こし中にen-USのダウンロードStreamの購読を解除
     * しても、文字起こしは継続しなければならない)。明示的な[cancel]は
     * 従来どおり両方を停止する。
     */
    fun cancelTranscriptionFromEventChannel() {
        currentTranscriptionJob?.cancel()
    }

    /**
     * `downloadProgress` EventChannel自体がキャンセルされた場合の保険。
     * 停止するのはダウンロードJobのみである(理由は
     * [cancelTranscriptionFromEventChannel]のコメント参照)。
     */
    fun cancelDownloadFromEventChannel() {
        currentDownloadJob?.cancel()
    }

    private suspend fun runDownload(locale: String) {
        // design.md §3細則3: downloadable以外で呼ばれた場合は状態を変化
        // させず何もemitせず完了する。
        val state = ModelAvailability.checkModel(context, locale)
        if (state != ModelState.DOWNLOADABLE) {
            downloadProgressWrapper.sendEndOfStream()
            return
        }

        downloadProgressWrapper.send(fraction = null, completed = false)
        try {
            ModelAcquisition.run(context, locale) { fraction, completed ->
                downloadProgressWrapper.send(fraction = fraction, completed = completed)
            }
            downloadProgressWrapper.sendEndOfStream()
        } catch (e: CancellationException) {
            downloadProgressWrapper.sendError(AndroidTranscribeError.Cancelled)
            downloadProgressWrapper.sendEndOfStream()
        } catch (e: AndroidTranscribeError) {
            downloadProgressWrapper.sendError(e)
            downloadProgressWrapper.sendEndOfStream()
        } catch (e: Exception) {
            downloadProgressWrapper.sendError(AndroidTranscribeError.PlatformError("$e"))
            downloadProgressWrapper.sendEndOfStream()
        }
    }

    private suspend fun runTranscription(request: TranscribeRequest) {
        // design.md §2.2: `playbackRate`はWeb専用オプションであり、
        // Androidでは無視する。PigeonスキーマのTranscribeRequestには
        // 現行ブランチの時点でplaybackRateフィールド自体が存在しない
        // (Darwin実装と同じ事情)ため、path/localeのみを使用する
        // 形で自然に無視される。
        try {
            RecognitionSession.run(context, request, segmentsWrapper)
        } catch (e: CancellationException) {
            // RecognitionSession.run()内のinvokeOnCancellationで既に
            // Cancelledエラーを送出済みのため、ここでは何もしない。
        } catch (e: AndroidTranscribeError) {
            segmentsWrapper.sendError(e)
        } catch (e: Exception) {
            segmentsWrapper.sendError(AndroidTranscribeError.PlatformError("$e"))
        }
    }
}
