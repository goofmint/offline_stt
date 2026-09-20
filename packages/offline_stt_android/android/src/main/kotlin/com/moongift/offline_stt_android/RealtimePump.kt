// RealtimePump.kt
// design.md §4.3(wt73版)の実時間ポンプ、Issue #46。壁時計基準で PCM を
// ParcelFileDescriptor の書き込み側へ供給する。design.md §6 に従い呼び出し
// 元は Dispatchers.IO 上で実行すること。
//
// バッファ単位について:
// design.md §4.3(wt73版)は「実時間ポンプ: 100ms = 1,600サンプル =
// 3,200バイト(1サンプル=2バイト)。壁時計基準」と定める。本実装の
// [DEFAULT_CHUNK_SAMPLES] はこの値(1,600サンプル)に合わせている。
//
// 本実装は「1チャンクのサンプル数」という設定値の大小に依存せず、書き込む
// たびに累積送信サンプル数と壁時計経過時間の差分で sleep を調整する
// 自己補正アルゴリズムを採る。そのため実効スループットはチャンクサイズの
// 値に関わらず常に `sampleRateHz × bytesPerSample × channels` バイト/秒に
// 収束する。
//
// spikes/android/app/src/main/java/com/moongift/offlinestt/spike/
// RealtimePump.kt(Pixel 6実機で目標レートとほぼ一致する実効レートを実測
// 済み、design.md §4.3(wt73版)「既存の実時間ポンプ設計はバックエンド
// 差し替え後もそのまま使える」)を移植の出発点とした。SpikeLogへの依存を
// android.util.Logへ置き換えた点のみがスパイクとの差分である。
package com.moongift.offline_stt_android

import android.util.Log
import java.io.OutputStream
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

object RealtimePump {
    private const val TAG = "OfflineSttRealtimePump"

    /** design.md §4.3(wt73版)記載の値(100ms相当 = 1,600サンプル)。 */
    const val DEFAULT_CHUNK_SAMPLES = 1600

    data class PumpResult(
        val totalBytesSent: Int,
        val elapsedMs: Long,
        val cancelled: Boolean,
    )

    /**
     * @param output PFDパイプの書き込み側から得た OutputStream。呼び出し元が
     *   close() する(design.md §4.3(wt73版):
     *   「キャンセル時はパイプclose → stopListening() → destroy()」)ため、
     *   本関数はストリームを close しない。
     */
    suspend fun pump(
        output: OutputStream,
        pcmBytes: ByteArray,
        sampleRateHz: Int,
        bitsPerSample: Int,
        channels: Int,
        chunkSamples: Int = DEFAULT_CHUNK_SAMPLES,
    ): PumpResult {
        require(sampleRateHz > 0) { "sampleRateHz must be positive" }
        require(bitsPerSample % 8 == 0) { "bitsPerSample must be a multiple of 8" }
        val bytesPerSample = bitsPerSample / 8
        val bytesPerFrame = bytesPerSample * channels
        val chunkBytes = chunkSamples * bytesPerFrame
        val totalBytes = pcmBytes.size

        val startNanos = System.nanoTime()
        var offset = 0
        var cumulativeSamples = 0L
        var cancelled = false

        while (offset < totalBytes) {
            if (!coroutineContext.isActive) {
                cancelled = true
                Log.w(TAG, "コルーチンがキャンセルされたため送出を中断する (offset=$offset)。")
                break
            }
            val end = minOf(offset + chunkBytes, totalBytes)
            val len = end - offset
            output.write(pcmBytes, offset, len)
            output.flush()
            offset = end
            cumulativeSamples += (len / bytesPerFrame)

            // 目標: cumulativeSamples 分の音声再生に要する実時間が経過して
            // からこのチャンクを送り終える。
            val targetElapsedNanos = (cumulativeSamples * 1_000_000_000L) / sampleRateHz
            val actualElapsedNanos = System.nanoTime() - startNanos
            val sleepNanos = targetElapsedNanos - actualElapsedNanos

            if (sleepNanos > 0) {
                delay(sleepNanos / 1_000_000)
            } else if (sleepNanos < -50_000_000L) {
                // 50ms 以上遅延している場合は追いつけていない兆候として警告
                // する(フォールバックはしない。事実をログするのみ)。
                Log.w(
                    TAG,
                    "送出が実時間に対して ${-sleepNanos / 1_000_000}ms 遅延している " +
                        "(offset=$offset/$totalBytes)。",
                )
            }
        }

        val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000
        return PumpResult(offset, elapsedMs, cancelled)
    }
}
