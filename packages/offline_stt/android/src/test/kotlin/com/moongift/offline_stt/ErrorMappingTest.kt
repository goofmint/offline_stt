// ErrorMappingTest.kt
// ErrorMapping.ktはSpeechRecognizer.ERROR_*定数(コンパイル時定数の
// public static final int)を分岐するだけの純粋な写像であり、実際のAndroid
// ランタイム呼び出しを伴わないため、JVMユニットテストで検証できる
// (design.md §7の切り分け方針、本ブランチの指示書「OS API依存部分は
// 書かなくてよい」との対比。ErrorMapping自体はOS APIを呼び出さないため
// テスト対象に含めた)。
package com.moongift.offline_stt

import android.speech.SpeechRecognizer
import kotlin.test.assertEquals
import kotlin.test.assertIs
import org.junit.Test

class ErrorMappingTest {
    @Test
    fun `ERROR_LANGUAGE_NOT_SUPPORTED は LocaleUnsupported へ写像する`() {
        val result = ErrorMapping.map(SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED)
        assertIs<AndroidTranscribeError.LocaleUnsupported>(result)
    }

    @Test
    fun `ERROR_LANGUAGE_UNAVAILABLE は ModelUnavailable へ写像する`() {
        val result = ErrorMapping.map(SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE)
        assertIs<AndroidTranscribeError.ModelUnavailable>(result)
    }

    @Test
    fun `ERROR_CANNOT_CHECK_SUPPORT は DeviceUnsupported へ写像する`() {
        val result = ErrorMapping.map(SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT)
        assertIs<AndroidTranscribeError.DeviceUnsupported>(result)
    }

    @Test
    fun `分類できないエラーは PlatformError へ写像し番号をメッセージに残す`() {
        val result = ErrorMapping.map(SpeechRecognizer.ERROR_NETWORK)
        assertIs<AndroidTranscribeError.PlatformError>(result)
        assertEquals(
            "ERROR_NETWORK(${SpeechRecognizer.ERROR_NETWORK})",
            (result as AndroidTranscribeError.PlatformError).detailMessage,
        )
    }

    @Test
    fun `未知のエラーコードも PlatformError へ写像しUNKNOWNとして番号を残す`() {
        val unknownCode = 9999
        val result = ErrorMapping.map(unknownCode)
        assertIs<AndroidTranscribeError.PlatformError>(result)
        assertEquals(
            "UNKNOWN($unknownCode)($unknownCode)",
            (result as AndroidTranscribeError.PlatformError).detailMessage,
        )
    }
}
