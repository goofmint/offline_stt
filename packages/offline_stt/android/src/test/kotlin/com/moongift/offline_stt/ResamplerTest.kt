// ResamplerTest.kt
// Resampler.kt(Issue #45)は純粋な計算(バイト配列→バイト配列)のみで
// 構成されており、Android OS APIに依存しないため、`app/src/test/`相当の
// JVMユニットテストで検証できる(design.md §7「Kotlin側: リサンプリングは
// 純粋な計算なので、可能なら単体テストを書くこと」、本ブランチの指示書
// 「OS API依存部分は書かなくてよい」との切り分け方針)。
//
// AudioDecoder.kt・RecognitionSession.kt・ModelAvailability.kt等は
// MediaExtractor/MediaCodec/SpeechRecognizerといったOS APIに直接依存する
// ため、JVMユニットテストの対象外とし実機E2E(design.md §7、本ブランチの
// スコープ外である#50)に委ねる。
package com.moongift.offline_stt

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test

class ResamplerTest {

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

    @Test
    fun `同一サンプルレート・モノラルは変化しない`() {
        val input = shortsToPcm(shortArrayOf(100, -200, 300, -400))
        val output = Resampler.resampleToMono16k(
            pcm = input,
            sourceSampleRate = 16_000,
            sourceChannelCount = 1,
            targetSampleRate = 16_000,
        )
        assertEquals(shortArrayOf(100, -200, 300, -400).toList(), pcmToShorts(output).toList())
    }

    @Test
    fun `ステレオは全チャンネルの単純平均でモノラルへダウンミックスする`() {
        // 2フレーム、L/Rの順でインターリーブ: (100, 200), (300, 400)
        val input = shortsToPcm(shortArrayOf(100, 200, 300, 400))
        val output = Resampler.resampleToMono16k(
            pcm = input,
            sourceSampleRate = 16_000,
            sourceChannelCount = 2,
            targetSampleRate = 16_000,
        )
        // (100+200)/2=150, (300+400)/2=350
        assertEquals(shortArrayOf(150, 350).toList(), pcmToShorts(output).toList())
    }

    @Test
    fun `線形補間によるダウンサンプリングは決定的な値を返す`() {
        // sourceRate=32000, targetRate=16000 -> ratio=2.0
        // srcPos(i=0)=0 -> mono[0]=0
        // srcPos(i=1)=2 -> mono[2]=200
        val input = shortsToPcm(shortArrayOf(0, 100, 200, 300))
        val output = Resampler.resampleToMono16k(
            pcm = input,
            sourceSampleRate = 32_000,
            sourceChannelCount = 1,
            targetSampleRate = 16_000,
        )
        assertEquals(shortArrayOf(0, 200).toList(), pcmToShorts(output).toList())
    }

    @Test
    fun `ダウンサンプリングは出力サンプル数をおおよそ比率どおりに減らす`() {
        val samples = ShortArray(1600) { (it % 100).toShort() } // 100ms相当@16kHz
        val input = shortsToPcm(samples)
        val output = Resampler.resampleToMono16k(
            pcm = input,
            sourceSampleRate = 48_000,
            sourceChannelCount = 1,
            targetSampleRate = 16_000,
        )
        val outputSamples = pcmToShorts(output)
        // 48000 -> 16000 は 1/3 になるはず(多少の丸め誤差を許容)。
        val expected = samples.size / 3
        assertTrue(
            kotlin.math.abs(outputSamples.size - expected) <= 1,
            "expected around $expected samples, but was ${outputSamples.size}",
        )
    }

    @Test
    fun `空のPCMは空のまま返す`() {
        val output = Resampler.resampleToMono16k(
            pcm = ByteArray(0),
            sourceSampleRate = 44_100,
            sourceChannelCount = 2,
        )
        assertEquals(0, output.size)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `sourceSampleRateが0以下なら例外を投げる`() {
        Resampler.resampleToMono16k(
            pcm = shortsToPcm(shortArrayOf(1, 2)),
            sourceSampleRate = 0,
            sourceChannelCount = 1,
        )
    }
}
