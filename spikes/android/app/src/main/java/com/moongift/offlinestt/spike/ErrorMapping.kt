package com.moongift.offlinestt.spike

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException

/**
 * design.md §5「エラーマッピング表」の Android 列への写像。
 *
 *   | 共通例外            | Android                                  |
 *   |---------------------|-------------------------------------------|
 *   | ModelUnavailable    | FeatureStatus.UNAVAILABLE / AICore 606     |
 *   | LocaleUnsupported   | ロケール非対応ステータス                    |
 *   | DecodeFailed        | MediaCodecエラー                            |
 *   | DeviceUnsupported   | ブートローダーアンロック / API<31           |
 *   | Cancelled           | Flow cancel                                |
 *
 * `com.google.mlkit.genai.common.GenAiException.ErrorCode` は上表の「共通例外」と1対1対応する
 * enum ではないため、本ファイルで実測しながら対応関係を決め打ちせずログに残す方針を取る
 * (CLAUDE.md: 「存在しないAPIを使わない」「フォールバック処理は絶対禁止」に従い、未確認の対応は
 * 断定せず `PlatformError` 相当としてそのまま出力する)。
 *
 * 「AICore 606」等の数値エラーコードは、この AAR が公開する `GenAiException.ErrorCode` の
 * 定数一覧 (UNKNOWN/REQUEST_PROCESSING_ERROR/CANCELLED/NOT_AVAILABLE/BUSY/
 * RESPONSE_PROCESSING_ERROR/REQUEST_TOO_LARGE/REQUEST_TOO_SMALL/RESPONSE_GENERATION_ERROR/
 * PER_APP_BATTERY_USE_QUOTA_EXCEEDED/BACKGROUND_USE_BLOCKED/NOT_ENOUGH_DISK_SPACE/
 * NEEDS_SYSTEM_UPDATE/AICORE_INCOMPATIBLE/INVALID_INPUT_IMAGE/CACHE_PROCESSING_ERROR) には
 * 含まれていない (`genai-speech-recognition:1.0.0-alpha1` / `genai-common:1.0.0-beta3` の
 * classes.jar を javap で実際に確認した結果)。601/606 のような AICore 固有コードは、OS/AICore
 * 側がより下位のレイヤで報告するものである可能性が高く、本ライブラリの公開 API からは
 * `GenAiException.errorCode` や例外メッセージ経由でしか観測できない可能性がある。したがって
 * 本実装は例外メッセージ/cause チェーンから数値コードらしき文字列を検出したら、それをそのまま
 * ログへ残すだけに留め、独自の対応関係を捏造しない。
 */
object ErrorMapping {

    enum class CommonException {
        MODEL_UNAVAILABLE,
        LOCALE_UNSUPPORTED,
        DECODE_FAILED,
        DEVICE_UNSUPPORTED,
        CANCELLED,
        PLATFORM_ERROR_UNCLASSIFIED,
    }

    fun featureStatusName(status: Int): String = when (status) {
        FeatureStatus.UNAVAILABLE -> "UNAVAILABLE"
        FeatureStatus.DOWNLOADABLE -> "DOWNLOADABLE"
        FeatureStatus.DOWNLOADING -> "DOWNLOADING"
        FeatureStatus.AVAILABLE -> "AVAILABLE"
        else -> "UNKNOWN($status)"
    }

    /** checkStatus() の戻り値を design.md §5 の区分へ写像する。available/downloadable/downloading は例外ではない。 */
    fun classifyFeatureStatus(status: Int): CommonException? = when (status) {
        FeatureStatus.UNAVAILABLE -> CommonException.MODEL_UNAVAILABLE
        else -> null
    }

    fun errorCodeName(code: Int): String = when (code) {
        GenAiException.ErrorCode.UNKNOWN -> "UNKNOWN"
        GenAiException.ErrorCode.REQUEST_PROCESSING_ERROR -> "REQUEST_PROCESSING_ERROR"
        GenAiException.ErrorCode.CANCELLED -> "CANCELLED"
        GenAiException.ErrorCode.NOT_AVAILABLE -> "NOT_AVAILABLE"
        GenAiException.ErrorCode.BUSY -> "BUSY"
        GenAiException.ErrorCode.RESPONSE_PROCESSING_ERROR -> "RESPONSE_PROCESSING_ERROR"
        GenAiException.ErrorCode.REQUEST_TOO_LARGE -> "REQUEST_TOO_LARGE"
        GenAiException.ErrorCode.REQUEST_TOO_SMALL -> "REQUEST_TOO_SMALL"
        GenAiException.ErrorCode.RESPONSE_GENERATION_ERROR -> "RESPONSE_GENERATION_ERROR"
        GenAiException.ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED -> "PER_APP_BATTERY_USE_QUOTA_EXCEEDED"
        GenAiException.ErrorCode.BACKGROUND_USE_BLOCKED -> "BACKGROUND_USE_BLOCKED"
        GenAiException.ErrorCode.NOT_ENOUGH_DISK_SPACE -> "NOT_ENOUGH_DISK_SPACE"
        GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE -> "NEEDS_SYSTEM_UPDATE"
        GenAiException.ErrorCode.AICORE_INCOMPATIBLE -> "AICORE_INCOMPATIBLE"
        GenAiException.ErrorCode.INVALID_INPUT_IMAGE -> "INVALID_INPUT_IMAGE"
        GenAiException.ErrorCode.CACHE_PROCESSING_ERROR -> "CACHE_PROCESSING_ERROR"
        else -> "UNKNOWN_CODE($code)"
    }

    /**
     * GenAiException を design.md §5 の区分へ写像する。実機で未観測のコードは
     * PLATFORM_ERROR_UNCLASSIFIED とし、errorCodeName() で実測値をログへ残す
     * (捏造しない。RESULTS.md には実機で観測できたものだけを「確定」として記載する)。
     */
    fun classify(e: GenAiException): CommonException {
        val name = errorCodeName(e.errorCode)
        SpikeLog.info("ErrorMapping.classify: errorCode=${e.errorCode} ($name), message=${e.message}")
        scanForAiCoreNumericCode(e)

        return when (e.errorCode) {
            GenAiException.ErrorCode.CANCELLED -> CommonException.CANCELLED
            GenAiException.ErrorCode.NOT_AVAILABLE -> CommonException.MODEL_UNAVAILABLE
            GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE -> CommonException.MODEL_UNAVAILABLE
            GenAiException.ErrorCode.AICORE_INCOMPATIBLE -> CommonException.DEVICE_UNSUPPORTED
            else -> CommonException.PLATFORM_ERROR_UNCLASSIFIED
        }
    }

    /** メッセージ/causeチェーンに "601"/"606" 等の数値コードらしき文字列が含まれていないか調べ、ログに残すのみ。 */
    private fun scanForAiCoreNumericCode(e: Throwable) {
        var cur: Throwable? = e
        var depth = 0
        val numericPattern = Regex("\\b\\d{3}\\b")
        while (cur != null && depth < 8) {
            val msg = cur.message
            if (msg != null) {
                val found = numericPattern.findAll(msg).map { it.value }.toList()
                if (found.isNotEmpty()) {
                    SpikeLog.warn(
                        "ErrorMapping: 例外メッセージに数値コードらしき文字列を検出: $found " +
                            "(class=${cur.javaClass.name}, message=$msg)。design.mdの『AICore 606』等の" +
                            "コードとの対応は未確認のため、断定せずそのまま記録する。"
                    )
                }
            }
            cur = cur.cause
            depth++
        }
    }

    /** API<31 は Gradle の minSdk=31 で既にビルド時に排除されるため、実行時到達コードとしては
     * ブートローダーアンロック検知など別経路が必要になる。本スパイクの範囲では、
     * checkStatus()/download()/startRecognition() から得られる例外のみを対象とする。
     */
    fun deviceApiLevelSupported(sdkInt: Int): Boolean = sdkInt >= 31
}
