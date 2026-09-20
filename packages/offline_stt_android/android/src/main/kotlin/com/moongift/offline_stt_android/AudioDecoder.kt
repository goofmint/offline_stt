// AudioDecoder.kt
// requirements.md FR-4、Issue #44。design.md §4.3(wt73版)のデコード層。
// `MediaExtractor` + `MediaCodec` で任意の音声ファイル(wav/m4a/mp3等、
// OS標準デコーダが対応する範囲)を16-bit raw PCM(ネイティブのサンプル
// レート・チャンネル数のまま)へ変換する。
//
// design.md §4.3(wt73版)「MediaCodecはコーデックのデコードのみを行い、
// サンプルレート変換・チャンネルのダウンミックスは一切行わないことを実測で
// 確認した」との検証結果どおり、本関数はサンプルレート・チャンネル数の変換を
// 一切行わない。それらは呼び出し元(`RecognitionSession`)が`Resampler`
// (Issue #45)を使って別途行う。
//
// ## 全量バッファからストリーミングへの変更
// (CodeRabbit指摘「Heavy lift」への対応)
// 旧実装 `decodeToPcm16()` はデコード結果を `ByteArrayOutputStream` に
// 溜め込み、入力全体のPCMを1本の `ByteArray` で返していた。48kHz・ステレオ・
// 16-bitの60分音声ではそれだけで約691MBになり、後段のリサンプリングが確保する
// 中間配列と合わせて端末のヒープ上限を超えてOOMになる。APIとして入力長の
// 上限を定めない以上、デコード結果を保持し続けてはならない。
// そこで本実装は [decodeStreaming] だけを提供し、MediaCodecの出力バッファを
// 取り出すたびにコールバックへ渡して即座に手放す。ピークメモリは
// MediaCodecの出力バッファ1つ分(実測で数KB〜十数KB)に収まる。
package com.moongift.offline_stt_android

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.IOException
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.isActive

object AudioDecoder {
    private const val TIMEOUT_US = 10_000L

    /**
     * 音声ファイルをデコードし、16-bit raw PCMをチャンク単位で
     * [onPcmChunk] へ供給する。
     *
     * デコードが完了する(= 入力を出し切る)まで suspend する。コルーチンが
     * キャンセルされた場合は [CancellationException] を投げ、MediaCodec と
     * MediaExtractor を必ず解放する。
     *
     * @param onOutputFormat デコーダの出力フォーマットが確定した時点、および
     *   デコード途中で `INFO_OUTPUT_FORMAT_CHANGED` により変化した時点で
     *   呼ばれる。必ず最初の [onPcmChunk] より前に1回は呼ばれる。
     *   引数はサンプルレートとチャンネル数(いずれもネイティブ値のまま)。
     * @param onPcmChunk デコード済みPCM(16-bit signed、リトルエンディアン、
     *   インターリーブ)のチャンク。呼び出しごとに新しい配列を渡すので、
     *   受け取り側は保持しても書き換えてもよい。
     * @throws AndroidTranscribeError.DecodeFailed デコード系の失敗時。
     * @throws IOException [onPcmChunk] が投げた [IOException]
     *   (パイプの読み取り側が先に閉じられた場合など)はデコード失敗ではない
     *   ため、`DecodeFailed` へ包まずそのまま伝播させる。
     */
    suspend fun decodeStreaming(
        path: String,
        onOutputFormat: suspend (sampleRate: Int, channelCount: Int) -> Unit,
        onPcmChunk: suspend (chunk: ByteArray) -> Unit,
    ) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
        } catch (e: Exception) {
            extractor.release()
            throw AndroidTranscribeError.DecodeFailed(
                "MediaExtractor.setDataSource失敗: ${e.message}",
            )
        }

        var trackIndex = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime != null && mime.startsWith("audio/")) {
                trackIndex = i
                inputFormat = format
                break
            }
        }
        if (trackIndex < 0 || inputFormat == null) {
            extractor.release()
            throw AndroidTranscribeError.DecodeFailed("音声トラックが見つからない: $path")
        }
        extractor.selectTrack(trackIndex)

        val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
        // `createDecoderByType()` が成功したあと `configure()` / `start()` が
        // 失敗すると、生成済みの MediaCodec が release() されずネイティブ
        // リソースを保持したまま残る(非対応プロファイルの入力で実際に
        // 起きる)。同一プロセスで繰り返すとコーデックインスタンスが枯渇
        // するため、catch 節から参照できる変数に受けて必ず release する。
        var created: MediaCodec? = null
        try {
            created = MediaCodec.createDecoderByType(mime)
            created.configure(inputFormat, null, null, 0)
            created.start()
        } catch (e: Exception) {
            runCatching { created?.release() }
            extractor.release()
            throw AndroidTranscribeError.DecodeFailed(
                "MediaCodec初期化失敗(mime=$mime): ${e.message}",
            )
        }
        val codec: MediaCodec = created

        // 入力側MediaFormatの値を初期値とし、INFO_OUTPUT_FORMAT_CHANGEDが
        // 通知された場合はデコーダの実際の出力フォーマットで上書きする。
        var outSampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var outChannels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var formatNotified = false
        var totalPcmBytes = 0L
        val bufferInfo = MediaCodec.BufferInfo()
        var sawInputEOS = false
        var sawOutputEOS = false

        try {
            while (!sawOutputEOS) {
                if (!coroutineContext.isActive) {
                    throw CancellationException("AudioDecoder.decodeStreaming cancelled")
                }
                if (!sawInputEOS) {
                    val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)
                            ?: throw AndroidTranscribeError.DecodeFailed(
                                "MediaCodec入力バッファ取得失敗",
                            )
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            sawInputEOS = true
                        } else {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                sampleSize,
                                extractor.sampleTime,
                                0,
                            )
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                when {
                    outputIndex >= 0 -> {
                        if (bufferInfo.size > 0) {
                            val outputBuffer = codec.getOutputBuffer(outputIndex)
                                ?: throw AndroidTranscribeError.DecodeFailed(
                                    "MediaCodec出力バッファ取得失敗",
                                )
                            val chunk = ByteArray(bufferInfo.size)
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                            outputBuffer.get(chunk)
                            // 出力フォーマットの通知は必ず最初のPCMより前に行う。
                            // 実測(spikes/android/RESULTS.md Issue #14)では
                            // INFO_OUTPUT_FORMAT_CHANGED が先に届くため通常は
                            // ここへは来ないが、届かないデコーダのために入力側
                            // MediaFormat の値で通知する。
                            if (!formatNotified) {
                                formatNotified = true
                                onOutputFormat(outSampleRate, outChannels)
                            }
                            // releaseOutputBuffer より前にコールバックを呼ぶと、
                            // 実時間ポンプの sleep の間 MediaCodec のバッファを
                            // 掴んだままになる。先に返してから渡す。
                            codec.releaseOutputBuffer(outputIndex, false)
                            totalPcmBytes += chunk.size
                            onPcmChunk(chunk)
                        } else {
                            codec.releaseOutputBuffer(outputIndex, false)
                        }
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            sawOutputEOS = true
                        }
                    }
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = codec.outputFormat
                        outSampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        outChannels = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        formatNotified = true
                        onOutputFormat(outSampleRate, outChannels)
                    }
                    // MediaCodec.INFO_TRY_AGAIN_LATER: 何もせずループを継続する。
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: AndroidTranscribeError) {
            throw e
        } catch (e: IOException) {
            // 下流(パイプへの書き込み)由来。デコード失敗ではないので包まない。
            throw e
        } catch (e: Exception) {
            throw AndroidTranscribeError.DecodeFailed("デコード中にエラー: ${e.message}")
        } finally {
            runCatching { codec.stop() }
            runCatching { codec.release() }
            runCatching { extractor.release() }
        }

        if (totalPcmBytes == 0L) {
            throw AndroidTranscribeError.DecodeFailed("デコード結果が空である: $path")
        }
    }
}
