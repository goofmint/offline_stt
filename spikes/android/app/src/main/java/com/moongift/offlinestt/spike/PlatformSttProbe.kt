// PlatformSttProbe.kt
// ML Kit GenAI が使えない端末向けの代替案調査(Android 標準 SpeechRecognizer)。
//
// ML Kit GenAI Speech Recognition は AICore を必要とし、Pixel 6 では Play ストアが
// 「このアプリはお使いのデバイスに対応しなくなりました」と明示する(spikes/android/RESULTS.md 参照)。
// そこで、モデルを同梱せず OS 側が持つ認識エンジンを使うという requirements.md の方針
// (NFR-3)を維持したまま利用できる代替として、Android 標準の
// `android.speech.SpeechRecognizer` のオンデバイス認識を調査する。
//
// 本ファイルは「使えるかどうか」を実機で確かめるための照会専用であり、
// 認識セッションそのものは別途実装する。
package com.moongift.offlinestt.spike

import android.content.Context
import android.content.Intent
import android.os.Build
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** 照会結果。RESULTS.md への転記に使う。 */
data class PlatformSttProbeResult(
    val sdkInt: Int,
    val isRecognitionAvailable: Boolean,
    val isOnDeviceRecognitionAvailable: Boolean?,
    val supportedOnDeviceLanguages: List<String>?,
    val installedOnDeviceLanguages: List<String>?,
    val pendingOnDeviceLanguages: List<String>?,
    val onlineLanguages: List<String>?,
    val supportError: Int?,
    val failure: String?,
)

object PlatformSttProbe {

    /**
     * `SpeechRecognizer` のオンデバイス認識が利用可能か、どの言語が使えるかを照会する。
     *
     * `checkRecognitionSupport()` は API 33 以上でのみ利用できる。それ未満では
     * 言語一覧を取得する手段が無いため null を返す。
     */
    fun run(context: Context, timeoutMs: Long = 15_000): PlatformSttProbeResult {
        val sdk = Build.VERSION.SDK_INT
        val available = SpeechRecognizer.isRecognitionAvailable(context)
        SpikeLog.info("SpeechRecognizer.isRecognitionAvailable() = $available")

        if (sdk < Build.VERSION_CODES.TIRAMISU) {
            SpikeLog.warn("API 33 未満のため checkRecognitionSupport() を呼べない。")
            return PlatformSttProbeResult(
                sdkInt = sdk,
                isRecognitionAvailable = available,
                isOnDeviceRecognitionAvailable = null,
                supportedOnDeviceLanguages = null,
                installedOnDeviceLanguages = null,
                pendingOnDeviceLanguages = null,
                onlineLanguages = null,
                supportError = null,
                failure = "API 33 未満",
            )
        }

        val onDeviceAvailable = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        SpikeLog.info("SpeechRecognizer.isOnDeviceRecognitionAvailable() = $onDeviceAvailable")

        var support: RecognitionSupport? = null
        var errorCode: Int? = null
        var failure: String? = null
        val latch = CountDownLatch(1)

        // createOnDeviceSpeechRecognizer() はメインスレッドから呼ぶ必要がある。
        val main = android.os.Handler(context.mainLooper)
        main.post {
            try {
                val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ja-JP")
                    // requirements.md NFR-2: ネットワーク送信を禁ずる方針のためオフラインを要求する。
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
                recognizer.checkRecognitionSupport(
                    intent,
                    Executors.newSingleThreadExecutor(),
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                            support = recognitionSupport
                            latch.countDown()
                        }

                        override fun onError(error: Int) {
                            errorCode = error
                            latch.countDown()
                        }
                    },
                )
            } catch (t: Throwable) {
                failure = "${t.javaClass.simpleName}: ${t.message}"
                latch.countDown()
            }
        }

        if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) {
            failure = "checkRecognitionSupport() が ${timeoutMs}ms 以内に応答しなかった"
        }

        val s = support
        return PlatformSttProbeResult(
            sdkInt = sdk,
            isRecognitionAvailable = available,
            isOnDeviceRecognitionAvailable = onDeviceAvailable,
            supportedOnDeviceLanguages = s?.supportedOnDeviceLanguages,
            installedOnDeviceLanguages = s?.installedOnDeviceLanguages,
            pendingOnDeviceLanguages = s?.pendingOnDeviceLanguages,
            onlineLanguages = s?.onlineLanguages,
            supportError = errorCode,
            failure = failure,
        )
    }
}
