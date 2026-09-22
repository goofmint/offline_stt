// RecognitionSession.isHypothesisReset の単体テスト。
// 実機(Pixel 6)で観測した「オンデバイス認識エンジンが長尺入力で仮説を
// リセットし、onPartialResults() が最初からやり直しになる」挙動
// (docs/e2e/E2E_RESULTS_ANDROID.md の B-3)への対処が、
// 通常の更新を誤ってリセット扱いしないことを確認する。
//
// **閾値そのものの妥当性は本テストでは担保できない。** ここで確認するのは
// 判定規則が意図どおりに書けていることだけであり、実際のエンジンが
// どのような縮み方をするかは実機E2E(Issue #50)でしか確かめられない。
package com.moongift.offline_stt

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test

class RecognitionSessionResetTest {
    @Test
    fun `伸びていく通常の更新はリセットではない`() {
        assertFalse(RecognitionSession.isHypothesisReset("東京都", "東京都渋谷区で"))
    }

    @Test
    fun `末尾が書き換わるだけの更新はリセットではない`() {
        assertFalse(
            RecognitionSession.isHypothesisReset("東京都渋谷で2024年", "東京都渋谷区で2024年"),
        )
    }

    @Test
    fun `接頭辞への取り消しはリセットではない`() {
        // 同じ仮説に対する retraction。半分未満に縮んでいても、直前の
        // 接頭辞であればリセットとは見なさない。
        assertFalse(RecognitionSession.isHypothesisReset("東京都渋谷区で2024年11月", "東京都"))
    }

    @Test
    fun `半分未満へ縮み接頭辞でもなければリセットとみなす`() {
        // 実機で観測した形: 341文字の仮説が数文字の新しい仮説に置き換わる。
        val previous = "あ".repeat(341)
        assertTrue(RecognitionSession.isHypothesisReset(previous, "来場者は"))
    }

    @Test
    fun `半分以上の長さが残っていればリセットとみなさない`() {
        val previous = "あ".repeat(100)
        assertFalse(RecognitionSession.isHypothesisReset(previous, "い".repeat(60)))
    }

    @Test
    fun `直前が空ならリセットではない`() {
        assertFalse(RecognitionSession.isHypothesisReset("", "東京都"))
    }
}

class RecognitionSessionJoinTest {
    @Test
    fun `重なりが無ければそのまま連結する`() {
        assertEquals("ABC", RecognitionSession.joinWithOverlap("ABC", ""))
        assertEquals("DEF", RecognitionSession.joinWithOverlap("", "DEF"))
    }

    @Test
    fun `末尾と先頭が一致する最長区間を取り除く`() {
        val shared = "これは十分に長い共通区間であり偶然ではない"
        val accumulated = "前半の内容$shared"
        val next = "$shared 後半の内容"
        assertEquals("前半の内容$shared 後半の内容", RecognitionSession.joinWithOverlap(accumulated, next))
    }

    @Test
    fun `minOverlap 未満の短い一致は重複とみなさない`() {
        // 「の」1文字のような偶然の一致で切り詰めると、本来必要な文字が消える。
        assertEquals("私の君の", RecognitionSession.joinWithOverlap("私の", "君の"))
    }

    @Test
    fun `完全に同一なら1つ分になる`() {
        val text = "まったく同じ内容がもう一度認識された場合の確認である"
        assertEquals(text, RecognitionSession.joinWithOverlap(text, text))
    }

    @Test
    fun `細部が揺れて一致しない場合は重複が残る`() {
        // 実測で `Moji tall core` / `Mojit tall core` のような揺れがある。
        // 取り除きすぎるより残すほうが実害が小さいという判断の明文化。
        val a = "abcdefghijklmnopqrstuvwxyz0123456789"
        val b = "Xbcdefghijklmnopqrstuvwxyz0123456789 tail"
        assertEquals(a + b, RecognitionSession.joinWithOverlap(a, b))
    }
}
