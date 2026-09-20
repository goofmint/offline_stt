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
//
// ## ストリーミング化(CodeRabbit指摘「Heavy lift」への対応)
// 上の矢印は以前「各段を全量バッファで受け渡す」実装だった。すなわち
// デコード結果のPCM全長(48kHz・ステレオ・60分で約691MB)を保持したまま
// リサンプリングを行い、その中間配列も加わって合計1.7GB規模のヒープを要求
// していた。APIとして入力長・入力サイズの上限を定めていない以上、これは
// 現実的な入力でOOMになる。
// 現在は [streamIntoPipe] のとおり **デコード → リサンプリング → パイプへの
// 送出をチャンク単位で行う**。同時に生存するのは
//   - MediaCodec の出力チャンク1つ(実測で数KB〜十数KB)
//   - StreamingResampler が保持する未消費の入力モノラルサンプル
//     (1チャンク分 + 補間に必要な数サンプル)
//   - RealtimePump.Pacer の送出バッファ(3,200バイト固定)
// だけであり、ピークメモリは音声の長さに依存しない。
package com.moongift.offline_stt_android

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

object RecognitionSession {
    /** 認識セッションが要求するPCM形式(design.md §4.3(wt73版))。 */
    private const val TARGET_SAMPLE_RATE = 16_000
    private const val TARGET_BITS_PER_SAMPLE = 16
    private const val TARGET_CHANNELS = 1

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
        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]

        // デコード・リサンプリング側で起きた失敗を[awaitRecognition]へ伝える。
        // ストリーミング化により、これらの失敗は「認識開始前」ではなく
        // 「認識待機中」に起こり得るようになった。子Jobの失敗は親
        // (coroutineScope)をキャンセルするため、対策をしないと
        // `invokeOnCancellation` が本当の失敗理由を Cancelled で上書きして
        // しまう。失敗を記録しておき、Cancelled を送らないようにする。
        val pipelineFailure = AtomicReference<AndroidTranscribeError?>(null)

        // Issue #44〜#46: デコード→リサンプリング→実時間ポンプ。design.md §6の
        // とおりDispatchers.IO上で実行する。coroutineScopeの子として起動する
        // ため、親(このJob)がキャンセルされれば自動的に道連れでキャンセル
        // される。
        //
        // リサンプリングは旧実装では Dispatchers.Default で実行していたが、
        // ストリーミング化に伴いデコードと同じ IO スレッド上で行う。1回あたり
        // 数KBの整数演算であり、実時間ポンプの100ms周期に対して無視できる。
        val pumpJob: Job = launch(Dispatchers.IO) {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { out ->
                    streamIntoPipe(request.path, out)
                }
            } catch (e: IOException) {
                // design.md §4.3(wt73版)「キャンセル時はパイプclose」の結果
                // として読み取り側(SpeechRecognizer側)が先に閉じられ、
                // 書き込みがIOExceptionになる経路(cancel実行時に発生し
                // うる)。エラーとして扱わず黙って終える。
            } catch (e: AndroidTranscribeError) {
                pipelineFailure.set(e)
                throw e
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
            awaitRecognition(
                recognizer,
                readSide,
                request.locale,
                segmentsWrapper,
                pumpJob,
                pipelineFailure,
            )
        } finally {
            runCatching { readSide.close() }
        }
    }

    /**
     * デコード → リサンプリング → 実時間ポンプ をチャンク単位で連結する。
     *
     * 全量バッファを作らないことが本関数の唯一の存在理由である。ファイル
     * 冒頭「ストリーミング化」のコメントを参照。
     */
    private suspend fun streamIntoPipe(path: String, out: OutputStream) {
        val pacer = RealtimePump.Pacer(
            output = out,
            sampleRateHz = TARGET_SAMPLE_RATE,
            bitsPerSample = TARGET_BITS_PER_SAMPLE,
            channels = TARGET_CHANNELS,
        )
        var resampler: Resampler.StreamingResampler? = null
        var sourceSampleRate = 0
        var sourceChannelCount = 0

        AudioDecoder.decodeStreaming(
            path = path,
            onOutputFormat = { sampleRate, channelCount ->
                if (resampler == null) {
                    sourceSampleRate = sampleRate
                    sourceChannelCount = channelCount
                    resampler = Resampler.StreamingResampler(
                        sourceSampleRate = sampleRate,
                        sourceChannelCount = channelCount,
                        targetSampleRate = TARGET_SAMPLE_RATE,
                    )
                } else if (sampleRate != sourceSampleRate || channelCount != sourceChannelCount) {
                    // ストリーム途中でのフォーマット変更は、既に送出済みの
                    // サンプルと整合させる手段がない。フォールバックせず
                    // 明確に失敗させる(CLAUDE.md「フォールバック処理は禁止」)。
                    throw AndroidTranscribeError.DecodeFailed(
                        "デコード途中で出力フォーマットが変化した: " +
                            "${sourceSampleRate}Hz/${sourceChannelCount}ch → " +
                            "${sampleRate}Hz/${channelCount}ch",
                    )
                }
            },
            onPcmChunk = { chunk ->
                val active = resampler
                    ?: throw AndroidTranscribeError.DecodeFailed(
                        "出力フォーマットが通知される前にPCMが届いた",
                    )
                val converted = active.process(chunk)
                if (converted.isNotEmpty()) pacer.write(converted, 0, converted.size)
            },
        )

        // decodeStreaming は1バイトも出力しなかった場合に DecodeFailed を
        // 投げるため、ここへ到達した時点で resampler は必ず生成されている。
        val active = resampler
            ?: throw AndroidTranscribeError.DecodeFailed("デコード結果が空である: $path")
        val tail = active.flush()
        if (tail.isNotEmpty()) pacer.write(tail, 0, tail.size)
        pacer.flush()
    }

    private suspend fun awaitRecognition(
        recognizer: SpeechRecognizer,
        readSide: ParcelFileDescriptor,
        locale: String,
        segmentsWrapper: SegmentsEventWrapper,
        pumpJob: Job,
        pipelineFailure: AtomicReference<AndroidTranscribeError?>,
    ): Unit = suspendCancellableCoroutine { continuation ->
        // design.md §4.3(wt73版)「onResults()のtextsがnullになる。その場合は
        // 直前のonPartialResults()の最上位候補を確定結果として採用する」。
        var lastPartialTopCandidate: String? = null
        // `settled` はメインスレッドの `RecognitionListener` と、IOスレッドから
        // 走りうる `invokeOnCancellation` の両方から触られる。`pumpJob` は
        // Dispatchers.IO 上で失敗を再送出するため、子ジョブの失敗で親スコープが
        // キャンセルされるとキャンセルハンドラはIOスレッドで実行される。
        // 通常の Boolean では競合するので AtomicBoolean で原子的に扱う。
        val settled = AtomicBoolean(false)
        // `SpeechRecognizer` はメインスレッドから操作する契約であるため、
        // 後始末は必ずメインスレッドへ post する。
        val mainHandler = Handler(Looper.getMainLooper())

        recognizer.setRecognitionListener(
            object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}

                override fun onBeginningOfSpeech() {}

                override fun onRmsChanged(rmsdB: Float) {}

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {}

                override fun onError(error: Int) {
                    if (!settled.compareAndSet(false, true)) return
                    val mapped = ErrorMapping.map(error)
                    segmentsWrapper.sendError(mapped)
                    runCatching { recognizer.destroy() }
                    if (continuation.isActive) continuation.resumeWith(Result.success(Unit))
                }

                override fun onResults(results: Bundle?) {
                    if (!settled.compareAndSet(false, true)) return
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
                    if (settled.get()) return
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
            if (!settled.compareAndSet(false, true)) return@invokeOnCancellation
            // Issue #48。design.md §4.3「キャンセル時はパイプclose
            // → stopListening() → destroy()」の順序どおり実施する。
            // `stopListening()` / `destroy()` はメインスレッド契約があるため
            // post する。このハンドラ自体はIOスレッドから走りうる。
            runCatching { pumpJob.cancel() }
            runCatching { readSide.close() }
            mainHandler.post {
                runCatching { recognizer.stopListening() }
                runCatching { recognizer.destroy() }
            }
            // デコード・リサンプリング側の失敗で親スコープがキャンセルされた
            // 場合は「キャンセル」ではない。後始末だけ行い、エラーの送出は
            // `run()` から伝播する例外を受ける `OfflineSttApiImpl` に任せる
            // (そうしないと Dart 側が本当の理由ではなく cancelled を受け取る)。
            if (pipelineFailure.get() != null) return@invokeOnCancellation
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
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, TARGET_CHANNELS)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, TARGET_SAMPLE_RATE)
        }
        recognizer.startListening(intent)
    }
}
