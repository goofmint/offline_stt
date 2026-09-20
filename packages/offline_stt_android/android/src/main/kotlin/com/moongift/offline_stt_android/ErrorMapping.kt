// ErrorMapping.kt
// `RecognitionListener.onError(error: Int)`が返す`SpeechRecognizer.ERROR_*`
// 定数をAndroidTranscribeErrorへ写像する(requirements.md FR-6、Issue #49)。
//
// PR #73のdesign.md §8未決事項7・requirements.md FR-6は「各ERROR_*定数と
// 共通例外の対応付けは実機でエラーを実発火させたわけではないためM3実装時に
// 確定させる必要がある」としており、本ファイルの対応表は暫定である。
// 明確に共通エラー型へ対応付けられるものだけを個別分類し、残りは
// PlatformError(design.md §2.2の「上記のいずれにも分類できないプラット
// フォーム固有のエラー」のバケツ)へ落とす。これはフォールバック(設定不能時
// に無言でデフォルト値へ逃げること)ではなく、design.mdが定める分類その
// ものである。番号(`errorCode`)は必ずメッセージへ残し、原因調査を妨げない
// ようにする。
package com.moongift.offline_stt_android

import android.speech.SpeechRecognizer

object ErrorMapping {
    fun map(errorCode: Int): AndroidTranscribeError = when (errorCode) {
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ->
            AndroidTranscribeError.LocaleUnsupported("${errorName(errorCode)}($errorCode)")
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
            AndroidTranscribeError.ModelUnavailable("${errorName(errorCode)}($errorCode)")
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT ->
            AndroidTranscribeError.DeviceUnsupported("${errorName(errorCode)}($errorCode)")
        else ->
            AndroidTranscribeError.PlatformError("${errorName(errorCode)}($errorCode)")
    }

    /** ログ・エラーメッセージ可読性のための`ERROR_*`定数名変換
     * (spikes/android/PlatformSttHarness.ktの`errorName()`を踏襲)。 */
    fun errorName(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "ERROR_AUDIO"
        SpeechRecognizer.ERROR_CLIENT -> "ERROR_CLIENT"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "ERROR_INSUFFICIENT_PERMISSIONS"
        SpeechRecognizer.ERROR_NETWORK -> "ERROR_NETWORK"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "ERROR_NETWORK_TIMEOUT"
        SpeechRecognizer.ERROR_NO_MATCH -> "ERROR_NO_MATCH"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "ERROR_RECOGNIZER_BUSY"
        SpeechRecognizer.ERROR_SERVER -> "ERROR_SERVER"
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "ERROR_SERVER_DISCONNECTED"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "ERROR_SPEECH_TIMEOUT"
        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "ERROR_TOO_MANY_REQUESTS"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "ERROR_LANGUAGE_NOT_SUPPORTED"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "ERROR_LANGUAGE_UNAVAILABLE"
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "ERROR_CANNOT_CHECK_SUPPORT"
        SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS ->
            "ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS"
        else -> "UNKNOWN($code)"
    }
}
