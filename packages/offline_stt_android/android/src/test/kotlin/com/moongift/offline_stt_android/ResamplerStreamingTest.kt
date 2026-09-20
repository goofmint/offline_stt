// ResamplerStreamingTest.kt
// `Resampler.StreamingResampler`(CodeRabbit指摘「Heavy lift」への対応で
// 追加したチャンク単位のリサンプラ)の検証。
//
// 検証したいことは2つある。
//  1. **チャンク分割しても単発実行と1バイトも変わらない**こと。線形補間は
//     出力1サンプルにつき入力2サンプルを参照するため、チャンク境界で前の
//     チャンクの末尾サンプルを持ち越さないと段差が出る。分割の仕方
//     (フレーム境界を割る奇数バイト長を含む)によらず一致することを示す。
//  2. **ストリーミング化前のアルゴリズムから出力が変わっていない**こと。
//     そのため本ファイルには旧実装(全量ByteArrayを受け取る版)をそのまま
//     [referenceResample] として写し、その出力と突き合わせる。
//     `Resampler.resampleToMono16k` 自体が現在は StreamingResampler の
//     ラッパーであり、両者を比較するだけでは「両方とも同じように壊れて
//     いる」場合を検出できないためである。
//
// design.md §7「Kotlin側: リサンプリングは純粋な計算なので、可能なら単体
// テストを書くこと」に沿う。OS API に依存しないため JVM 上で実行できる。
package com.moongift.offline_stt_android

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test

class ResamplerStreamingTest {

    // ---- テスト用ユーティリティ ---------------------------------------

    private fun shortsToPcm(shorts: ShortArray): ByteArray {
        val buffer = ByteBuffer.allocate(shorts.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (s in shorts) buffer.putShort(s)
        return buffer.array()
    }

    private fun pcmToShorts(pcm: ByteArray): ShortArray {
        val buffer = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
        val shorts = ShortArray(pcm.size / 2)
        for (i in shorts.indices) shorts[i] = buffer.short
        return shorts
    }

    /** 決定的だが単調ではない(補間の誤りが値に出る)テスト信号。 */
    private fun signal(sampleCount: Int): ByteArray =
        shortsToPcm(ShortArray(sampleCount) { (((it * 4409) % 65536) - 32768).toShort() })

    /**
     * ストリーミング化**前**の `Resampler.resampleToMono16k` の実装をその
     * まま写したもの。リグレッション検出の基準として使う。
     */
    private fun referenceResample(
        pcm: ByteArray,
        sourceSampleRate: Int,
        sourceChannelCount: Int,
        targetSampleRate: Int,
    ): ByteArray {
        if (pcm.isEmpty()) return ByteArray(0)

        val samples = pcmToShorts(pcm)
        val mono = if (sourceChannelCount == 1) {
            samples
        } else {
            val frameCount = samples.size / sourceChannelCount
            val downmixed = ShortArray(frameCount)
            for (frame in 0 until frameCount) {
                var sum = 0
                val base = frame * sourceChannelCount
                for (ch in 0 until sourceChannelCount) sum += samples[base + ch]
                downmixed[frame] = (sum / sourceChannelCount).toShort()
            }
            downmixed
        }

        val resampled = if (sourceSampleRate == targetSampleRate) {
            mono
        } else if (mono.isEmpty()) {
            ShortArray(0)
        } else if (mono.size == 1) {
            mono
        } else {
            val ratio = sourceSampleRate.toDouble() / targetSampleRate.toDouble()
            val outputLength = (mono.size / ratio).toInt()
            if (outputLength <= 0) {
                ShortArray(0)
            } else {
                val output = ShortArray(outputLength)
                for (i in 0 until outputLength) {
                    val srcPos = i * ratio
                    val srcIndex = srcPos.toInt()
                    val frac = srcPos - srcIndex
                    val s0 = mono[srcIndex]
                    val s1 = if (srcIndex + 1 < mono.size) mono[srcIndex + 1] else s0
                    output[i] = (s0 + (s1 - s0) * frac).toInt().toShort()
                }
                output
            }
        }
        return shortsToPcm(resampled)
    }

    /** `chunkSize`バイトずつ投入した場合の出力を連結して返す。 */
    private fun streamed(
        pcm: ByteArray,
        sourceSampleRate: Int,
        sourceChannelCount: Int,
        targetSampleRate: Int,
        chunkSize: Int,
    ): ByteArray {
        val resampler = Resampler.StreamingResampler(
            sourceSampleRate = sourceSampleRate,
            sourceChannelCount = sourceChannelCount,
            targetSampleRate = targetSampleRate,
        )
        val out = java.io.ByteArrayOutputStream()
        var offset = 0
        while (offset < pcm.size) {
            val end = minOf(offset + chunkSize, pcm.size)
            out.write(resampler.process(pcm.copyOfRange(offset, end)))
            offset = end
        }
        out.write(resampler.flush())
        return out.toByteArray()
    }

    // ---- 本題 ----------------------------------------------------------

    @Test
    fun `チャンク分割しても単発実行と完全に一致する`() {
        // (sourceSampleRate, channelCount, targetSampleRate, フレーム数)
        val cases = listOf(
            listOf(48_000, 2, 16_000, 9_601),
            listOf(44_100, 2, 16_000, 7_351),
            listOf(22_050, 1, 16_000, 3_677),
            listOf(8_000, 1, 16_000, 1_333), // アップサンプリング(ratio < 1)
            listOf(16_000, 1, 16_000, 2_048), // 素通し
            listOf(16_000, 2, 16_000, 1_024), // 素通し + ダウンミックス
            listOf(48_000, 6, 16_000, 811), // 5.1ch のダウンミックス
        )
        // フレーム境界(2ch=4バイト, 6ch=12バイト)を意図的に割る値を含める。
        val chunkSizes = listOf(1, 2, 3, 5, 7, 13, 97, 1_000, 4_096, 1_000_000)

        for (case in cases) {
            val (rate, channels, target, frames) = case
            val pcm = signal(frames * channels)
            val expected = referenceResample(pcm, rate, channels, target)

            // 単発API(現在は StreamingResampler のラッパー)も基準と一致する。
            val single = Resampler.resampleToMono16k(pcm, rate, channels, target)
            assertEquals(
                pcmToShorts(expected).toList(),
                pcmToShorts(single).toList(),
                "単発実行が旧実装と一致しない: rate=$rate ch=$channels target=$target",
            )

            for (chunkSize in chunkSizes) {
                val actual = streamed(pcm, rate, channels, target, chunkSize)
                assertEquals(
                    pcmToShorts(expected).toList(),
                    pcmToShorts(actual).toList(),
                    "チャンク分割で出力が変わった: rate=$rate ch=$channels " +
                        "target=$target chunkSize=$chunkSize",
                )
            }
        }
    }

    @Test
    fun `補間はチャンク境界をまたいで連続する`() {
        // 32kHz→16kHz(ratio=2.0)ではなく 24kHz→16kHz(ratio=1.5)を使い、
        // 端数 frac が必ず現れるようにする。
        // mono = [0, 300, 600, 900, 1200, 1500]
        //   i=0: srcPos=0.0 -> 0
        //   i=1: srcPos=1.5 -> 300 + (600-300)*0.5 = 450
        //   i=2: srcPos=3.0 -> 900
        //   i=3: srcPos=4.5 -> 1200 + (1500-1200)*0.5 = 1350
        val mono = shortArrayOf(0, 300, 600, 900, 1200, 1500)
        val pcm = shortsToPcm(mono)
        val expected = listOf<Short>(0, 450, 900, 1350)

        assertEquals(
            expected,
            pcmToShorts(Resampler.resampleToMono16k(pcm, 24_000, 1, 16_000)).toList(),
        )
        // 境界を i=1 の補間ペア(mono[1], mono[2])の真ん中に置く。持ち越しを
        // 忘れていれば 450 が出ない。
        for (chunkSize in 1..pcm.size) {
            assertEquals(
                expected,
                pcmToShorts(streamed(pcm, 24_000, 1, 16_000, chunkSize)).toList(),
                "chunkSize=$chunkSize",
            )
        }
    }

    @Test
    fun `空入力とフレーム未満の端数は空を返す`() {
        assertEquals(0, streamed(ByteArray(0), 48_000, 2, 16_000, 7).size)
        // 4バイト(=2chの1フレーム)に満たない3バイトだけを投入する。
        assertEquals(0, streamed(ByteArray(3), 48_000, 2, 16_000, 1).size)
    }

    @Test
    fun `末尾の不完全なフレームは旧実装と同じく捨てられる`() {
        // 2ch・9バイト = 2フレーム + 1バイト。
        val pcm = signal(4) + byteArrayOf(0x7F)
        val expected = referenceResample(pcm, 16_000, 2, 16_000)
        assertEquals(4, expected.size) // 2フレーム分のモノラル = 4バイト
        for (chunkSize in 1..pcm.size) {
            assertEquals(
                pcmToShorts(expected).toList(),
                pcmToShorts(streamed(pcm, 16_000, 2, 16_000, chunkSize)).toList(),
                "chunkSize=$chunkSize",
            )
        }
    }

    @Test
    fun `入力が1フレームだけの場合も旧実装と一致する`() {
        val pcm = shortsToPcm(shortArrayOf(1234))
        val expected = referenceResample(pcm, 48_000, 1, 16_000)
        assertEquals(listOf<Short>(1234), pcmToShorts(expected).toList())
        assertEquals(
            pcmToShorts(expected).toList(),
            pcmToShorts(streamed(pcm, 48_000, 1, 16_000, 1)).toList(),
        )
    }

    @Test
    fun `保持する未消費サンプルは入力長に比例しない`() {
        // OOM対策の本丸。1チャンク投入ごとに内部バッファが伸び続けないことを
        // 「出力済みサンプル数が入力の進行に追随している」ことで間接的に示す。
        // (内部バッファは private なので、消費が進んでいる = 捨てられている
        //  ことを出力量で確認する。)
        val frames = 48_000 * 10 // 10秒ぶん @48kHz ステレオ
        val pcm = signal(frames * 2)
        val resampler = Resampler.StreamingResampler(48_000, 2, 16_000)
        var producedBytes = 0L
        var consumedFrames = 0
        val chunkFrames = 1_024
        var offset = 0
        while (offset < pcm.size) {
            val end = minOf(offset + chunkFrames * 4, pcm.size)
            producedBytes += resampler.process(pcm.copyOfRange(offset, end)).size
            consumedFrames += (end - offset) / 4
            // 未出力のまま溜まっている入力は、理屈上つねに ratio(=3)
            // サンプル程度で、投入済みフレーム数には比例しない。出力済み
            // サンプル数が「投入フレーム数/3」から大きく遅れていないことで確認する。
            val expectedOut = consumedFrames / 3
            val actualOut = producedBytes / 2
            assertTrue(
                expectedOut - actualOut <= 2,
                "出力が滞留している: expected≈$expectedOut actual=$actualOut",
            )
            offset = end
        }
        producedBytes += resampler.flush().size
        assertEquals(
            referenceResample(pcm, 48_000, 2, 16_000).size.toLong(),
            producedBytes,
        )
    }

    @Test(expected = IllegalStateException::class)
    fun `flush後にprocessを呼ぶと例外になる`() {
        val resampler = Resampler.StreamingResampler(48_000, 1, 16_000)
        resampler.flush()
        resampler.process(ByteArray(2))
    }
}
