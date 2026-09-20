// ModelAvailability.kt
// requirements.md FR-1、Issue #43。
// `SpeechRecognizer.checkRecognitionSupport()`が返す`RecognitionSupport`の
// 4リストを突き合わせてModelStateの4値へ写像する。
// spikes/android/app/src/main/java/com/moongift/offlinestt/spike/
// PlatformSttProbe.ktの検証結果を移植の出発点とした。
//
// ## FR-1(4値)への写像方針(requirements.md FR-1 Android行そのまま)
// 1. `installedOnDeviceLanguages`に対象ロケールが含まれる → available
// 2. `pendingOnDeviceLanguages`に含まれる → downloading
// 3. いずれにも含まれないが`supportedOnDeviceLanguages`に含まれる → downloadable
// 4. いずれにも含まれない → unavailable
//
// `SpeechRecognizer.createOnDeviceSpeechRecognizer()`/
// `checkRecognitionSupport()`はメインスレッドから呼ぶ必要がある
// (design.md §4.3(wt73版)注記9)。呼び出し元(`OfflineSttApiImpl`)は
// `OfflineSttHostApi`のメソッドとして既にFlutterのプラットフォームスレッド
// (Android上はメインスレッドと同一)上で実行されている前提のため、本
// オブジェクトは内部でメインスレッドへの切り替えを行わない。
package com.moongift.offline_stt_android

import android.content.Context
import android.content.Intent
import android.os.Build
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.suspendCancellableCoroutine

object ModelAvailability {

    /** requirements.md FR-1。`OfflineSttApiImpl.checkModel`から呼ばれる。 */
    suspend fun checkModel(context: Context, locale: String): ModelState {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // requirements.md NFR-4はAPI 31以上を最低要件とするが、
            // `checkRecognitionSupport()`自体はAPI 33(TIRAMISU)で追加された
            // APIである(spikes/android/PlatformSttProbe.kt冒頭コメント参照)。
            // API 31/32では4リストを取得する手段が無いため`unavailable`へ
            // 倒す(フォールバックではなく、APIが存在しないことを明示的に
            // 扱った結果である)。
            return ModelState.UNAVAILABLE
        }

        val support = querySupport(context, locale) ?: return ModelState.UNAVAILABLE

        return when {
            support.installedOnDeviceLanguages.contains(locale) -> ModelState.AVAILABLE
            support.pendingOnDeviceLanguages.contains(locale) -> ModelState.DOWNLOADING
            support.supportedOnDeviceLanguages.contains(locale) -> ModelState.DOWNLOADABLE
            else -> ModelState.UNAVAILABLE
        }
    }

    /**
     * `checkRecognitionSupport()`を1回照会する。API未対応・例外・
     * `RecognitionSupportCallback.onError()`はいずれもnullを返す
     * (呼び出し元は`unavailable`として扱う、またはダウンロード完了ポーリング
     * であれば「まだ完了していない」として扱う)。
     */
    suspend fun querySupport(context: Context, locale: String): RecognitionSupport? =
        suspendCancellableCoroutine { continuation ->
            // `SpeechRecognizer` の破棄経路を1箇所に集約する。コールバック・
            // 同期例外・コルーチンのキャンセルのいずれで終わっても、必ず
            // 1回だけ `destroy()` する。
            //
            // 破棄はメインスレッドで行う。`SpeechRecognizer` はメインスレッド
            // から操作する契約であり、違反が例外になると `runCatching` が
            // 握り潰してサービス接続の解放が保証できなくなる。ダウンロード
            // 完了ポーリングは2秒間隔で最大10分続くため、取りこぼしが反復
            // するとインスタンスが積み上がる。
            var recognizer: SpeechRecognizer? = null
            val destroyed = AtomicBoolean(false)
            val mainExecutor = context.mainExecutor
            fun destroyOnce() {
                // 生成前に呼ばれた場合は `destroyed` を立てずに帰る。先に
                // 立ててしまうと、生成とキャンセルが競合したときに
                // 「フラグだけ立って実体は破棄されない」状態になり、以降の
                // destroyOnce() が何もしなくなってリークする。
                val target = recognizer ?: return
                if (!destroyed.compareAndSet(false, true)) return
                mainExecutor.execute { runCatching { target.destroy() } }
            }

            try {
                recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
                // ハンドラの登録は生成後に行う。既にキャンセル済みであれば
                // `invokeOnCancellation` は登録時点で即座にハンドラを実行する
                // ため、生成直後にキャンセルされていても取りこぼさない。
                continuation.invokeOnCancellation { destroyOnce() }
                recognizer.checkRecognitionSupport(
                    buildRecognizerIntent(locale),
                    mainExecutor,
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                            destroyOnce()
                            if (continuation.isActive) {
                                continuation.resumeWith(Result.success(recognitionSupport))
                            }
                        }

                        override fun onError(error: Int) {
                            destroyOnce()
                            if (continuation.isActive) continuation.resumeWith(Result.success(null))
                        }
                    },
                )
            } catch (t: Throwable) {
                destroyOnce()
                if (continuation.isActive) continuation.resumeWith(Result.success(null))
            }
        }

    /**
     * design.md §4.3(wt73版): `EXTRA_PREFER_OFFLINE = true`
     * (requirements.md NFR-2のオフライン方針)。
     */
    fun buildRecognizerIntent(locale: String): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }
}
