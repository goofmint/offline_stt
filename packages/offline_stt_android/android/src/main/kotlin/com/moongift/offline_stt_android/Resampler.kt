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
//
// ## ストリーミング化(CodeRabbit指摘「Heavy lift」への対応)
// 旧実装は「入力PCM全体のByteArray」を受け取り、内部で
// `bytesToShorts`(入力と同サイズのShortArray)・`downmixToMono`・
// `linearResample`・`shortsToBytes` と複数の全長配列を確保していた。
// 48kHz・ステレオ・16-bitの60分音声では入力だけで約691MB、変換中の中間配列を
// 含めると1.7GB規模になり、端末のヒープ上限を超えてOOMになる。
// そこで本ファイルは[StreamingResampler]を導入し、チャンク単位で
// 「ダウンミックス → 線形補間 → 出力バイト列」を行えるようにした。
// 保持するのは「未消費の入力モノラルサンプル(1チャンク分 + 補間に必要な
// 数サンプル)」だけであり、ピークメモリは入力長に依存しない。
//
// 単発版の[resampleToMono16k]は[StreamingResampler]の薄いラッパーとして
// 実装する。こうしておけば「単発 = チャンク分割」の一致は実装上自明に保たれ、
// 二重実装によるズレが起こり得ない(ズレていないことは
// `ResamplerStreamingTest`でも明示的に検証する)。
package com.moongift.offline_stt_android

object Resampler {
    /**
     * 16-bit PCM(インターリーブ)を`targetSampleRate`・モノラルへ変換する。
     *
     * 入力全体を一度に渡す単発APIである。[StreamingResampler]へ全量を投入して
     * [StreamingResampler.flush]するのと完全に等価であり、**入力長に比例した
     * メモリを消費する**。長尺音声のパイプラインでは使わず、
     * [StreamingResampler]を直接使うこと(`RecognitionSession.kt`参照)。
     * 本関数は短い入力の変換と単体テストのために残している。
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
        val resampler = StreamingResampler(
            sourceSampleRate = sourceSampleRate,
            sourceChannelCount = sourceChannelCount,
            targetSampleRate = targetSampleRate,
        )
        val head = resampler.process(pcm)
        val tail = resampler.flush()
        if (tail.isEmpty()) return head
        if (head.isEmpty()) return tail
        return head + tail
    }

    /**
     * [resampleToMono16k]と同じ変換を**チャンク単位**で行う状態付き変換器。
     *
     * 使い方: デコーダから届いたPCMチャンクを順に[process]へ渡し、最後に
     * [flush]を呼ぶ。返ったバイト列をそのまま下流(実時間ポンプ)へ流す。
     * 戻り値が空配列になることは正常である(補間に必要な入力サンプルがまだ
     * 揃っていない場合)。
     *
     * ## チャンク境界の扱い(本クラスの肝)
     * 1. **フレーム境界**: チャンクの末尾が1フレーム(=`channelCount`×2バイト)
     *    に満たない場合、その端数バイトは[pendingBytes]に持ち越して次の
     *    チャンクの先頭と連結する。MediaCodecの出力バッファ境界はフレーム境界と
     *    一致する保証がないため必須である。
     * 2. **線形補間の連続性**: 出力サンプル`i`は入力モノラルサンプル
     *    `floor(i*ratio)`と`floor(i*ratio)+1`の2点から作られる。そのため
     *    「次に必要になる入力サンプル位置」より手前しか捨てられない。
     *    [monoBuffer]には未消費の入力モノラルサンプルだけを残し、消費済みの
     *    前方部分を都度切り詰める。出力位置[outIndex]と入力の絶対位置
     *    [monoBase]をグローバルなカウンタで持つことで、`srcPos = i * ratio`
     *    の計算式自体は単発版と1ビットも変わらない。
     * 3. **末尾の打ち切り位置**: 単発版の出力長は`floor(N/ratio)`
     *    (Nは入力モノラルサンプル総数)である。整数`i`について
     *    `i < floor(N/ratio) ⟺ (i+1)*ratio <= N` なので、ストリーミング中は
     *    「今までに受け取った入力サンプル数」をNの下限とみなしてこの条件を
     *    満たす`i`だけを出力する。入力が増えれば条件を満たす`i`も増えるため、
     *    取りこぼしも出しすぎも起こらない。総数が確定する[flush]時点で
     *    残りを出し切る。
     */
    class StreamingResampler(
        private val sourceSampleRate: Int,
        private val sourceChannelCount: Int,
        private val targetSampleRate: Int = 16_000,
    ) {
        init {
            require(sourceSampleRate > 0) { "sourceSampleRate must be positive" }
            require(sourceChannelCount > 0) { "sourceChannelCount must be positive" }
            require(targetSampleRate > 0) { "targetSampleRate must be positive" }
        }

        private val bytesPerFrame = sourceChannelCount * BYTES_PER_SAMPLE
        private val ratio = sourceSampleRate.toDouble() / targetSampleRate.toDouble()

        /** 単発版が`sourceSampleRate == targetSampleRate`を素通しにしていた分岐。 */
        private val passthrough = sourceSampleRate == targetSampleRate

        /** 1フレームに満たない端数バイト(常に`bytesPerFrame`未満)。 */
        private var pendingBytes = ByteArray(0)

        /** 未消費の入力モノラルサンプル。`monoBuffer[0]`の絶対位置が[monoBase]。 */
        private var monoBuffer = ShortArray(0)
        private var monoLength = 0
        private var monoBase = 0L

        /** 次に生成する出力サンプルの絶対位置。 */
        private var outIndex = 0L

        /** 受け取った入力モノラルサンプルの総数(= monoBase + monoLength)。 */
        private val available: Long get() = monoBase + monoLength

        private var flushed = false

        /**
         * PCMチャンクを投入し、この時点で確定した出力バイト列を返す。
         *
         * @param pcm 16-bit signed PCM、リトルエンディアン、インターリーブ。
         *   呼び出し後に内容を書き換えてよい(内部でコピーしてから保持する)。
         */
        fun process(pcm: ByteArray): ByteArray {
            check(!flushed) { "flush()後にprocess()を呼んではならない" }
            appendFrames(pcm)
            return drain(endOfStream = false)
        }

        /**
         * 入力の終端を宣言し、残りの出力バイト列を返す。以降[process]は呼べない。
         */
        fun flush(): ByteArray {
            check(!flushed) { "flush()を二度呼んではならない" }
            flushed = true
            // 端数バイト([pendingBytes])は完全なフレームを構成しないため捨てる。
            // 単発版も`bytesToShorts`・`downmixToMono`の整数除算で末尾の不完全な
            // フレームを落としており、挙動は同じである。
            return drain(endOfStream = true)
        }

        /**
         * 端数バイトと連結したうえでフレーム単位にダウンミックスし、
         * [monoBuffer]へ追加する。
         */
        private fun appendFrames(pcm: ByteArray) {
            if (pcm.isEmpty() && pendingBytes.isEmpty()) return

            val source: ByteArray
            val sourceLength: Int
            if (pendingBytes.isEmpty()) {
                source = pcm
                sourceLength = pcm.size
            } else {
                source = ByteArray(pendingBytes.size + pcm.size)
                System.arraycopy(pendingBytes, 0, source, 0, pendingBytes.size)
                System.arraycopy(pcm, 0, source, pendingBytes.size, pcm.size)
                sourceLength = source.size
            }

            val frameCount = sourceLength / bytesPerFrame
            val consumed = frameCount * bytesPerFrame
            pendingBytes = if (consumed == sourceLength) {
                EMPTY_BYTES
            } else {
                source.copyOfRange(consumed, sourceLength)
            }
            if (frameCount == 0) return

            ensureMonoCapacity(monoLength + frameCount)
            var offset = 0
            for (frame in 0 until frameCount) {
                // 全チャンネルの単純平均。Int加算→整数除算の順序は単発版と同一
                // (0方向への切り捨てまで含めて挙動を変えない)。
                var sum = 0
                for (ch in 0 until sourceChannelCount) {
                    sum += readLittleEndianShort(source, offset)
                    offset += BYTES_PER_SAMPLE
                }
                monoBuffer[monoLength + frame] = (sum / sourceChannelCount).toShort()
            }
            monoLength += frameCount
        }

        private fun drain(endOfStream: Boolean): ByteArray {
            if (passthrough) {
                // サンプルレートが同一なら補間は行わない(単発版と同じ分岐)。
                // ダウンミックス済みサンプルをそのまま出し切れるので、
                // バッファを持ち越す必要がない。
                if (monoLength == 0) return EMPTY_BYTES
                val out = shortsToBytes(monoBuffer, monoLength)
                outIndex += monoLength
                monoBase += monoLength
                monoLength = 0
                return out
            }

            // 単発版の`linearResample`にあった「入力が1サンプルだけならその
            // サンプルをそのまま返す」という分岐を保つ。入力総数が確定する
            // flush時にしか判定できない(それまでは入力が増える可能性がある)。
            if (endOfStream && outIndex == 0L && available == 1L) {
                outIndex = 1
                val only = monoBuffer[0]
                monoBase += 1
                monoLength = 0
                return shortsToBytes(shortArrayOf(only), 1)
            }

            val builder = ShortBuilder()
            while (true) {
                val i = outIndex
                // 打ち切り条件。クラスのドキュメントコメント3を参照。
                if ((i + 1) * ratio > available) break

                val srcPos = i * ratio
                val srcIndex = srcPos.toLong()
                val nextIndex = srcIndex + 1
                // 終端前は「補間相手(s1)」が届くまで待つ。終端後は単発版と同じく
                // s1が無ければs0で代用する。
                if (nextIndex >= available && !endOfStream) break

                val offset = (srcIndex - monoBase).toInt()
                val s0 = monoBuffer[offset]
                val s1 = if (nextIndex < available) monoBuffer[offset + 1] else s0
                val frac = srcPos - srcIndex
                builder.add((s0 + (s1 - s0) * frac).toInt().toShort())
                outIndex = i + 1
            }

            trimConsumed()
            return shortsToBytes(builder.buffer, builder.size)
        }

        /** 次の出力に必要な入力位置より前を捨て、バッファ長を入力長に依存させない。 */
        private fun trimConsumed() {
            val nextSourceIndex = (outIndex * ratio).toLong()
            val drop = (nextSourceIndex - monoBase)
                .coerceAtLeast(0L)
                .coerceAtMost(monoLength.toLong())
                .toInt()
            if (drop <= 0) return
            System.arraycopy(monoBuffer, drop, monoBuffer, 0, monoLength - drop)
            monoLength -= drop
            monoBase += drop
        }

        private fun ensureMonoCapacity(required: Int) {
            if (monoBuffer.size >= required) return
            var capacity = if (monoBuffer.isEmpty()) 1024 else monoBuffer.size
            while (capacity < required) capacity *= 2
            monoBuffer = monoBuffer.copyOf(capacity)
        }
    }

    private const val BYTES_PER_SAMPLE = 2
    private val EMPTY_BYTES = ByteArray(0)

    private fun readLittleEndianShort(bytes: ByteArray, offset: Int): Int =
        ((bytes[offset].toInt() and 0xFF) or (bytes[offset + 1].toInt() shl 8)).toShort().toInt()

    private fun shortsToBytes(shorts: ShortArray, length: Int): ByteArray {
        if (length == 0) return EMPTY_BYTES
        val bytes = ByteArray(length * BYTES_PER_SAMPLE)
        var offset = 0
        for (i in 0 until length) {
            val value = shorts[i].toInt()
            bytes[offset] = (value and 0xFF).toByte()
            bytes[offset + 1] = ((value shr 8) and 0xFF).toByte()
            offset += BYTES_PER_SAMPLE
        }
        return bytes
    }

    /** 出力長が事前に分からないための可変長ShortArray。 */
    private class ShortBuilder {
        var buffer = ShortArray(256)
            private set
        var size = 0
            private set

        fun add(value: Short) {
            if (size == buffer.size) buffer = buffer.copyOf(buffer.size * 2)
            buffer[size++] = value
        }
    }
}
