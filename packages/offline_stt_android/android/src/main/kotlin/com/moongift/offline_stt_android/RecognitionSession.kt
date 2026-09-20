// RecognitionSession.kt
// requirements.md FR-3、Issue #44〜#48。design.md §4.3(wt73版)の
// パイプライン全体を統括する:
//   入力ファイル
//     → MediaExtractor + MediaCodec でデコード(AudioDecoder、Issue #44)
//     → リサンプリング(16kHz・モノラル・16-bit PCM、Resampler、Issue #45)
//     → ParcelFileDescriptor.createPipe()
//     → 書き込み側: 実時間ポンプ(RealtimePump、Issue #46)
//     → Intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, 読み取り側)
//     → SpeechRecognizer.createOnDeviceSpeechRecognizer() の
//       startListening() → RecognitionListener(Issue #47)
//     → EventChannel へ転送
//
// spikes/android/app/src/main/java/com/moongift/offlinestt/spike/
// PlatformSttHarness.kt(runFileInputProbe)を移植の出発点とした。
package com.moongift.offline_stt_android

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

object RecognitionSession {
    /**
     * @throws AndroidTranscribeError デコード・認識のいずれかの失敗時。
     *   キャンセル時は[kotlinx.coroutines.CancellationException]が投げられる
     *   前に、内部で`segmentsWrapper.sendError(AndroidTranscribeError.Cancelled)`
     *   が呼ばれている(design.md §4.3(wt73版)「キャンセル時はパイプclose
     *   → stopListening() → destroy()」)。
     */
    suspend fun run(
        context: Context,
        request: TranscribeRequest,
        segmentsWrapper: SegmentsEventWrapper,
    ) = coroutineScope {
        // Issue #44: MediaExtractor + MediaCodecでデコード。ネイティブの
        // サンプルレート・チャンネル数のまま(design.md §4.3(wt73版)の実測
        // どおりMediaCodecはサンプルレート変換・ダウンミックスを行わない)。
        val decoded = withContext(Dispatchers.IO) { AudioDecoder.decodeToPcm16(request.path) }

        // Issue #45: 16kHz・モノラルへのリサンプリング(design.md §4.3
        // (wt73版)「リサンプリングは必須」)。
        val resampled = withContext(Dispatchers.Default) {
            Resampler.resampleToMono16k(
                pcm = decoded.pcm,
                sourceSampleRate = decoded.sampleRate,
                sourceChannelCount = decoded.channelCount,
            )
        }

        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]

        // Issue #46: 実時間ポンプ。design.md §6のとおりDispatchers.IO上で
        // 実行する。coroutineScopeの子として起動するため、親(このJob)が
        // キャンセルされれば自動的に道連れでキャンセルされる。
        val pumpJob: Job = launch(Dispatchers.IO) {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { out ->
                    RealtimePump.pump(
                        output = out,
                        pcmBytes = resampled,
                        sampleRateHz = 16_000,
                        bitsPerSample = 16,
                        channels = 1,
                    )
                }
            } catch (e: IOException) {
                // design.md §4.3(wt73版)「キャンセル時はパイプclose」の結果
                // として読み取り側(SpeechRecognizer側)が先に閉じられ、
                // 書き込みがIOExceptionになる経路(cancel実行時に発生し
                // うる)。エラーとして扱わず黙って終える。
            }
        }
        // 本体(`launch`のブロック)が一度も実行されないまま親スコープが
        // キャンセルされた場合、`use`に入らないため書き込み側FDが閉じられない。
        // `invokeOnCancellation`は読み取り側しか閉じないので、開始直後に
        // キャンセルされるとパイプの書き込み側FDが残る。Jobの完了フックで
        // 確実に閉じる(二重closeは`runCatching`で無害に握る)。
        pumpJob.invokeOnCompletion { runCatching { writeSide.close() } }

        // design.md §4.3(wt73版)注記9: SpeechRecognizerはメインスレッドから
        // 生成・操作する必要がある。本関数はOfflineSttApiImpl経由で
        // Dispatchers.Main上から呼ばれる前提である。
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        try {
            awaitRecognition(recognizer, readSide, request.locale, segmentsWrapper, pumpJob)
        } finally {
            runCatching { readSide.close() }
        }
    }

    private suspend fun awaitRecognition(
        recognizer: SpeechRecognizer,
        readSide: ParcelFileDescriptor,
        locale: String,
        segmentsWrapper: SegmentsEventWrapper,
        pumpJob: Job,
    ): Unit = suspendCancellableCoroutine { continuation ->
        // design.md §4.3(wt73版)「onResults()のtextsがnullになる。その場合は
        // 直前のonPartialResults()の最上位候補を確定結果として採用する」。
        var lastPartialTopCandidate: String? = null
        var settled = false

        recognizer.setRecognitionListener(
            object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}

                override fun onBeginningOfSpeech() {}

                override fun onRmsChanged(rmsdB: Float) {}

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {}

                override fun onError(error: Int) {
                    if (settled) return
                    settled = true
                    val mapped = ErrorMapping.map(error)
                    segmentsWrapper.sendError(mapped)
                    runCatching { recognizer.destroy() }
                    if (continuation.isActive) continuation.resumeWith(Result.success(Unit))
                }

                override fun onResults(results: Bundle?) {
                    if (settled) return
                    settled = true
                    // Issue #47/#48。design.md §4.3(wt73版)の実測どおり
                    // texts が null になり得る。その場合は直前の
                    // onPartialResults() の最上位候補を確定結果として採用
                    // する。これは隠すべき不具合ではなく、design.mdが明記
                    // する正規の仕様として扱う(Web実装が isFinal が立たない
                    // 場合に末尾interimを採用したのと同じ構図)。
                    val texts = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val finalText = texts?.firstOrNull() ?: lastPartialTopCandidate
                    if (finalText != null) {
                        segmentsWrapper.send(TranscriptSegment(text = finalText, isFinal = true))
                    }
                    segmentsWrapper.sendEndOfStream()
                    runCatching { recognizer.destroy() }
                    if (continuation.isActive) continuation.resumeWith(Result.success(Unit))
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    if (settled) return
                    val texts =
                        partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val top = texts?.firstOrNull() ?: return
                    lastPartialTopCandidate = top
                    segmentsWrapper.send(TranscriptSegment(text = top, isFinal = false))
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            },
        )

        continuation.invokeOnCancellation {
            if (settled) return@invokeOnCancellation
            settled = true
            // Issue #48。design.md §4.3(wt73版)「キャンセル時はパイプclose
            // → stopListening() → destroy()」の順序どおり実施する。
            runCatching { pumpJob.cancel() }
            runCatching { readSide.close() }
            runCatching { recognizer.stopListening() }
            runCatching { recognizer.destroy() }
            segmentsWrapper.sendError(AndroidTranscribeError.Cancelled)
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            // requirements.md NFR-2: オフライン方針。
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            // design.md §4.3(wt73版): EXTRA_AUDIO_SOURCEには
            // EXTRA_AUDIO_SOURCE_CHANNEL_COUNT(=1)・_ENCODING(=PCM_16BIT)・
            // _SAMPLING_RATE(=16000)の3つを必ず併せて渡す。RECORD_AUDIO
            // 権限は不要(AndroidManifest.xmlには追加しない)。
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16_000)
        }
        recognizer.startListening(intent)
    }
}
