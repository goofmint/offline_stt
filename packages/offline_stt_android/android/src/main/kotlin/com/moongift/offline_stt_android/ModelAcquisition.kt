// ModelAcquisition.kt
// requirements.md FR-2、Issue #43。
//
// design.md §4.3(wt73版)・requirements.md FR-2:
// 「SpeechRecognizer.triggerModelDownload(intent, executor,
// ModelDownloadListener)でOS管理の言語パック取得をトリガーする。
// ModelDownloadListenerのonScheduled/onProgress/onSuccess/onErrorは
// ダウンロード完了時に発火しない実測がある(Pixel 6実機でja-JP言語パックを
// 取得した際、onScheduled()のみ発火し、以降60秒以内に他のコールバックが
// 一切到達しなかった。しかし直後に再照会すると実際にはダウンロードが完了
// していた)。そのため完了判定はコールバックに依らず、
// checkRecognitionSupport()を再照会しinstalledOnDeviceLanguagesに対象
// ロケールが現れたかで行う」。
//
// spikes/android/app/src/main/java/com/moongift/offlinestt/spike/
// PlatformSttHarness.kt(triggerJaJpModelDownload)を移植の出発点とした。
package com.moongift.offline_stt_android

import android.content.Context
import android.speech.ModelDownloadListener
import android.speech.SpeechRecognizer
import java.util.concurrent.Executors
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine

object ModelAcquisition {
    private const val POLL_INTERVAL_MS = 2_000L

    // design.md自体には明記が無いが、上記のとおりModelDownloadListenerの
    // コールバックが実測で信頼できない以上、checkRecognitionSupport()の
    // 再照会ポーリングに完全に依存する設計になる。OS側のダウンロードが
    // 何らかの理由で永久に完了しない場合にStreamが無期限にハングし続ける
    // ことを避けるため、上限時間を設ける。design.md未記載の値であるが、
    // 「フォールバック処理は絶対禁止」は「設定不能時に無言でデフォルト値へ
    // 逃げること」を指すものであり、本タイムアウトは逆に「完了しない場合に
    // 明確なエラーを出す」ためのものなので方針に反しない。
    private const val MAX_WAIT_MS = 10 * 60 * 1_000L

    /**
     * @param onProgress 不定進捗として`fraction=null`を都度通知する
     *   (Web/Windowsと同様の粒度、design.md §2.2)。呼び出し元
     *   (`OfflineSttApiImpl.runDownload`)は事前に
     *   `ModelAvailability.checkModel`で`downloadable`であることを
     *   確認してから本関数を呼び出す前提であり、本関数自体はその確認を
     *   行わない(offline_stt_darwinの`ModelAcquisition.run`と同じ設計)。
     */
    suspend fun run(
        context: Context,
        locale: String,
        onProgress: suspend (fraction: Double?, completed: Boolean) -> Unit,
    ) {
        onProgress(null, false)

        triggerDownload(context, locale)

        val deadline = System.currentTimeMillis() + MAX_WAIT_MS
        while (coroutineContext.isActive) {
            delay(POLL_INTERVAL_MS)
            val support = ModelAvailability.querySupport(context, locale)
            if (support != null && support.installedOnDeviceLanguages.contains(locale)) {
                onProgress(null, true)
                return
            }
            if (System.currentTimeMillis() > deadline) {
                throw AndroidTranscribeError.PlatformError(
                    "${MAX_WAIT_MS}ms 以内にダウンロードが完了しなかった" +
                        "(checkRecognitionSupport()の再照会で installedOnDeviceLanguages に " +
                        "$locale が現れなかった)。",
                )
            }
        }
    }

    private suspend fun triggerDownload(context: Context, locale: String) {
        suspendCancellableCoroutine<Unit> { continuation ->
            try {
                val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                recognizer.triggerModelDownload(
                    ModelAvailability.buildRecognizerIntent(locale),
                    Executors.newSingleThreadExecutor(),
                    object : ModelDownloadListener {
                        // design.md §4.3(wt73版)のとおりこれらのコールバックは
                        // 完了時に発火しない実測があるため、完了判定には使わず
                        // ログの意味合いでのみ持つ。完了判定は呼び出し元の
                        // ポーリングloopが担う。
                        override fun onScheduled() {}

                        override fun onProgress(progress: Int) {}

                        override fun onSuccess() {}

                        override fun onError(error: Int) {}
                    },
                )
            } catch (t: Throwable) {
                // triggerModelDownload自体の呼び出し失敗は、以降の
                // ポーリングに委ねる(再照会してもinstalledに現れなければ
                // 最終的にMAX_WAIT_MSでタイムアウトする)。ここで例外を
                // 投げて直ちに失敗にはしない。
            }
            if (continuation.isActive) continuation.resumeWith(Result.success(Unit))
        }
    }
}
