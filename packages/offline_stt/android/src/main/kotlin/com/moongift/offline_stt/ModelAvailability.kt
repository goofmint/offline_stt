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
package com.moongift.offline_stt

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Looper
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.suspendCancellableCoroutine

object ModelAvailability {

    /**
     * `checkRecognitionSupport()` の照会結果。
     *
     * **「照会できて、対象ロケールがどのリストにも無い」と「そもそも照会に
     * 失敗した」を区別するための型である。** 以前は両方とも `null` を返して
     * いたため、`checkModel()` が失敗を `unavailable` に畳んでいた。Pixel 6
     * 実機で `checkModel()` を連続呼び出しすると 17〜20%(B-1 修正後も
     * 2/30 = 6.7%)の確率で偽の `unavailable` が返り、その理由がどこにも
     * 残らなかった(E2E_RESULTS.md の B-2)。
     */
    sealed interface SupportQuery {
        data class Success(val support: RecognitionSupport) : SupportQuery

        /**
         * 照会そのものが失敗した。[errorCode] は
         * `RecognitionSupportCallback.onError()` が返した
         * `SpeechRecognizer.ERROR_*`。同期例外で失敗した場合は null。
         */
        data class Failed(val errorCode: Int?, val cause: Throwable? = null) : SupportQuery
    }

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

        // **照会の失敗を一律に `unavailable` へ畳まない。** 端末が対応して
        // いないことと、照会が一時的に失敗したことは別である。後者を前者と
        // して返すと、利用者に「この端末では使えない」という誤った結論を
        // 与え、しかも原因がどこにも残らない(E2E_RESULTS.md の B-2)。
        //
        // ただし `onError()` の中には「照会は成立していて、答えが否定的」と
        // 解釈すべきものがある。両者を分けて扱う。
        when (val query = querySupportDetailed(context, locale)) {
            is SupportQuery.Success -> return classify(query.support, locale)
            is SupportQuery.Failed -> {
                when (query.errorCode) {
                    // 対象ロケールについての確定的な否定応答。FR-1 の
                    // `unavailable`(終端状態)がそのまま当てはまる。
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                    SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
                    -> return ModelState.UNAVAILABLE
                    // 「対応状況を判定できない」ことを示す定数。端末側の
                    // 問題であり、`AndroidTranscribeError.DeviceUnsupported`
                    // の定義がこれを名指ししている。
                    SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT ->
                        throw AndroidTranscribeError.DeviceUnsupported(
                            "ERROR_CANNOT_CHECK_SUPPORT(${query.errorCode})",
                        )
                }
                // それ以外(ERROR_RECOGNIZER_BUSY / ERROR_SERVER_DISCONNECTED
                // / ERROR_CLIENT など)は一時的な失敗である。明示的なエラーに
                // して呼び出し側が再試行できるようにする。
                val detail = query.errorCode
                    ?.let { "${ErrorMapping.errorName(it)}($it)" }
                    ?: "同期例外: ${query.cause}"
                throw AndroidTranscribeError.PlatformError(
                    "checkRecognitionSupport() の照会に失敗した($detail)。" +
                        "端末が対応していないという意味ではない。再試行すること。",
                )
            }
        }
    }

    /**
     * requirements.md FR-5。`OfflineSttApiImpl.supportedLocales` から呼ばれる。
     *
     * `RecognitionSupport` の3リスト
     * (`supportedOnDeviceLanguages`(要ダウンロード) /
     * `installedOnDeviceLanguages`(導入済み) /
     * `pendingOnDeviceLanguages`(取得中))の **和集合** を返す。
     * `getOnlineLanguages()` は `createOnDeviceSpeechRecognizer()` では空が
     * 期待される(オンデバイス認識の対応言語ではない)ため**除外する**。
     *
     * 返すのは「この端末が扱えるロケールの集合」であり、`available` な
     * ロケールの一覧ではない。未ダウンロードのロケールも含む。
     *
     * **空リストを返さない。** 列挙できない場合は必ず例外を投げる。
     * 「端末が1言語も扱えない」ことと「列挙する手段が無い/照会に失敗した」
     * ことを空リストへ畳むと、呼び出し側が前者だと誤解し、しかも原因が
     * どこにも残らない([checkModel] の `SupportQuery.Failed` 分岐と同じ
     * 理由である)。
     */
    suspend fun supportedLocales(context: Context): List<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // `checkRecognitionSupport()` とそれが返す `RecognitionSupport`
            // の4メソッドはいずれも API 33(TIRAMISU)で追加された。API 31/32
            // には対応ロケールを列挙する手段そのものが存在しない。
            // [checkModel] は同じ状況で `unavailable`(FR-1 の終端状態)を
            // 返すが、一覧には「対応ロケールが無い」を表す正しい値が無い
            // (空リストは上記のとおり誤解を招く)ため、ここは明示的な
            // エラーにする。
            throw AndroidTranscribeError.DeviceUnsupported(
                "対応ロケールの列挙には API 33 以上が必要である" +
                    "(現在: API ${Build.VERSION.SDK_INT})。",
            )
        }

        when (val query = querySupportDetailed(context, locale = null)) {
            is SupportQuery.Success -> {
                val support = query.support
                // 3リストの和集合。`LinkedHashSet` により重複を除きつつ
                // 「導入済み → 取得中 → 要ダウンロード」の順序を保つ。
                val union = LinkedHashSet<String>()
                union.addAll(support.installedOnDeviceLanguages)
                union.addAll(support.pendingOnDeviceLanguages)
                union.addAll(support.supportedOnDeviceLanguages)
                if (union.isEmpty()) {
                    throw AndroidTranscribeError.DeviceUnsupported(
                        "checkRecognitionSupport() は成功したが、" +
                            "オンデバイス認識の対応ロケールが1つも無い。",
                    )
                }
                return union.toList()
            }
            is SupportQuery.Failed -> {
                if (query.errorCode == SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT) {
                    throw AndroidTranscribeError.DeviceUnsupported(
                        "ERROR_CANNOT_CHECK_SUPPORT(${query.errorCode})",
                    )
                }
                val detail = query.errorCode
                    ?.let { "${ErrorMapping.errorName(it)}($it)" }
                    ?: "同期例外: ${query.cause}"
                throw AndroidTranscribeError.PlatformError(
                    "checkRecognitionSupport() の照会に失敗した($detail)。" +
                        "端末が対応していないという意味ではない。再試行すること。",
                )
            }
        }
    }

    private fun classify(support: RecognitionSupport, locale: String): ModelState {
        return when {
            support.installedOnDeviceLanguages.contains(locale) -> ModelState.AVAILABLE
            support.pendingOnDeviceLanguages.contains(locale) -> ModelState.DOWNLOADING
            support.supportedOnDeviceLanguages.contains(locale) -> ModelState.DOWNLOADABLE
            else -> ModelState.UNAVAILABLE
        }
    }

    /**
     * ダウンロード完了ポーリング用。照会できなければ `null` を返す
     * (「まだ完了していない」として扱う)。失敗理由が要る場合は
     * [querySupportDetailed] を使うこと。
     */
    suspend fun querySupport(context: Context, locale: String): RecognitionSupport? =
        (querySupportDetailed(context, locale) as? SupportQuery.Success)?.support

    /**
     * `checkRecognitionSupport()`を1回照会する。API未対応・例外・
     * `RecognitionSupportCallback.onError()`はいずれもnullを返す
     * (呼び出し元は`unavailable`として扱う、またはダウンロード完了ポーリング
     * であれば「まだ完了していない」として扱う)。
     */
    suspend fun querySupportDetailed(context: Context, locale: String?): SupportQuery =
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
                // **既にメインスレッド上ならその場で破棄する。** post すると
                // 現在のメッセージ処理の「後」に回るため、コールバックが
                // continuation を再開 → 呼び出し元が認識用の SpeechRecognizer を
                // 生成 → その後に本インスタンスが破棄される、という順序になる。
                // Pixel 6 実機ではこの順序で音声認識サービスの接続が切れ、
                // 直後の `startListening()` が ERROR_SERVER_DISCONNECTED(11) で
                // 即座に失敗した(20回中17回。E2E_RESULTS.md の B-1)。
                // `checkRecognitionSupport()` のコールバックは本関数が渡した
                // mainExecutor 上で走るため、通常はこの分岐に入る。
                if (Looper.myLooper() == Looper.getMainLooper()) {
                    runCatching { target.destroy() }
                } else {
                    // キャンセル経路など、メインスレッド以外から呼ばれた場合。
                    // `SpeechRecognizer` はメインスレッドから操作する契約で
                    // あるため post する。
                    mainExecutor.execute { runCatching { target.destroy() } }
                }
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
                                continuation.resumeWith(
                                    Result.success(SupportQuery.Success(recognitionSupport)),
                                )
                            }
                        }

                        override fun onError(error: Int) {
                            destroyOnce()
                            if (continuation.isActive) {
                                continuation.resumeWith(
                                    Result.success(SupportQuery.Failed(errorCode = error)),
                                )
                            }
                        }
                    },
                )
            } catch (t: Throwable) {
                destroyOnce()
                if (continuation.isActive) {
                    continuation.resumeWith(
                        Result.success(SupportQuery.Failed(errorCode = null, cause = t)),
                    )
                }
            }
        }

    /**
     * design.md §4.3(wt73版): `EXTRA_PREFER_OFFLINE = true`
     * (requirements.md NFR-2のオフライン方針)。
     */
    fun buildRecognizerIntent(locale: String?): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            // [supportedLocales] は特定のロケールについて尋ねているわけでは
            // ないため `null` を渡す。その場合 `EXTRA_LANGUAGE` を付けず、
            // 認識サービス側の既定ロケールで照会させる(`RecognitionSupport`
            // の3リストは `EXTRA_LANGUAGE` を入れても絞られないことを
            // Pixel 6 実機で確認済みである)。
            if (locale != null) putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }
}
