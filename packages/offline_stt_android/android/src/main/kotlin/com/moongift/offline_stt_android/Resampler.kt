// Resampler.kt
// requirements.md FR-4、Issue #45(design.md §4.3(wt73版)で「M0で必須と
// 実測確定」とされたリサンプリング)。
//
// design.md §4.3(wt73版)「線形補間ではなくAudioResampler相当のサンプル
// レート変換 + ステレオ→モノラルのダウンミックス処理をM3で実装する」との
// 指示に対し、本実装は外部ライブラリを追加せずKotlinのみで実装する方針
// (design.md §4.3(wt73版)「#45 リサンプリングの実装方針」)を取るため、
// 以下のとおり単純な線形補間で妥協する。品質とのトレードオフはこのファイル
// 冒頭・関数コメントに明記する。
package com.moongift.offline_stt_android

import java.nio.ByteBuffer
import java.nio.ByteOrder

object Resampler {
    /**
     * 16-bit PCM(インターリーブ)を`targetSampleRate`・モノラルへ変換する。
     *
     * ## アルゴリズムと品質のトレードオフ(design.md §4.3(wt73版)必須記載事項)
     * サンプルレート変換は**線形補間(linear interpolation)**で行う。
     * design.md が言及する「AudioResampler相当の処理」(windowed-sinc等の
     * ローパスFIRフィルタを伴う高品質リサンプラ)は実装しない。
     *
     * - **トレードオフの理由**: 外部DSPライブラリを追加しない方針
     *   (design.md §4.3(wt73版)「#45 リサンプリングの実装方針」)のもとで、
     *   windowed-sinc等の高品質リサンプラをゼロから実装するのは実装コストが
     *   高く、本ブランチのスコープ(#42〜#49の雛形〜キャンセルまで)に対して
     *   過大である。線形補間はNフレームの依存だけで実装でき、実装・
     *   テストのコストが低い。
     * - **品質上の既知の制約**: 線形補間はローパスフィルタを持たないため、
     *   ダウンサンプリング(本ライブラリの主要ケースである
     *   44.1/48kHz→16kHz)時にエイリアシング(折り返し雑音)を理論上
     *   十分に抑制できない。これは音声認識精度に悪影響を与えうる既知の
     *   制約として残る。
     * - **将来の改善余地**: 認識精度がボトルネックになった場合、
     *   ローパスFIRフィルタ(windowed-sinc等)を追加した高品質リサンプラへの
     *   置き換えを検討する(design.md §8相当の未決事項として記録する)。
     *
     * ステレオ/マルチチャンネル→モノラルのダウンミックスは全チャンネルの
     * 単純平均で行う(design.md §4.3(wt73版)「ステレオ→モノラルの
     * ダウンミックス」)。
     *
     * 純粋な計算のみで構成されるため単体テストが書ける
     * (`android/src/test/kotlin/.../ResamplerTest.kt`参照。design.md §7
     * 「Kotlin側: リサンプリングは純粋な計算なので、可能なら単体テストを
     * 書くこと」)。
     */
    fun resampleToMono16k(
        pcm: ByteArray,
        sourceSampleRate: Int,
        sourceChannelCount: Int,
        targetSampleRate: Int = 16_000,
    ): ByteArray {
        require(sourceSampleRate > 0) { "sourceSampleRate must be positive" }
        require(sourceChannelCount > 0) { "sourceChannelCount must be positive" }
        require(targetSampleRate > 0) { "targetSampleRate must be positive" }

        if (pcm.isEmpty()) return ByteArray(0)

        val mono = downmixToMono(pcm, sourceChannelCount)
        val resampled = if (sourceSampleRate == targetSampleRate) {
            mono
        } else {
            linearResample(mono, sourceSampleRate, targetSampleRate)
        }
        return shortsToBytes(resampled)
    }

    /** 全チャンネルの単純平均でモノラルへダウンミックスする。 */
    private fun downmixToMono(pcm: ByteArray, channelCount: Int): ShortArray {
        val samples = bytesToShorts(pcm)
        if (channelCount == 1) return samples

        val frameCount = samples.size / channelCount
        val mono = ShortArray(frameCount)
        for (frame in 0 until frameCount) {
            var sum = 0
            val base = frame * channelCount
            for (ch in 0 until channelCount) {
                sum += samples[base + ch]
            }
            mono[frame] = (sum / channelCount).toShort()
        }
        return mono
    }

    /** 上記コメントのとおり線形補間で妥協する。 */
    private fun linearResample(mono: ShortArray, sourceRate: Int, targetRate: Int): ShortArray {
        if (mono.isEmpty()) return ShortArray(0)
        if (mono.size == 1) return mono

        val ratio = sourceRate.toDouble() / targetRate.toDouble()
        val outputLength = (mono.size / ratio).toInt()
        if (outputLength <= 0) return ShortArray(0)

        val output = ShortArray(outputLength)
        for (i in 0 until outputLength) {
            val srcPos = i * ratio
            val srcIndex = srcPos.toInt()
            val frac = srcPos - srcIndex
            val s0 = mono[srcIndex]
            val s1 = if (srcIndex + 1 < mono.size) mono[srcIndex + 1] else s0
            output[i] = (s0 + (s1 - s0) * frac).toInt().toShort()
        }
        return output
    }

    private fun bytesToShorts(bytes: ByteArray): ShortArray {
        val shorts = ShortArray(bytes.size / 2)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        for (i in shorts.indices) {
            shorts[i] = buffer.short
        }
        return shorts
    }

    private fun shortsToBytes(shorts: ShortArray): ByteArray {
        val buffer = ByteBuffer.allocate(shorts.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (s in shorts) {
            buffer.putShort(s)
        }
        return buffer.array()
    }
}
