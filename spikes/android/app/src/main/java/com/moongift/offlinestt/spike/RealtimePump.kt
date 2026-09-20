package com.moongift.offlinestt.spike

import java.io.OutputStream
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.coroutines.coroutineContext

/**
 * design.md §4.3 の実時間ポンプ (Issue #13)。壁時計基準で PCM を `ParcelFileDescriptor` の
 * 書き込み側へ供給する。design.md §6 に従い呼び出し元は `Dispatchers.IO` 上で実行すること。
 *
 * バッファ単位について:
 * design.md §4.3 は「バッファ単位100ms(16kHz・モノラル・16-bit PCMでは1,600サンプル=3,200バイト。
 * 1サンプル=2バイトである点に注意)」と定める。本実装の [DEFAULT_CHUNK_SAMPLES] はこの値
 * (1,600サンプル)に合わせている。
 *
 * 本実装は「1チャンクのサンプル数」という設定値の大小に依存せず、書き込むたびに
 * 累積送信サンプル数と壁時計経過時間の差分で sleep を調整する自己補正アルゴリズムを採る
 * (design.md の記述通り)。そのため実効スループットはチャンクサイズの値に関わらず常に
 * `sampleRateHz × bytesPerSample × channels` バイト/秒に収束する。
 */
object RealtimePump {

    /** design.md §4.3 記載の値(100ms相当 = 1,600サンプル)をそのまま踏襲 (上記コメント参照)。 */
    const val DEFAULT_CHUNK_SAMPLES = 1600

    data class PumpResult(
        val totalBytesSent: Int,
        val elapsedMs: Long,
        val effectiveBytesPerSec: Double,
        val cancelled: Boolean,
    )

    /**
     * @param output PFDパイプの書き込み側から得た OutputStream。呼び出し元が close() する
     *   (design.md §4.3: 「キャンセル時はパイプclose → stopRecognition() → close()」)ため、
     *   本関数はストリームを close しない。
     */
    suspend fun pump(
        output: OutputStream,
        pcmBytes: ByteArray,
        sampleRateHz: Int,
        bitsPerSample: Int,
        channels: Int,
        chunkSamples: Int = DEFAULT_CHUNK_SAMPLES,
        onProgress: (sentBytes: Int, totalBytes: Int, elapsedMs: Long) -> Unit = { _, _, _ -> },
    ): PumpResult {
        require(sampleRateHz > 0) { "sampleRateHz must be positive" }
        require(bitsPerSample % 8 == 0) { "bitsPerSample must be a multiple of 8" }
        val bytesPerSample = bitsPerSample / 8
        val bytesPerFrame = bytesPerSample * channels
        val chunkBytes = chunkSamples * bytesPerFrame
        val totalBytes = pcmBytes.size

        SpikeLog.info(
            "RealtimePump 開始: totalBytes=$totalBytes, sampleRate=$sampleRateHz, " +
                "bytesPerFrame=$bytesPerFrame, chunkBytes=$chunkBytes, " +
                "目標レート=${sampleRateHz * bytesPerFrame}バイト/秒"
        )

        val startNanos = System.nanoTime()
        var offset = 0
        var cumulativeSamples = 0L
        var cancelled = false

        try {
            while (offset < totalBytes) {
                if (!coroutineContext.isActive) {
                    cancelled = true
                    SpikeLog.warn("RealtimePump: コルーチンがキャンセルされたため送出を中断する (offset=$offset)。")
                    break
                }
                val end = minOf(offset + chunkBytes, totalBytes)
                val len = end - offset
                output.write(pcmBytes, offset, len)
                output.flush()
                offset = end
                cumulativeSamples += (len / bytesPerFrame)

                // 目標: cumulativeSamples 分の音声再生に要する実時間が経過してからこのチャンクを送り終える。
                val targetElapsedNanos = (cumulativeSamples * 1_000_000_000L) / sampleRateHz
                val actualElapsedNanos = System.nanoTime() - startNanos
                val sleepNanos = targetElapsedNanos - actualElapsedNanos

                onProgress(offset, totalBytes, actualElapsedNanos / 1_000_000)

                if (sleepNanos > 0) {
                    delay(sleepNanos / 1_000_000)
                } else if (sleepNanos < -50_000_000L) {
                    // 50ms 以上遅延している場合は追いつけていない兆候として警告する
                    // (フォールバックはしない。事実をログするのみ)。
                    SpikeLog.warn(
                        "RealtimePump: 送出が実時間に対して ${-sleepNanos / 1_000_000}ms 遅延している " +
                            "(offset=$offset/$totalBytes)。"
                    )
                }
            }
        } catch (e: java.io.IOException) {
            // 読み取り側が閉じられた (EPIPE 等) 場合はここに来る。キャンセル経路の一部として扱い、
            // 握りつぶさずログに残した上で呼び出し元へ伝播する。
            SpikeLog.ng("RealtimePump: 書き込み中に IOException (offset=$offset/$totalBytes): ${e.message}")
            throw e
        }

        val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000
        val effectiveBytesPerSec = if (elapsedMs > 0) offset.toDouble() / (elapsedMs / 1000.0) else 0.0
        SpikeLog.let {
            val fn = if (cancelled) it::warn else it::ok
            fn(
                "RealtimePump 終了: sentBytes=$offset/$totalBytes, elapsedMs=$elapsedMs, " +
                    "実効レート=${"%.1f".format(effectiveBytesPerSec)}バイト/秒, cancelled=$cancelled"
            )
        }
        return PumpResult(offset, elapsedMs, effectiveBytesPerSec, cancelled)
    }
}
