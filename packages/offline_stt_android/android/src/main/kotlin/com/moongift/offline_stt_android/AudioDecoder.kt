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
package com.moongift.offline_stt_android

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.isActive

object AudioDecoder {
    private const val TIMEOUT_US = 10_000L

    data class DecodedAudio(
        val sampleRate: Int,
        val channelCount: Int,
        /** 16-bit signed PCM、リトルエンディアン、インターリーブ。 */
        val pcm: ByteArray,
    )

    suspend fun decodeToPcm16(path: String): DecodedAudio {
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
        val codec: MediaCodec
        try {
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(inputFormat, null, null, 0)
            codec.start()
        } catch (e: Exception) {
            extractor.release()
            throw AndroidTranscribeError.DecodeFailed(
                "MediaCodec初期化失敗(mime=$mime): ${e.message}",
            )
        }

        // 入力側MediaFormatの値を初期値とし、INFO_OUTPUT_FORMAT_CHANGEDが
        // 通知された場合はデコーダの実際の出力フォーマットで上書きする。
        var outSampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var outChannels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val output = ByteArrayOutputStream()
        val bufferInfo = MediaCodec.BufferInfo()
        var sawInputEOS = false
        var sawOutputEOS = false

        try {
            while (!sawOutputEOS) {
                if (!coroutineContext.isActive) {
                    throw CancellationException("AudioDecoder.decodeToPcm16 cancelled")
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
                            output.write(chunk)
                        }
                        codec.releaseOutputBuffer(outputIndex, false)
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            sawOutputEOS = true
                        }
                    }
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = codec.outputFormat
                        outSampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        outChannels = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    // MediaCodec.INFO_TRY_AGAIN_LATER: 何もせずループを継続する。
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: AndroidTranscribeError) {
            throw e
        } catch (e: Exception) {
            throw AndroidTranscribeError.DecodeFailed("デコード中にエラー: ${e.message}")
        } finally {
            runCatching { codec.stop() }
            runCatching { codec.release() }
            runCatching { extractor.release() }
        }

        if (output.size() == 0) {
            throw AndroidTranscribeError.DecodeFailed("デコード結果が空である: $path")
        }

        return DecodedAudio(
            sampleRate = outSampleRate,
            channelCount = outChannels,
            pcm = output.toByteArray(),
        )
    }
}
