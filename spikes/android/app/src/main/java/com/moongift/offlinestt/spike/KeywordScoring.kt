package com.moongift.offlinestt.spike

import java.text.Normalizer

/**
 * design.md §7「評価基準(キーワード包含率)」に厳密に従うスコアリング実装。
 *
 * 正規化ルール(この順で適用し、期待キーワードと認識結果テキストの両方へ同一に適用する):
 *   1. Unicode NFKC 正規化
 *   2. 小文字化 (ja-JP に含まれるラテン文字にも適用)
 *   3. 句読点・記号除去 (Unicode 一般カテゴリ P と S の全文字、および明示列挙記号)
 *   4. 空白除去 (半角/全角スペース、タブ、改行を含む全空白文字)
 *   ja-JP 固有: 上記に加えてひらがな→カタカナ畳み込み
 *
 * 参照実装: spikes/web/spike.js の (C) ブロック (`normalize` / `keywordMatches` / `scoreResult`)。
 * Darwin 版: spikes/darwin/Sources/DarwinSTTSpikeCore/KeywordScoring.swift。
 * 本ファイルはこれら2つと同一の判定ロジックになるようにしている。
 */
object KeywordScoring {

    /** design.md §7 由来のしきい値。クリーン基準音声に対する判定区分。 */
    data class Thresholds(val passMin: Double, val conditionalMin: Double?)

    // design.md §7:
    // - ja-JP: 95%以上で合格、90〜94%は「条件付き合格 / 要確認」の中間区分、90%未満は不成立
    // - en-US: 95%以上で合格、95%未満は不成立 (中間区分の記載なし)
    val THRESHOLDS: Map<String, Thresholds> = mapOf(
        "ja-JP" to Thresholds(passMin = 95.0, conditionalMin = 90.0),
        "en-US" to Thresholds(passMin = 95.0, conditionalMin = null),
    )

    enum class Verdict(val label: String) {
        PASS("合格"),
        CONDITIONAL("条件付き合格 / 要確認"),
        FAIL("不成立"),
        UNDEFINED("判定基準未定義"),
    }

    // Java の \p{Punct} は ASCII のみを指すため使わない。design.md §7 が指す Unicode 一般カテゴリ
    // P (句読点) と S (記号) は、Java 正規表現では単一文字の一般カテゴリグループ \p{P} / \p{S}
    // (「Is」なしの2文字表記) で確実に動作する。なお \p{IsPunctuation} は Unicode の binary
    // property "Punctuation" として Java でも有効だが、\p{IsSymbol} という binary property は
    // Java では未定義でありコンパイル時に PatternSyntaxException になるため使わない。
    private val PUNCTUATION_OR_SYMBOL_REGEX = Regex("[\\p{P}\\p{S}]")

    // NFKC/カテゴリ判定の抜け漏れに備えた明示列挙 (spike.js と同一の集合)。
    private val EXPLICIT_SYMBOLS_REGEX = Regex("[、。「」・,.!?:;()\\[\\]{}\"'\\-/]")

    private val WHITESPACE_REGEX = Regex("\\s")

    // ひらがな U+3041-U+3096 → カタカナは +0x60 (spike.js/KeywordScoring.swift と同一範囲)。
    private const val HIRAGANA_START = 0x3041
    private const val HIRAGANA_END = 0x3096
    private const val HIRAGANA_TO_KATAKANA_OFFSET = 0x60

    fun normalize(text: String, locale: String): String {
        // 1. Unicode NFKC 正規化
        var s = Normalizer.normalize(text, Normalizer.Form.NFKC)

        // 2. 小文字化
        s = s.lowercase()

        // 3. 句読点・記号除去
        s = PUNCTUATION_OR_SYMBOL_REGEX.replace(s, "")
        s = EXPLICIT_SYMBOLS_REGEX.replace(s, "")

        // 4. 空白除去
        s = WHITESPACE_REGEX.replace(s, "")

        // ja-JP固有: ひらがな→カタカナ畳み込み
        if (locale == "ja-JP") {
            val sb = StringBuilder(s.length)
            for (ch in s) {
                val code = ch.code
                if (code in HIRAGANA_START..HIRAGANA_END) {
                    sb.append((code + HIRAGANA_TO_KATAKANA_OFFSET).toChar())
                } else {
                    sb.append(ch)
                }
            }
            s = sb.toString()
        }

        return s
    }

    data class KeywordMatch(val matched: Boolean, val matchedVariant: String?)

    /**
     * keywordItem は 1個のキーワード(単一表記)または、許容表記を列挙した List<String> のいずれか。
     * いずれか1つの表記が一致すれば matched=true とする。
     */
    fun keywordMatches(keywordItem: Any, normalizedResult: String, locale: String): KeywordMatch {
        val variants: List<String> = when (keywordItem) {
            is List<*> -> keywordItem.map { it.toString() }
            else -> listOf(keywordItem.toString())
        }
        for (variant in variants) {
            val normalizedVariant = normalize(variant, locale)
            if (normalizedVariant.isEmpty()) continue
            if (normalizedResult.contains(normalizedVariant)) {
                return KeywordMatch(matched = true, matchedVariant = variant)
            }
        }
        return KeywordMatch(matched = false, matchedVariant = null)
    }

    fun judge(locale: String, ratePercent: Double): Verdict {
        val th = THRESHOLDS[locale] ?: return Verdict.UNDEFINED
        if (ratePercent >= th.passMin) return Verdict.PASS
        if (th.conditionalMin != null && ratePercent >= th.conditionalMin) return Verdict.CONDITIONAL
        return Verdict.FAIL
    }

    data class ScoreResult(
        val matched: List<Pair<Any, String?>>,
        val unmatched: List<Any>,
        val ratePercent: Double,
        val verdict: Verdict,
    )

    fun score(locale: String, keywords: List<Any>, resultText: String): ScoreResult {
        val normalizedResult = normalize(resultText, locale)

        val matched = mutableListOf<Pair<Any, String?>>()
        val unmatched = mutableListOf<Any>()
        for (kw in keywords) {
            val m = keywordMatches(kw, normalizedResult, locale)
            if (m.matched) {
                matched.add(kw to m.matchedVariant)
            } else {
                unmatched.add(kw)
            }
        }

        val total = keywords.size
        val rate = if (total == 0) 0.0 else (matched.size.toDouble() / total) * 100.0
        val verdict = judge(locale, rate)

        SpikeLog.let { log ->
            val fn = if (verdict == Verdict.FAIL) log::ng else log::ok
            fn("キーワード包含率: ${matched.size}/$total = ${"%.1f".format(rate)}% (locale=$locale) → 判定: ${verdict.label}")
            log.info("一致キーワード: ${matched.joinToString(", ") { it.first.toString() }.ifEmpty { "(なし)" }}")
            log.info("不一致キーワード: ${unmatched.joinToString(", ") { it.toString() }.ifEmpty { "(なし)" }}")
        }

        return ScoreResult(matched, unmatched, rate, verdict)
    }
}
