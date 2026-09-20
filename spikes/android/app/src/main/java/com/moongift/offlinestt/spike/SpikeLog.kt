package com.moongift.offlinestt.spike

import android.util.Log

/**
 * 全段階ログの共通ユーティリティ。spikes/web/spike.js の `log(message, level)` 方針
 * (info/ok/ng/warn の色分け、Logcat と画面の両方へ出力、フォールバックはしない) を踏襲する。
 *
 * `sink` を差し替えることで、画面上のログ領域にも同じ行を流し込める。
 */
object SpikeLog {

    const val TAG = "OfflineSttSpike"

    enum class Level { INFO, OK, NG, WARN }

    var sink: ((Level, String) -> Unit)? = null

    fun info(message: String) = emit(Level.INFO, message)
    fun ok(message: String) = emit(Level.OK, message)
    fun ng(message: String) = emit(Level.NG, message)
    fun warn(message: String) = emit(Level.WARN, message)

    private fun emit(level: Level, message: String) {
        when (level) {
            Level.INFO -> Log.i(TAG, message)
            Level.OK -> Log.i(TAG, "[OK] $message")
            Level.NG -> Log.e(TAG, message)
            Level.WARN -> Log.w(TAG, message)
        }
        sink?.invoke(level, message)
    }
}
