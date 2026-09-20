// AndroidTranscribeError.kt
// requirements.md FR-6の共通エラー型への分類(Issue #49)。
//
// design.md §5(このブランチのdesign.mdはML Kit GenAI Speech Recognition版の
// 古いエラーマッピング表であり、標準android.speech.SpeechRecognizerの
// ERROR_*定数には未対応。正しい設計はPR #73のdesign.md §4.3・§5にある)。
//
// offline_stt_darwinのDarwinTranscribeError.swiftのKotlin版。design.md §2.2
// のTranscribeException sealed階層(ModelUnavailable/LocaleUnsupported/
// DecodeFailed/DeviceUnsupported/Cancelled/PlatformError)にそのまま対応
// させる6値のみを持つ。
package com.moongift.offline_stt_android

sealed class AndroidTranscribeError(open val detailMessage: String?) : Exception() {
    /**
     * `ERROR_CANNOT_CHECK_SUPPORT`。
     *
     * **API 31/32 はここに含まれない。** `checkRecognitionSupport()` は
     * API 33(TIRAMISU)で追加されたAPIであり、API 31/32 では FR-1 の4値を
     * 決める手段そのものが無い。そのため `ModelAvailability.checkModel()` は
     * `ModelState.UNAVAILABLE` を返す。これは Darwin が OS 26 未満で
     * `unavailable` を返すのと同じ「OSバージョンゲート」であり、
     * design.md §4.2 の扱いと揃えている。
     *
     * 結果として API 31/32 の利用者が Dart 側で受け取るのは
     * `DeviceUnsupportedException` ではなく、`checkModel()` の戻り値
     * `ModelState.unavailable`(および `transcribeFile()` 時の
     * `ModelUnavailableException`)である。ダウンロード導線も出ない。
     * 端末が対応していないという事実は同じであり、`unavailable` は
     * requirements.md FR-1 の定義どおり終端状態である。
     */
    data class DeviceUnsupported(override val detailMessage: String) :
        AndroidTranscribeError(detailMessage)

    /**
     * 対象ロケールのモデルが利用できない状態で`transcribeFile()`が呼ばれた
     * 場合、または`ERROR_LANGUAGE_UNAVAILABLE`。
     */
    data class ModelUnavailable(override val detailMessage: String) :
        AndroidTranscribeError(detailMessage)

    /** `ERROR_LANGUAGE_NOT_SUPPORTED`(supportedOnDeviceLanguages外)。 */
    data class LocaleUnsupported(override val detailMessage: String) :
        AndroidTranscribeError(detailMessage)

    /** `MediaExtractor`/`MediaCodec`のデコードエラー。 */
    data class DecodeFailed(override val detailMessage: String) :
        AndroidTranscribeError(detailMessage)

    /**
     * `stopListening()`/`destroy()`呼び出しに伴うセッション終了
     * (design.md §4.3(wt73版)「キャンセル時はパイプclose →
     * stopListening() → destroy()」)。
     */
    data object Cancelled : AndroidTranscribeError(null)

    /** 上記のいずれにも分類できないSpeechRecognizer由来のエラー。 */
    data class PlatformError(override val detailMessage: String) :
        AndroidTranscribeError(detailMessage)
}

/** Pigeon生成の`TranscribeErrorCode`(design.md §2.3)への対応。 */
val AndroidTranscribeError.pigeonCode: TranscribeErrorCode
    get() = when (this) {
        is AndroidTranscribeError.DeviceUnsupported -> TranscribeErrorCode.DEVICE_UNSUPPORTED
        is AndroidTranscribeError.ModelUnavailable -> TranscribeErrorCode.MODEL_UNAVAILABLE
        is AndroidTranscribeError.LocaleUnsupported -> TranscribeErrorCode.LOCALE_UNSUPPORTED
        is AndroidTranscribeError.DecodeFailed -> TranscribeErrorCode.DECODE_FAILED
        AndroidTranscribeError.Cancelled -> TranscribeErrorCode.CANCELLED
        is AndroidTranscribeError.PlatformError -> TranscribeErrorCode.PLATFORM_ERROR
    }

/**
 * EventChannelの`PigeonEventSink.error(code:)`へ渡す文字列表現。
 *
 * この文字列はDart側(`lib/src/error_code_mapping.dart`)の
 * `TranscribeErrorCode.name`(enum名の文字列表現)と完全一致させることで、
 * Dart側が文字列比較のみで`TranscribeException`の具象型へ写像できるように
 * している。`lib/src/pigeon.g.dart`の`TranscribeErrorCode`定義とこの分岐の
 * 対応関係が崩れないよう、両方を変更する場合は必ず同時に更新すること
 * (offline_stt_darwinのDarwinTranscribeError.swift `wireCode`と同じ方針)。
 */
val TranscribeErrorCode.wireCode: String
    get() = when (this) {
        TranscribeErrorCode.MODEL_UNAVAILABLE -> "modelUnavailable"
        TranscribeErrorCode.LOCALE_UNSUPPORTED -> "localeUnsupported"
        TranscribeErrorCode.DECODE_FAILED -> "decodeFailed"
        TranscribeErrorCode.DEVICE_UNSUPPORTED -> "deviceUnsupported"
        TranscribeErrorCode.CANCELLED -> "cancelled"
        TranscribeErrorCode.PLATFORM_ERROR -> "platformError"
    }
