// KeywordScoring.swift
// design.md §7「評価基準(キーワード包含率)」に厳密に従ったスコアリング実装。
//
// 正規化(共通、この順で実施):
//   1. Unicode NFKC 正規化(String.precomposedStringWithCompatibilityMapping)
//   2. 小文字化
//   3. 句読点・記号除去(Unicode一般カテゴリ P と S。CharacterSet.punctuationCharacters / .symbols で判定)
//   4. 空白除去(CharacterSet.whitespacesAndNewlines)
// ja-JP 固有: 上記に加えてひらがな→カタカナ畳み込み(StringTransform.hiraganaToKatakana)
//
// 期待キーワードと認識結果テキストの両方に同一の正規化を適用する。
// keywords の要素が配列(許容表記の列挙)の場合はいずれか1つの一致でOKとする。

import Foundation

public enum KeywordNormalizer {
    private static let stripSet: CharacterSet = {
        CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
    }()

    public static func normalize(_ text: String, locale: String) -> String {
        // 1. NFKC
        let nfkc = text.precomposedStringWithCompatibilityMapping
        // 2. 小文字化
        let lowered = nfkc.lowercased()
        // 3. 句読点・記号除去 + 4. 空白除去(いずれもstripSetに含める)
        let scalars = lowered.unicodeScalars.filter { !stripSet.contains($0) }
        var result = String(String.UnicodeScalarView(scalars))
        // ja-JP 固有: ひらがな→カタカナ畳み込み
        if locale.lowercased().hasPrefix("ja") {
            if let transformed = result.applyingTransform(.hiraganaToKatakana, reverse: false) {
                result = transformed
            }
        }
        return result
    }
}

/// `{clip}.json` の `keywords` 配列の1要素。文字列単体、または許容表記を列挙した配列のいずれか。
public struct KeywordEntry: Decodable, Sendable {
    public let alternatives: [String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            alternatives = [single]
        } else {
            alternatives = try container.decode([String].self)
        }
    }

    public var displayName: String { alternatives.joined(separator: " / ") }
}

public struct BaselineClip: Decodable, Sendable {
    public let locale: String
    public let transcript: String
    public let keywords: [KeywordEntry]
}

/// design.md §7 のしきい値。ja-JP は 95%以上で合格、90〜94%で条件付き合格、90%未満で不成立。
/// en-US は 95%以上で合格(未満は不成立)。design.md本文の表は「ja-JP 90%以上」を合格しきい値の欄に
/// 記載しているが、直後の備考で「90〜94%は条件付き合格」としており、90%以上をそのまま単純合格とすると
/// 備考と矛盾する。本スパイクでは実施依頼で明示された「95%以上合格/90〜94%条件付き合格/90%未満不成立」の
/// 解釈を採用する(design.mdとの齟齬としてRESULTS.mdに記録する)。
public enum ScoringThresholds {
    public static let jaFullPass = 0.95
    public static let jaConditionalPass = 0.90
    public static let enPass = 0.95
}

public enum ScoreVerdict: String, Codable, Sendable {
    case pass = "合格"
    case conditionalPass = "条件付き合格"
    case fail = "不成立"
}

public struct KeywordScore: Codable, Sendable {
    public let totalKeywords: Int
    public let matchedKeywords: [String]
    public let unmatchedKeywords: [String]
    public let matchRate: Double
    public let verdict: String
}

public enum KeywordScoring {
    public static func score(recognizedText: String, clip: BaselineClip) -> KeywordScore {
        let normalizedRecognized = KeywordNormalizer.normalize(recognizedText, locale: clip.locale)

        var matched: [String] = []
        var unmatched: [String] = []
        for entry in clip.keywords {
            let isMatch = entry.alternatives.contains { alt in
                let normAlt = KeywordNormalizer.normalize(alt, locale: clip.locale)
                return !normAlt.isEmpty && normalizedRecognized.contains(normAlt)
            }
            if isMatch {
                matched.append(entry.displayName)
            } else {
                unmatched.append(entry.displayName)
            }
        }

        let rate = clip.keywords.isEmpty ? 0.0 : Double(matched.count) / Double(clip.keywords.count)
        let verdict = judge(rate: rate, locale: clip.locale)

        return KeywordScore(
            totalKeywords: clip.keywords.count,
            matchedKeywords: matched,
            unmatchedKeywords: unmatched,
            matchRate: rate,
            verdict: verdict.rawValue
        )
    }

    private static func judge(rate: Double, locale: String) -> ScoreVerdict {
        if locale.lowercased().hasPrefix("ja") {
            if rate >= ScoringThresholds.jaFullPass { return .pass }
            if rate >= ScoringThresholds.jaConditionalPass { return .conditionalPass }
            return .fail
        } else {
            return rate >= ScoringThresholds.enPass ? .pass : .fail
        }
    }
}
