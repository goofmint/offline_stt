// PlatformSttHarness.kt
// 代替案調査(Android 標準 SpeechRecognizer)の本体。PlatformSttProbe.kt が照会専用なのに対し、
// 本ファイルは「A: ja-JP オンデバイス言語パックの取得」「B: EXTRA_AUDIO_SOURCE によるファイル入力の
// 受理確認」「C: 認識精度確認」を行う。design.md §4.3 の PFDパイプ + 実時間ポンプ方式を
// android.speech.SpeechRecognizer 向けに流用できるかを確かめることが目的である。
//
// 既存の ML Kit GenAI 用コード(RecognitionHarness.kt 等)は変更しない。本ファイルは完全に独立している。
//
// フォールバック処理は書かない: 想定外の状態はすべて例外またはログとして明確に顕在化させる。
// RECORD_AUDIO 権限は付与しない(AndroidManifest.xml 参照。マイク入力は対象外)。
package com.moongift.offlinestt.spike

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.ModelDownloadListener
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.concurrent.Executors
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

object PlatformSttHarness {

    // ===== A: ja-JP オンデバイス言語パックの取得 (triggerModelDownload) =====

    data class ModelDownloadResult(
        val scheduled: Boolean,
        val success: Boolean,
        val lastProgress: Int?,
        val errorCode: Int?,
        val timedOut: Boolean,
    )

    /**
     * `SpeechRecognizer.triggerModelDownload(intent, executor, listener)` で ja-JP の
     * オンデバイス言語パックのダウンロードを試みる (API 34+ で追加された ModelDownloadListener 版)。
     * `javap` で確認済み: `android.jar` (API 36) に両オーバーロードが存在する。
     *
     * 取得できたかどうかは呼び出し元が `PlatformSttProbe.run()` を再実行し
     * `installedOnDeviceLanguages` に "ja-JP" が現れるかで判定すること(このメソッド単体では判定しない)。
     */
    suspend fun triggerJaJpModelDownload(context: Context, timeoutMs: Long = 60_000): ModelDownloadResult =
        coroutineScope {
            SpikeLog.info("=== A: ja-JP オンデバイス言語パックのダウンロード開始 (triggerModelDownload) ===")

            var scheduled = false
            var success = false
            var lastProgress: Int? = null
            var errorCode: Int? = null
            val done = CompletableDeferred<Unit>()

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ja-JP")
            }

            val main = Handler(Looper.getMainLooper())
            main.post {
                try {
                    val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                    recognizer.triggerModelDownload(
                        intent,
                        Executors.newSingleThreadExecutor(),
                        object : ModelDownloadListener {
                            override fun onScheduled() {
                                scheduled = true
                                SpikeLog.info("triggerModelDownload: onScheduled()")
                            }

                            override fun onProgress(progress: Int) {
                                lastProgress = progress
                                SpikeLog.info("triggerModelDownload: onProgress($progress)")
                            }

                            override fun onSuccess() {
                                success = true
                                SpikeLog.ok("triggerModelDownload: onSuccess()")
                                if (!done.isCompleted) done.complete(Unit)
                            }

                            override fun onError(error: Int) {
                                errorCode = error
                                SpikeLog.ng("triggerModelDownload: onError($error)")
                                if (!done.isCompleted) done.complete(Unit)
                            }
                        },
                    )
                } catch (t: Throwable) {
                    SpikeLog.ng("triggerModelDownload() 呼び出しで例外: ${t.javaClass.simpleName}: ${t.message}")
                    if (!done.isCompleted) done.complete(Unit)
                }
            }

            val timedOut = withTimeoutOrNull(timeoutMs) { done.await() } == null
            if (timedOut) {
                SpikeLog.warn("triggerJaJpModelDownload: ${timeoutMs}ms 以内に onSuccess/onError が到達しなかった。")
            }

            SpikeLog.info(
                "=== A: ダウンロード試行終了: scheduled=$scheduled, success=$success, " +
                    "lastProgress=$lastProgress, errorCode=$errorCode, timedOut=$timedOut ===",
            )
            ModelDownloadResult(scheduled, success, lastProgress, errorCode, timedOut)
        }

    // ===== B: EXTRA_AUDIO_SOURCE によるファイル入力の受理確認 =====

    /** RecognitionListener の各コールバックの発生順序と内容を記録する(RESULTS.md への転記用)。 */
    data class FileInputProbeResult(
        val events: List<String>,
        val resultsTexts: List<String>?,
        val partialTexts: List<String>?,
        val errorCode: Int?,
        val timedOut: Boolean,
        val pumpBytesSent: Int,
        val pumpElapsedMs: Long,
    )

    /**
     * `RecognizerIntent.EXTRA_AUDIO_SOURCE` (PFD) 経由でファイル入力を受理するかを確認する。
     * design.md §4.3 の PFDパイプ + 実時間ポンプ方式をそのまま流用する
     * (`ParcelFileDescriptor.createPipe()` + `RealtimePump.pump()`)。
     *
     * `EXTRA_PREFER_OFFLINE = true` を設定する (NFR-2: オフライン方針)。
     * RECORD_AUDIO 権限は付与していないため、もしファイル入力が無視されマイクが開かれた場合は
     * 権限不足のエラー(`onError` の `ERROR_INSUFFICIENT_PERMISSIONS` 等)が発生するはずであり、
     * それ自体を「EXTRA_AUDIO_SOURCE が効いていない」証拠として記録する。
     */
    suspend fun runFileInputProbe(
        context: Context,
        clip: BaselineClip,
        firstEventTimeoutMs: Long = 20_000,
    ): FileInputProbeResult = coroutineScope {
        SpikeLog.info("=== B: EXTRA_AUDIO_SOURCE ファイル入力受理確認開始 (clip=${clip.clipId}) ===")

        val pcm = BaselineAssets.openWav(context, clip.clipId).use { input ->
            WavPcm.readMono16kHz16BitPcmOrThrow(input, "${clip.clipId}.wav")
        }

        SpikeLog.info("ParcelFileDescriptor.createPipe() を呼び出す。")
        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]

        val events = mutableListOf<String>()
        var resultsTexts: List<String>? = null
        var partialTexts: List<String>? = null
        var errorCode: Int? = null
        val firstEvent = CompletableDeferred<Unit>()

        fun recordEvent(label: String) {
            events += label
            SpikeLog.info("[RecognitionListener] $label")
            if (!firstEvent.isCompleted) firstEvent.complete(Unit)
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, clip.locale)
            // requirements.md NFR-2: オフライン方針。
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            // ファイル入力 (design.md §4.3 の PFDパイプをそのまま流用)。
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, pcm.channels)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, pcm.sampleRate)
        }

        var recognizer: SpeechRecognizer? = null
        val main = Handler(Looper.getMainLooper())
        main.post {
            try {
                val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                recognizer = r
                r.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) = recordEvent("onReadyForSpeech(params=$params)")
                    override fun onBeginningOfSpeech() = recordEvent("onBeginningOfSpeech()")
                    override fun onRmsChanged(rmsdB: Float) {
                        // 高頻度で来るため events には積まずログのみ (design.mdの「事実をログするのみ」方針)。
                        SpikeLog.info("[RecognitionListener] onRmsChanged($rmsdB)")
                    }
                    override fun onBufferReceived(buffer: ByteArray?) =
                        recordEvent("onBufferReceived(size=${buffer?.size})")
                    override fun onEndOfSpeech() = recordEvent("onEndOfSpeech()")
                    override fun onError(error: Int) {
                        errorCode = error
                        recordEvent("onError(error=$error, name=${errorName(error)})")
                    }
                    override fun onResults(results: Bundle?) {
                        val texts = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        resultsTexts = texts
                        recordEvent("onResults(texts=$texts)")
                    }
                    override fun onPartialResults(partialResults: Bundle?) {
                        val texts = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        partialTexts = texts
                        recordEvent("onPartialResults(texts=$texts)")
                    }
                    override fun onEvent(eventType: Int, params: Bundle?) =
                        recordEvent("onEvent(eventType=$eventType)")
                })
                SpikeLog.info("startListening() を呼び出す (EXTRA_AUDIO_SOURCE 付き)。")
                r.startListening(intent)
            } catch (t: Throwable) {
                SpikeLog.ng("startListening() 呼び出しで例外: ${t.javaClass.simpleName}: ${t.message}")
                events += "EXCEPTION: ${t.javaClass.simpleName}: ${t.message}"
                if (!firstEvent.isCompleted) firstEvent.complete(Unit)
            }
        }

        var pumpBytesSent = 0
        var pumpElapsedMs = 0L
        val pumpJob = launch(Dispatchers.IO) {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { out ->
                    val result = RealtimePump.pump(
                        output = out,
                        pcmBytes = pcm.dataBytes,
                        sampleRateHz = pcm.sampleRate,
                        bitsPerSample = pcm.bitsPerSample,
                        channels = pcm.channels,
                    )
                    pumpBytesSent = result.totalBytesSent
                    pumpElapsedMs = result.elapsedMs
                }
            } catch (e: Exception) {
                SpikeLog.warn("B: 実時間ポンプでエラー(読み取り側が既に閉じた可能性): ${e.message}")
            }
        }

        val timedOut = withTimeoutOrNull(firstEventTimeoutMs) { firstEvent.await() } == null
        if (timedOut) {
            SpikeLog.ng(
                "B: ${firstEventTimeoutMs}ms 以内に RecognitionListener の最初のコールバックが" +
                    "到達しなかった。",
            )
        } else {
            // onResults / onError が来るまでもう少し待つ (最初のコールバックが onReadyForSpeech 等の
            // 場合があるため)。design.mdの joinTimeoutMs と同様の考え方。
            withTimeoutOrNull(firstEventTimeoutMs) {
                while (resultsTexts == null && errorCode == null) {
                    kotlinx.coroutines.delay(200)
                }
            }
        }

        runCatching { pumpJob.cancelAndJoin() }

        // パイプへの書き込みが終わっただけでは確定結果が返らず、onResults の
        // texts が null になる事例を観測した。明示的に stopListening() を呼んで
        // 入力終了を通知し、確定結果が返るかを確かめる。Web(design.md §4.1)で
        // recognition.stop() が必須だったのと同じ構図である。
        val stopLatch = java.util.concurrent.CountDownLatch(1)
        main.post {
            runCatching {
                recognizer?.stopListening()
                SpikeLog.info("stopListening() を呼び出した。")
            }.onFailure { SpikeLog.warn("stopListening() 失敗: ${it.message}") }
            stopLatch.countDown()
        }
        runCatching { stopLatch.await(3, java.util.concurrent.TimeUnit.SECONDS) }
        // 確定結果が届く余地を与える。
        kotlinx.coroutines.delay(8_000)
        SpikeLog.info("stopListening() 後の resultsTexts=$resultsTexts")

        runCatching { recognizer?.destroy() }
            .onFailure { SpikeLog.warn("recognizer.destroy() 失敗: ${it.message}") }
        runCatching { readSide.close() }
            .onFailure { SpikeLog.warn("readSide.close() 失敗: ${it.message}") }
        runCatching { writeSide.close() }
            .onFailure { SpikeLog.warn("writeSide.close() 失敗: ${it.message}") }

        SpikeLog.info(
            "=== B: 受理確認終了: events=$events, resultsTexts=$resultsTexts, errorCode=$errorCode, " +
                "pumpBytesSent=$pumpBytesSent, pumpElapsedMs=$pumpElapsedMs ===",
        )

        FileInputProbeResult(
            events = events,
            resultsTexts = resultsTexts,
            partialTexts = partialTexts,
            errorCode = errorCode,
            timedOut = timedOut,
            pumpBytesSent = pumpBytesSent,
            pumpElapsedMs = pumpElapsedMs,
        )
    }

    /** SpeechRecognizer.ERROR_* 定数名への変換 (ログ可読性のため)。 */
    fun errorName(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "ERROR_AUDIO"
        SpeechRecognizer.ERROR_CLIENT -> "ERROR_CLIENT"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "ERROR_INSUFFICIENT_PERMISSIONS"
        SpeechRecognizer.ERROR_NETWORK -> "ERROR_NETWORK"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "ERROR_NETWORK_TIMEOUT"
        SpeechRecognizer.ERROR_NO_MATCH -> "ERROR_NO_MATCH"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "ERROR_RECOGNIZER_BUSY"
        SpeechRecognizer.ERROR_SERVER -> "ERROR_SERVER"
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "ERROR_SERVER_DISCONNECTED"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "ERROR_SPEECH_TIMEOUT"
        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "ERROR_TOO_MANY_REQUESTS"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "ERROR_LANGUAGE_NOT_SUPPORTED"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "ERROR_LANGUAGE_UNAVAILABLE"
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "ERROR_CANNOT_CHECK_SUPPORT"
        SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS -> "ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS"
        else -> "UNKNOWN($code)"
    }
}
