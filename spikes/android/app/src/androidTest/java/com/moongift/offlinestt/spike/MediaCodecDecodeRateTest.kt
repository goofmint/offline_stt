package com.moongift.offlinestt.spike

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #14 (design.md §8 未決事項6): 手持ち音源の MediaCodec デコード出力レート調査。
 *
 * test-assets/baseline-audio/ の全クリップ (jaJP_10s/jaJP_3m/enUS_10s/enUS_3m × wav/m4a、計8ファイル)
 * について、MediaExtractor で入力トラックの MediaFormat (KEY_SAMPLE_RATE/KEY_CHANNEL_COUNT/KEY_MIME)を、
 * MediaCodec の出力側 MediaFormat (KEY_SAMPLE_RATE/KEY_CHANNEL_COUNT/KEY_PCM_ENCODING) を記録し、
 * design.md §4.3 の目標形式 (16kHz・モノラル・16-bit PCM) との差分からリサンプリング要否を判定する。
 * さらに実際にデコードしたPCMバイト数から実効サンプルレートを検算し、outputFormat の申告値と
 * 一致するかも確認する。
 *
 * **circular reasoning の回避**: 上記8ファイルはいずれも generate.sh により16kHz・モノラルで
 * *生成された* ものであり、これだけを計測して「リサンプリング不要」と結論づけるのは循環論法になる
 * (16kHz入力をデコードして16kHzが出るのは当然)。実際のユーザー音源(ボイスメモ・会議録音等)は
 * 44.1kHz/48kHzのステレオが一般的であるため、fixtures/generate-rate-fixtures.sh が生成する
 * fixtures/generated/ 配下の実環境相当音源 (44.1kHz/48kHzステレオ、mp3、22.05kHz、8kHz、計7ファイル)
 * も計測対象に加えている。詳細は README.md / RESULTS.md 参照。
 *
 * fixtures/generated/ のファイルは生成スクリプトを実行していない環境では存在しない
 * (コミット対象外)。その場合、当該テストはビルド/テスト全体を失敗させず、Logcatへ明示的に
 * 「スキップした」旨を出力したうえでスキップする (measure() 内の FileNotFoundException 処理参照)。
 *
 * 結果は Logcat タグ [RESULT_TAG] へ1行1JSONで出力する。`adb logcat -s $RESULT_TAG` で回収できる。
 * フォールバック処理は書かない: 想定外の状態(ファイルが存在しない場合を除く)は例外として顕在化させる。
 * `resampleNeeded == true` であってもこのテスト自体は失敗させない。これは調査であって要件検証ではない。
 */
@RunWith(AndroidJUnit4::class)
class MediaCodecDecodeRateTest {

    companion object {
        const val RESULT_TAG = "OfflineSttSpike.M14Result"
        const val LOG_TAG = "OfflineSttSpike.M14"

        // design.md §4.3 の目標形式 (16kHz・モノラル・16-bit PCM)。
        const val TARGET_SAMPLE_RATE = 16000
        const val TARGET_CHANNELS = 1
    }

    data class DecodeMeasurement(
        val clipId: String,
        val format: String,
        val inputMime: String?,
        val inputSampleRate: Int?,
        val inputChannels: Int?,
        val outputSampleRate: Int,
        val outputChannels: Int,
        val outputPcmEncoding: Int?,
        val outputBytes: Long,
        val durationUs: Long?,
        val effectiveSampleRate: Double?,
        val expectedSampleRate: Int,
        val expectedChannels: Int,
        val resampleNeeded: Boolean,
    )

    private fun measure(clipId: String, format: String): DecodeMeasurement? {
        val assetName = "$clipId.$format"
        Log.i(LOG_TAG, "=== 計測開始: $assetName ===")

        val instrumentationContext = InstrumentationRegistry.getInstrumentation().context
        val afd = try {
            instrumentationContext.assets.openFd(assetName)
        } catch (e: java.io.FileNotFoundException) {
            // fixtures/generated/ は generate-rate-fixtures.sh を実行していない環境には存在しない
            // (コミット対象外)。その場合はテストを失敗させず、スキップした旨を明示的にログする
            // (黙って通さない)。test-assets/baseline-audio/ 側の8ファイルはリポジトリにコミット
            // されているため通常この分岐には入らないが、万一欠落していた場合も同様にスキップする。
            val reason = "$assetName が assets に見つからないためスキップした。" +
                "fixtures/generate-rate-fixtures.sh を実行すると生成される (README.md参照)。"
            Log.w(LOG_TAG, "$assetName: SKIPPED - $reason")
            Log.w(
                RESULT_TAG,
                JSONObject().apply {
                    put("clip", clipId)
                    put("format", format)
                    put("skipped", true)
                    put("reason", reason)
                }.toString()
            )
            return null
        }

        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)

            var audioTrackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME)
                if (mime != null && mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    inputFormat = fmt
                    break
                }
            }
            check(audioTrackIndex >= 0 && inputFormat != null) {
                "$assetName: 音声トラックが見つからなかった。"
            }
            extractor.selectTrack(audioTrackIndex)

            val inputMime = inputFormat.getString(MediaFormat.KEY_MIME)
            val inputSampleRate = if (inputFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            } else null
            val inputChannels = if (inputFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else null
            Log.i(
                LOG_TAG,
                "$assetName: 入力MediaFormat mime=$inputMime sampleRate=$inputSampleRate channels=$inputChannels " +
                    "full=$inputFormat"
            )

            checkNotNull(inputMime) { "$assetName: 入力トラックに KEY_MIME が無い。" }
            codec = MediaCodec.createDecoderByType(inputMime)
            codec.configure(inputFormat, null, null, 0)
            codec.start()

            val bufferInfo = MediaCodec.BufferInfo()
            var sawInputEOS = false
            var sawOutputEOS = false
            var outputFormat: MediaFormat? = null
            var totalOutputBytes = 0L
            var maxPresentationTimeUs = 0L
            val timeoutUs = 20_000L
            var idleIterations = 0
            val maxIdleIterations = 2_000 // 約 40 秒分のタイムアウト待ちを上限とする安全弁

            while (!sawOutputEOS) {
                var progressed = false

                if (!sawInputEOS) {
                    val inIndex = codec.dequeueInputBuffer(timeoutUs)
                    if (inIndex >= 0) {
                        val inputBuffer = checkNotNull(codec.getInputBuffer(inIndex)) {
                            "$assetName: getInputBuffer($inIndex) が null。"
                        }
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            sawInputEOS = true
                            Log.i(LOG_TAG, "$assetName: 入力側 EOS を送出した。")
                        } else {
                            val presentationTimeUs = extractor.sampleTime
                            if (presentationTimeUs > maxPresentationTimeUs) {
                                maxPresentationTimeUs = presentationTimeUs
                            }
                            codec.queueInputBuffer(inIndex, 0, sampleSize, presentationTimeUs, 0)
                            extractor.advance()
                        }
                        progressed = true
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(bufferInfo, timeoutUs)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        outputFormat = codec.outputFormat
                        Log.i(LOG_TAG, "$assetName: INFO_OUTPUT_FORMAT_CHANGED -> $outputFormat")
                        progressed = true
                    }
                    outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // 何もしない (次ループで再試行)。
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> {
                        progressed = true
                    }
                    outIndex >= 0 -> {
                        totalOutputBytes += bufferInfo.size
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            sawOutputEOS = true
                            Log.i(LOG_TAG, "$assetName: 出力側 EOS を受信した。totalOutputBytes=$totalOutputBytes")
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        progressed = true
                    }
                }

                if (progressed) {
                    idleIterations = 0
                } else {
                    idleIterations++
                    check(idleIterations < maxIdleIterations) {
                        "$assetName: デコードが進行しないままタイムアウト上限に達した " +
                            "(idleIterations=$idleIterations)。"
                    }
                }
            }

            val finalOutputFormat = checkNotNull(outputFormat) {
                "$assetName: INFO_OUTPUT_FORMAT_CHANGED が一度も発生しなかった。出力MediaFormatを取得できない。"
            }
            val outputSampleRate = finalOutputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val outputChannels = finalOutputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val outputPcmEncoding = if (finalOutputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                finalOutputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
            } else null

            // 実効サンプルレートの検算: 出力バイト数 / (バイト深度 × チャンネル数) / 秒数。
            // バイト深度は KEY_PCM_ENCODING から判定する。未指定の場合、Android のデコーダ出力は
            // 既定で 16-bit PCM (ENCODING_PCM_16BIT = 2) であるため、その前提を明示してログする。
            val bytesPerSample = when (outputPcmEncoding) {
                android.media.AudioFormat.ENCODING_PCM_8BIT -> 1
                android.media.AudioFormat.ENCODING_PCM_FLOAT -> 4
                android.media.AudioFormat.ENCODING_PCM_16BIT, null -> 2
                else -> {
                    Log.w(LOG_TAG, "$assetName: 未知の KEY_PCM_ENCODING=$outputPcmEncoding。16-bit(2バイト)と仮定する。")
                    2
                }
            }
            val durationUs = if (maxPresentationTimeUs > 0) maxPresentationTimeUs else null
            val effectiveSampleRate = if (durationUs != null && durationUs > 0) {
                val bytesPerFrame = bytesPerSample * outputChannels
                (totalOutputBytes.toDouble() / bytesPerFrame) / (durationUs / 1_000_000.0)
            } else null

            val resampleNeeded = outputSampleRate != TARGET_SAMPLE_RATE || outputChannels != TARGET_CHANNELS

            Log.i(
                LOG_TAG,
                "$assetName: 出力MediaFormat sampleRate=$outputSampleRate channels=$outputChannels " +
                    "pcmEncoding=$outputPcmEncoding totalOutputBytes=$totalOutputBytes durationUs=$durationUs " +
                    "effectiveSampleRate=$effectiveSampleRate resampleNeeded=$resampleNeeded"
            )

            val measurement = DecodeMeasurement(
                clipId = clipId,
                format = format,
                inputMime = inputMime,
                inputSampleRate = inputSampleRate,
                inputChannels = inputChannels,
                outputSampleRate = outputSampleRate,
                outputChannels = outputChannels,
                outputPcmEncoding = outputPcmEncoding,
                outputBytes = totalOutputBytes,
                durationUs = durationUs,
                effectiveSampleRate = effectiveSampleRate,
                expectedSampleRate = TARGET_SAMPLE_RATE,
                expectedChannels = TARGET_CHANNELS,
                resampleNeeded = resampleNeeded,
            )
            logResultJson(measurement)
            return measurement
        } finally {
            codec?.stop()
            codec?.release()
            extractor.release()
            afd.close()
        }
    }

    private fun logResultJson(m: DecodeMeasurement) {
        val json = JSONObject().apply {
            put("clip", m.clipId)
            put("format", m.format)
            put("inputMime", m.inputMime)
            put("inputSampleRate", m.inputSampleRate)
            put("inputChannels", m.inputChannels)
            put("outputSampleRate", m.outputSampleRate)
            put("outputChannels", m.outputChannels)
            put("outputPcmEncoding", m.outputPcmEncoding)
            put("outputBytes", m.outputBytes)
            put("durationUs", m.durationUs)
            put("effectiveSampleRate", m.effectiveSampleRate)
            put("expectedSampleRate", m.expectedSampleRate)
            put("expectedChannels", m.expectedChannels)
            put("resampleNeeded", m.resampleNeeded)
        }
        // adb logcat -s OfflineSttSpike.M14Result で1行1JSONとして回収できる。
        Log.i(RESULT_TAG, json.toString())
    }

    @Test fun jaJP_10s_wav() { measure("jaJP_10s", "wav") }
    @Test fun jaJP_10s_m4a() { measure("jaJP_10s", "m4a") }
    @Test fun jaJP_3m_wav() { measure("jaJP_3m", "wav") }
    @Test fun jaJP_3m_m4a() { measure("jaJP_3m", "m4a") }
    @Test fun enUS_10s_wav() { measure("enUS_10s", "wav") }
    @Test fun enUS_10s_m4a() { measure("enUS_10s", "m4a") }
    @Test fun enUS_3m_wav() { measure("enUS_3m", "wav") }
    @Test fun enUS_3m_m4a() { measure("enUS_3m", "m4a") }

    // Issue #14 追加分: 実環境相当音源 (fixtures/generate-rate-fixtures.sh の生成物)。
    // 基準音声(16kHzモノラルで生成されたもの)だけでは循環論法になるため、
    // 44.1kHz/48kHzステレオ・mp3・22.05kHz・8kHzのケースを追加している。
    // 生成スクリプトを実行していない環境では afd が見つからずスキップされる (measure() 参照)。
    @Test fun rate_44100_stereo_wav() { measure("rate_44100_stereo", "wav") }
    @Test fun rate_48000_stereo_wav() { measure("rate_48000_stereo", "wav") }
    @Test fun rate_44100_stereo_m4a() { measure("rate_44100_stereo", "m4a") }
    @Test fun rate_48000_stereo_m4a() { measure("rate_48000_stereo", "m4a") }
    @Test fun rate_44100_stereo_mp3() { measure("rate_44100_stereo", "mp3") }
    @Test fun rate_22050_mono_wav() { measure("rate_22050_mono", "wav") }
    @Test fun rate_8000_mono_wav() { measure("rate_8000_mono", "wav") }
}
