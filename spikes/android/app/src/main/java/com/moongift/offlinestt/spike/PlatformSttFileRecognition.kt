// PlatformSttFileRecognition.kt
//
// ML Kit GenAI の代替案として、Android 標準の `android.speech.SpeechRecognizer` で
// ファイル入力の文字起こしが成立するかを検証する。
//
// 検証する点は2つである。
//  A. ja-JP のオンデバイス言語パックを `triggerModelDownload()` で取得できるか
//  B. `RecognizerIntent.EXTRA_AUDIO_SOURCE`(ParcelFileDescriptor)でファイル入力が
//     受理されるか。design.md §4.3 の PFDパイプ + 実時間ポンプがそのまま流用できるか
//
// RECORD_AUDIO 権限は意図的に付与しない。EXTRA_AUDIO_SOURCE が効いていれば
// マイクは開かれないはずであり、逆に権限不足のエラーが出るなら
// 「EXTRA_AUDIO_SOURCE が効いていない」証拠になる。
package com.moongift.offlinestt.spike

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Handler
import android.os.ParcelFileDescriptor
import android.speech.ModelDownloadListener
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object PlatformSttFileRecognition {

    private const val LOCALE = "ja-JP"

    private fun baseIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, LOCALE)
            // requirements.md NFR-2: ネットワーク送信を行わない方針のためオフラインを要求する。
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }

    /** A: ja-JP のオンデバイス言語パックを取得する。 */
    fun downloadJaJp(context: Context, timeoutMs: Long = 180_000): String {
        SpikeLog.info("=== A: ja-JP オンデバイス言語パック取得開始 ===")
        val latch = CountDownLatch(1)
        var outcome = "(未確定)"
        Handler(context.mainLooper).post {
            try {
                val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                recognizer.triggerModelDownload(
                    baseIntent(),
                    Executors.newSingleThreadExecutor(),
                    object : ModelDownloadListener {
                        override fun onScheduled() {
                            SpikeLog.info("triggerModelDownload: onScheduled")
                        }

                        override fun onProgress(completedPercent: Int) {
                            SpikeLog.info("triggerModelDownload: onProgress $completedPercent%")
                        }

                        override fun onSuccess() {
                            outcome = "onSuccess"
                            SpikeLog.ok("triggerModelDownload: onSuccess")
                            latch.countDown()
                        }

                        override fun onError(error: Int) {
                            outcome = "onError($error)"
                            SpikeLog.ng("triggerModelDownload: onError $error")
                            latch.countDown()
                        }
                    },
                )
            } catch (t: Throwable) {
                outcome = "${t.javaClass.simpleName}: ${t.message}"
                SpikeLog.ng("triggerModelDownload で例外: $outcome")
                latch.countDown()
            }
        }
        if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) {
            outcome = "timeout(${timeoutMs}ms)"
            SpikeLog.warn("triggerModelDownload が ${timeoutMs}ms 以内に完了しなかった")
        }
        SpikeLog.info("=== A 終了: $outcome ===")
        return outcome
    }

    /** 現在の installedOnDeviceLanguages を再照会する。 */
    fun installedLanguages(context: Context, timeoutMs: Long = 15_000): List<String>? {
        val latch = CountDownLatch(1)
        var result: RecognitionSupport? = null
        Handler(context.mainLooper).post {
            try {
                val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                r.checkRecognitionSupport(
                    baseIntent(),
                    Executors.newSingleThreadExecutor(),
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                            result = recognitionSupport
                            latch.countDown()
                        }

                        override fun onError(error: Int) {
                            SpikeLog.ng("checkRecognitionSupport onError=$error")
                            latch.countDown()
                        }
                    },
                )
            } catch (t: Throwable) {
                SpikeLog.ng("checkRecognitionSupport で例外: ${t.message}")
                latch.countDown()
            }
        }
        latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return result?.installedOnDeviceLanguages
    }

    data class FileRecognitionResult(
        val accepted: Boolean,
        val finalText: String,
        val partialCount: Int,
        val errorCode: Int?,
        val elapsedMs: Long,
        val note: String,
    )

    /**
     * B: EXTRA_AUDIO_SOURCE によるファイル入力の受理可否を検証する。
     *
     * design.md §4.3 の PFDパイプ + 実時間ポンプをそのまま使う。
     * ML Kit GenAI では `AudioSource.fromPfd()` に渡していたものを、
     * ここでは `EXTRA_AUDIO_SOURCE` に載せ替えるだけである。
     */
    suspend fun recognizeFile(
        context: Context,
        clipId: String,
        timeoutMs: Long = 120_000,
    ): FileRecognitionResult {
        SpikeLog.info("=== B: EXTRA_AUDIO_SOURCE によるファイル入力検証開始 (clip=$clipId) ===")
        val started = System.currentTimeMillis()

        val pcm = withContext(Dispatchers.IO) {
            BaselineAssets.openWav(context, clipId).use {
                WavPcm.readMono16kHz16BitPcmOrThrow(it, "$clipId.wav")
            }
        }
        SpikeLog.ok("PCM読み込み: ${pcm.dataBytes.size}バイト, ${pcm.sampleRate}Hz, ${pcm.channels}ch, ${pcm.bitsPerSample}bit")

        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]

        val intent = baseIntent().apply {
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, pcm.channels)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, pcm.sampleRate)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }
        SpikeLog.info("EXTRA_AUDIO_SOURCE にパイプの読み取り側を設定した。RECORD_AUDIO 権限は付与していない。")

        val latch = CountDownLatch(1)
        // ポンプ完了後に stopListening() を呼ぶため、recognizer の参照を保持する。
        val recognizerRef = java.util.concurrent.atomic.AtomicReference<SpeechRecognizer?>(null)
        val finals = StringBuilder()
        var partials = 0
        var errorCode: Int? = null
        var sawReadyForSpeech = false

        Handler(context.mainLooper).post {
            try {
                val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                recognizerRef.set(recognizer)
                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: android.os.Bundle?) {
                        sawReadyForSpeech = true
                        SpikeLog.ok("onReadyForSpeech")
                    }

                    override fun onBeginningOfSpeech() = SpikeLog.info("onBeginningOfSpeech")
                    override fun onRmsChanged(rmsdB: Float) = Unit
                    override fun onBufferReceived(buffer: ByteArray?) = Unit
                    override fun onEndOfSpeech() = SpikeLog.info("onEndOfSpeech")

                    override fun onError(error: Int) {
                        errorCode = error
                        SpikeLog.ng("onError=$error (${errorName(error)})")
                        latch.countDown()
                    }

                    override fun onResults(results: android.os.Bundle?) {
                        // RESULTS_RECOGNITION が null になる事例を観測したため、
                        // バンドルに実際どのキーが入っているかを記録する。
                        SpikeLog.info("onResults keys=" + (results?.keySet()?.joinToString() ?: "(null bundle)"))
                        val texts = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val t = texts?.firstOrNull().orEmpty()
                        finals.append(t)
                        SpikeLog.ok("onResults: texts=" + texts + " -> \"" + t + "\"")
                        latch.countDown()
                    }

                    override fun onPartialResults(partialResults: android.os.Bundle?) {
                        partials++
                        val texts = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        SpikeLog.info("onPartialResults: ${texts?.firstOrNull().orEmpty()}")
                    }

                    override fun onEvent(eventType: Int, params: android.os.Bundle?) = Unit
                })
                recognizer.startListening(intent)
                SpikeLog.info("startListening() を呼び出した。")
            } catch (t: Throwable) {
                SpikeLog.ng("startListening で例外: ${t.javaClass.simpleName}: ${t.message}")
                latch.countDown()
            }
        }

        // 読み取り側は recognizer 側へ渡したので、こちらは書き込み側だけを扱う。
        runCatching { readSide.close() }
            .onFailure { SpikeLog.warn("readSide.close() 失敗: ${it.message}") }

        withContext(Dispatchers.IO) {
            FileOutputStream(writeSide.fileDescriptor).use { out ->
                RealtimePump.pump(
                    output = out,
                    pcmBytes = pcm.dataBytes,
                    sampleRateHz = pcm.sampleRate,
                    bitsPerSample = pcm.bitsPerSample,
                    channels = pcm.channels,
                )
            }
        }
        runCatching { writeSide.close() }
            .onFailure { SpikeLog.warn("writeSide.close() 失敗: ${it.message}") }
        SpikeLog.info("実時間ポンプ完了。パイプを閉じた。")

        // パイプを閉じただけでは確定結果が返らず onResults の texts が null に
        // なる事例を観測したため、明示的に stopListening() を呼んで入力終了を
        // 通知する。Web(design.md §4.1)で recognition.stop() が必須だったのと
        // 同じ構図である。
        Handler(context.mainLooper).post {
            runCatching {
                recognizerRef.get()?.stopListening()
                SpikeLog.info("stopListening() を呼び出した。")
            }.onFailure { SpikeLog.warn("stopListening() 失敗: ${it.message}") }
        }

        val done = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        val elapsed = System.currentTimeMillis() - started
        val note = when {
            !done -> "タイムアウト(${timeoutMs}ms)"
            errorCode != null -> "onError=${errorCode} (${errorName(errorCode!!)})"
            else -> "onResults 受信"
        }
        SpikeLog.info("=== B 終了: $note, elapsed=${elapsed}ms, partials=$partials, readyForSpeech=$sawReadyForSpeech ===")
        return FileRecognitionResult(
            accepted = done && errorCode == null,
            finalText = finals.toString(),
            partialCount = partials,
            errorCode = errorCode,
            elapsedMs = elapsed,
            note = note,
        )
    }

    private fun errorName(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "ERROR_AUDIO"
        SpeechRecognizer.ERROR_CLIENT -> "ERROR_CLIENT"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "ERROR_INSUFFICIENT_PERMISSIONS"
        SpeechRecognizer.ERROR_NETWORK -> "ERROR_NETWORK"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "ERROR_NETWORK_TIMEOUT"
        SpeechRecognizer.ERROR_NO_MATCH -> "ERROR_NO_MATCH"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "ERROR_RECOGNIZER_BUSY"
        SpeechRecognizer.ERROR_SERVER -> "ERROR_SERVER"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "ERROR_SPEECH_TIMEOUT"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "ERROR_LANGUAGE_NOT_SUPPORTED"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "ERROR_LANGUAGE_UNAVAILABLE"
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "ERROR_CANNOT_CHECK_SUPPORT"
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "ERROR_SERVER_DISCONNECTED"
        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "ERROR_TOO_MANY_REQUESTS"
        else -> "UNKNOWN($code)"
    }
}
