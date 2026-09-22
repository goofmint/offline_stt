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
package com.moongift.offline_stt

import android.content.Context
import android.os.Build
import android.speech.ModelDownloadListener
import android.speech.SpeechRecognizer
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

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
     * 1回の`checkRecognitionSupport()`再照会に許す上限。実機で
     * コールバックが一度も発火しない事例があり(E2E_RESULTS.md の B-4)、
     * 上限が無いとポーリングループ自体が止まる。ポーリング間隔より十分
     * 長く、かつ全体の上限より十分短い値を採る。
     */
    private const val QUERY_TIMEOUT_MS = 15_000L

    /**
     * @param onProgress 不定進捗として`fraction=null`を都度通知する
     *   (Web/Windowsと同様の粒度、design.md §2.2)。呼び出し元
     *   (`OfflineSttApiImpl.runDownload`)は事前に
     *   `ModelAvailability.checkModel`で`downloadable`であることを
     *   確認してから本関数を呼び出す前提であり、本関数自体はその確認を
     *   行わない(Darwin実装の`ModelAcquisition.run`と同じ設計)。
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

            // **デッドラインは querySupport() の前に判定する。** 後ろだけで
            // 判定していると、`querySupport()` が返ってこない限り上限が
            // 一度も評価されない。Pixel 6 実機で実際に11分以上ハングし、
            // MAX_WAIT_MS が機能しないことを確認した
            // (E2E_RESULTS.md の B-4)。
            if (System.currentTimeMillis() > deadline) throw timedOut(locale)

            // `querySupport()` 自体にも上限を設ける。`checkRecognitionSupport()`
            // のコールバックが一度も発火しない事例を実測しており
            // (同 B-4)、その場合 `suspendCancellableCoroutine` は永久に
            // 再開しない。`withTimeoutNull` は内部でコルーチンをキャンセル
            // するため、`querySupport()` の `invokeOnCancellation` が
            // SpeechRecognizer を破棄する。
            val support = withTimeoutOrNull(QUERY_TIMEOUT_MS) {
                ModelAvailability.querySupport(context, locale)
            }
            if (support != null && support.installedOnDeviceLanguages.contains(locale)) {
                onProgress(null, true)
                return
            }
            onProgress(null, false)

            if (System.currentTimeMillis() > deadline) throw timedOut(locale)
        }
    }

    private fun timedOut(locale: String) =
        AndroidTranscribeError.PlatformError(
            "${MAX_WAIT_MS}ms 以内にダウンロードが完了しなかった" +
                "(checkRecognitionSupport()の再照会で installedOnDeviceLanguages に " +
                "$locale が現れなかった)。",
        )

    private suspend fun triggerDownload(context: Context, locale: String) {
        suspendCancellableCoroutine<Unit> { continuation ->
            // `SpeechRecognizer` は生成したら必ず `destroy()` する。要求を
            // 引き渡した時点で本インスタンスの用は済む(完了判定は呼び出し元の
            // ポーリングが担う)ため、同期例外の有無にかかわらず finally で
            // 破棄する。破棄し忘れるとダウンロード要求のたびにインスタンスが
            // 積み上がる。本関数は OfflineSttApiImpl のメインスレッドスコープ
            // 上で実行されるため、`destroy()` のメインスレッド契約も満たす。
            var recognizer: SpeechRecognizer? = null
            try {
                recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // `triggerModelDownload(Intent, Executor, ModelDownloadListener)`
                    // は API 34(UPSIDE_DOWN_CAKE)で追加された overload である。
                    // API 33 でこれを呼ぶと `NoSuchMethodError` になり、下の
                    // catch が握り潰すためダウンロードが始まらないまま
                    // ポーリングだけが上限まで続く。API 33 でも
                    // `checkRecognitionSupport()` は downloadable を返しうる
                    // ため、この経路には実際に到達する。
                    recognizer.triggerModelDownload(
                        ModelAvailability.buildRecognizerIntent(locale),
                        // メインスレッドのExecutorを使う。専用スレッドの
                        // Executor は非デーモンスレッドを作り `shutdown()` も
                        // 呼ばれないため、呼び出しのたびにスレッドが残る。
                        // 下のコールバックはいずれも空であり、専用スレッドを
                        // 用意する理由が無い。
                        context.mainExecutor,
                        object : ModelDownloadListener {
                            // design.md §4.3 のとおりこれらのコールバックは
                            // 完了時に発火しない実測があるため、完了判定には
                            // 使わない。完了判定は呼び出し元のポーリングloopが
                            // 担う。
                            override fun onScheduled() {}

                            override fun onProgress(progress: Int) {}

                            override fun onSuccess() {}

                            override fun onError(error: Int) {}
                        },
                    )
                } else {
                    recognizer.triggerModelDownload(
                        ModelAvailability.buildRecognizerIntent(locale),
                    )
                }
            } catch (t: Throwable) {
                // triggerModelDownload自体の呼び出し失敗は、以降の
                // ポーリングに委ねる(再照会してもinstalledに現れなければ
                // 最終的にMAX_WAIT_MSでタイムアウトする)。ここで例外を
                // 投げて直ちに失敗にはしない。
            } finally {
                runCatching { recognizer?.destroy() }
            }
            if (continuation.isActive) continuation.resumeWith(Result.success(Unit))
        }
    }
}
