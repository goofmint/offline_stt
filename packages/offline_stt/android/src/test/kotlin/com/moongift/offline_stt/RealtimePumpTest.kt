// RealtimePumpTest.kt
// `RealtimePump.Pacer`(CodeRabbit指摘「Heavy lift」への対応で、全量
// ByteArray受け取りから逐次供給へ変えた実時間ポンプ)の検証。
//
// ## ここで検証できること・できないこと
// 検証できるのは「どの大きさで・どの順番で `OutputStream.write()` を呼ぶか」
// である。design.md §4.3(wt73版)が定める 100ms = 1,600サンプル =
// 3,200バイトという書き込み単位が、供給側の断片サイズによらず保たれることを
// 確かめる。M0 で Pixel 6 実機上の実効レート(約31,993バイト/秒)を実測した
// のはこの書き込み単位と `delay` の組み合わせであり、単位が変わらなければ
// レートも変わらない。
//
// 検証できないのは実効レートそのものである。`kotlinx-coroutines-test` の
// `runTest` は `delay` を仮想時間で読み飛ばすため、壁時計の経過は測れない。
// 実時間での挙動は実機E2E(design.md §7、Issue #50)に委ねる。
package com.moongift.offline_stt

import java.io.OutputStream
import kotlin.coroutines.coroutineContext
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Test

class RealtimePumpTest {

    /** `write()` の呼び出し単位を記録する OutputStream。 */
    private class RecordingOutputStream : OutputStream() {
        val writeSizes = mutableListOf<Int>()
        val bytes = java.io.ByteArrayOutputStream()
        var flushCount = 0

        override fun write(b: Int) {
            writeSizes.add(1)
            bytes.write(b)
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            writeSizes.add(len)
            bytes.write(b, off, len)
        }

        override fun flush() {
            flushCount++
        }
    }

    private fun pcm(size: Int): ByteArray = ByteArray(size) { (it % 251).toByte() }

    /** 16kHz・モノラル・16bit の既定設定(design.md §4.3(wt73版))。 */
    private fun pacer(output: OutputStream) = RealtimePump.Pacer(
        output = output,
        sampleRateHz = 16_000,
        bitsPerSample = 16,
        channels = 1,
    )

    @Test
    fun `書き込み単位は供給の刻み方によらず3200バイトである`() = runTest {
        // 10秒ぶん + 端数。3,200バイト = 100ms が 100 回 + 末尾 1,234 バイト。
        val data = pcm(3_200 * 100 + 1_234)
        // 供給側の断片サイズ。MediaCodec の出力チャンクは 3,200 バイトとは
        // 無関係な大きさで届くため、割り切れない値を意図的に並べる。
        val feedSizes = listOf(1, 7, 683, 3_199, 3_200, 3_201, 12_000, data.size)

        for (feedSize in feedSizes) {
            val sink = RecordingOutputStream()
            val pacer = pacer(sink)
            var offset = 0
            while (offset < data.size) {
                val length = minOf(feedSize, data.size - offset)
                pacer.write(data, offset, length)
                offset += length
            }
            val result = pacer.flush()

            assertEquals(
                List(100) { 3_200 } + listOf(1_234),
                sink.writeSizes,
                "feedSize=$feedSize で書き込み単位が変わった",
            )
            assertEquals(data.toList(), sink.bytes.toByteArray().toList(), "feedSize=$feedSize")
            assertEquals(data.size, result.totalBytesSent, "feedSize=$feedSize")
            assertFalse(result.cancelled, "feedSize=$feedSize")
            // 書き込み1回につき flush 1回(旧実装と同じ)。
            assertEquals(101, sink.flushCount, "feedSize=$feedSize")
        }
    }

    @Test
    fun `チャンクが埋まるまでは1バイトも書かない`() = runTest {
        val sink = RecordingOutputStream()
        val pacer = pacer(sink)
        pacer.write(pcm(3_199), 0, 3_199)
        assertEquals(emptyList(), sink.writeSizes)
        pacer.write(pcm(1), 0, 1)
        assertEquals(listOf(3_200), sink.writeSizes)
    }

    @Test
    fun `端数が無ければflushは何も書かない`() = runTest {
        val sink = RecordingOutputStream()
        val pacer = pacer(sink)
        val data = pcm(3_200 * 3)
        pacer.write(data, 0, data.size)
        val result = pacer.flush()
        assertEquals(listOf(3_200, 3_200, 3_200), sink.writeSizes)
        assertEquals(3_200 * 3, result.totalBytesSent)
    }

    @Test
    fun `入力が1チャンクに満たなくてもflushで送り切る`() = runTest {
        val sink = RecordingOutputStream()
        val pacer = pacer(sink)
        pacer.write(pcm(10), 0, 10)
        val result = pacer.flush()
        assertEquals(listOf(10), sink.writeSizes)
        assertEquals(10, result.totalBytesSent)
    }

    @Test
    fun `キャンセル済みコルーチンでは1バイトも書かない`() = runTest {
        // Issue #48 のキャンセル経路。旧実装が送出ループの先頭で
        // `coroutineContext.isActive` を見て break していたのと同じ判定を、
        // チャンク送出の直前で行う。
        val sink = RecordingOutputStream()
        val pacer = pacer(sink)
        val job = launch {
            // 自分自身をキャンセルしてから送出を試みる。
            coroutineContext[Job]!!.cancel()
            pacer.write(pcm(3_200 * 2), 0, 3_200 * 2)
        }
        job.join()
        assertEquals(emptyList(), sink.writeSizes)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `sampleRateHzが0以下なら例外を投げる`() {
        RealtimePump.Pacer(
            output = RecordingOutputStream(),
            sampleRateHz = 0,
            bitsPerSample = 16,
            channels = 1,
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `bitsPerSampleが8の倍数でなければ例外を投げる`() {
        RealtimePump.Pacer(
            output = RecordingOutputStream(),
            sampleRateHz = 16_000,
            bitsPerSample = 12,
            channels = 1,
        )
    }
}
