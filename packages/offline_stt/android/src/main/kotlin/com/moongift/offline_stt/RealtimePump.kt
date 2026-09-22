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
// 収束する(M0 で Pixel 6 実機の実測済み。spikes/android/RESULTS.md および
// spikes/android/app/src/main/java/com/moongift/offlinestt/spike/
// RealtimePump.kt を移植の出発点とした)。
//
// ## 全量ByteArray受け取りからストリーミング供給への変更
// (CodeRabbit指摘「Heavy lift」への対応)
// 旧実装は `pump(output, pcmBytes: ByteArray, ...)` という「変換済みPCM全量を
// 1本のByteArrayで受け取る」APIだった。そのため呼び出し元は必ず全長のPCMを
// 先に materialize する必要があり、長尺音声でOOMになる。
// 本実装は [Pacer] という状態付きの供給器に変え、任意の大きさの断片を
// [Pacer.write] で何度でも渡せるようにした。内部では断片を
// `chunkSamples` 分たまるまで貯め、**たまった時点で正確に chunkBytes ずつ**
// 書き出す。すなわち:
//   - 1回の `output.write()` の大きさ(既定3,200バイト)
//   - 書き込みと書き込みの間の sleep の決め方(累積サンプル数 vs 壁時計)
//   - 末尾の端数チャンクだけが chunkBytes 未満になること
// のいずれも旧実装と同一であり、単位時間あたりの送出バイト数(実測
// 約31,993バイト/秒)は変わらない。計測開始時刻(startNanos)は旧実装では
// ループ直前、本実装では最初の書き込み直前に取るが、旧実装もループに入って
// 即座に1回目を書いていたため実質同じである。
package com.moongift.offline_stt

import android.util.Log
import java.io.OutputStream
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

object RealtimePump {
    private const val TAG = "OfflineSttRealtimePump"

    /** design.md §4.3(wt73版)記載の値(100ms相当 = 1,600サンプル)。 */
    const val DEFAULT_CHUNK_SAMPLES = 1600

    /** 50ms以上の遅延は「実時間に追いつけていない」兆候として警告する閾値。 */
    private const val LAG_WARNING_THRESHOLD_NANOS = 50_000_000L

    data class PumpResult(
        val totalBytesSent: Int,
        val elapsedMs: Long,
        val cancelled: Boolean,
    )

    /**
     * 壁時計基準でPCMをパイプへ供給する状態付きの供給器。
     *
     * デコード〜リサンプリングの結果が届き次第 [write] へ渡し、入力を出し
     * 切ったら [flush] を呼ぶ。ピークメモリは内部のチャンクバッファ
     * (既定3,200バイト)だけであり、音声の長さに依存しない。
     *
     * @param output PFDパイプの書き込み側から得た OutputStream。呼び出し元が
     *   close() する(design.md §4.3(wt73版):
     *   「キャンセル時はパイプclose → stopListening() → destroy()」)ため、
     *   本クラスはストリームを close しない。
     */
    class Pacer(
        private val output: OutputStream,
        private val sampleRateHz: Int,
        bitsPerSample: Int,
        channels: Int,
        chunkSamples: Int = DEFAULT_CHUNK_SAMPLES,
    ) {
        init {
            require(sampleRateHz > 0) { "sampleRateHz must be positive" }
            // 0 や負の8の倍数がここを通ると、フレームサイズ計算の除算で
            // ArithmeticException になったり ByteArray の生成に失敗したりする。
            require(bitsPerSample > 0 && bitsPerSample % 8 == 0) {
                "bitsPerSample must be a positive multiple of 8"
            }
            require(channels > 0) { "channels must be positive" }
            require(chunkSamples > 0) { "chunkSamples must be positive" }
        }

        private val bytesPerFrame = (bitsPerSample / 8) * channels
        private val chunk = ByteArray(chunkSamples * bytesPerFrame)

        private var fill = 0
        private var startNanos = 0L
        private var started = false
        private var cumulativeSamples = 0L
        private var totalBytesSent = 0
        private var cancelled = false

        /**
         * PCMの断片を供給する。チャンクが埋まるたびに壁時計基準で送出する。
         * コルーチンがキャンセルされていれば送出を中断し、以降は何もしない。
         */
        suspend fun write(data: ByteArray, offset: Int, length: Int) {
            require(offset >= 0 && length >= 0 && offset + length <= data.size) {
                "write() range out of bounds"
            }
            var position = offset
            var remaining = length
            while (remaining > 0 && !cancelled) {
                val copied = minOf(chunk.size - fill, remaining)
                System.arraycopy(data, position, chunk, fill, copied)
                fill += copied
                position += copied
                remaining -= copied
                if (fill == chunk.size) emitChunk()
            }
        }

        /**
         * 端数チャンクを送出して結果を返す。旧実装の `pump()` が最後の
         * `chunkBytes` 未満の残りを書いていたのと同じ扱いである。
         */
        suspend fun flush(): PumpResult {
            if (fill > 0 && !cancelled) emitChunk()
            val elapsedMs = if (started) (System.nanoTime() - startNanos) / 1_000_000 else 0L
            return PumpResult(totalBytesSent, elapsedMs, cancelled)
        }

        private suspend fun emitChunk() {
            if (!coroutineContext.isActive) {
                cancelled = true
                Log.w(TAG, "コルーチンがキャンセルされたため送出を中断する (sent=$totalBytesSent)。")
                return
            }
            if (!started) {
                started = true
                startNanos = System.nanoTime()
            }

            val length = fill
            output.write(chunk, 0, length)
            output.flush()
            fill = 0
            totalBytesSent += length
            cumulativeSamples += (length / bytesPerFrame)

            // 目標: cumulativeSamples 分の音声再生に要する実時間が経過して
            // からこのチャンクを送り終える。
            val targetElapsedNanos = (cumulativeSamples * 1_000_000_000L) / sampleRateHz
            val actualElapsedNanos = System.nanoTime() - startNanos
            val sleepNanos = targetElapsedNanos - actualElapsedNanos

            if (sleepNanos > 0) {
                delay(sleepNanos / 1_000_000)
            } else if (sleepNanos < -LAG_WARNING_THRESHOLD_NANOS) {
                // 50ms 以上遅延している場合は追いつけていない兆候として警告
                // する(フォールバックはしない。事実をログするのみ)。
                // ストリーミング化後はデコード・リサンプリングの所要時間も
                // この遅延に含まれるため、デコードが実時間より遅い端末では
                // ここに出る。M0 実測(spikes/android/RESULTS.md Issue #14)
                // ではデコードは実時間を大きく上回る速度で完了している。
                Log.w(
                    TAG,
                    "送出が実時間に対して ${-sleepNanos / 1_000_000}ms 遅延している " +
                        "(sent=$totalBytesSent)。",
                )
            }
        }
    }
}
