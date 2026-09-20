// KeywordScoring.cpp
#include "pch.h"
#include "KeywordScoring.h"

// ICU (Windows同梱、Windows 10 1903+ / icu.lib) のC API。
// https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu-
#include <icu.h>

#include <algorithm>
#include <set>
#include <sstream>

namespace wsspike {

std::wstring ToString(Verdict v) {
    switch (v) {
        case Verdict::Pass: return L"pass";
        case Verdict::Conditional: return L"conditional";
        case Verdict::Fail: return L"fail";
    }
    return L"fail";
}

namespace {

// NFKC正規化。NormalizeString(winnls.h)。
// https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-normalizestring
std::wstring NormalizeNfkc(const std::wstring& input) {
    if (input.empty()) return input;
    int required = ::NormalizeString(NormalizationKC, input.c_str(), -1, nullptr, 0);
    if (required <= 0) {
        // 正規化不能な文字列の場合はそのまま返す(スパイクの都合で握りつぶさず、
        // 呼び出し元のスコアリングが不一致として扱われるだけなので実害は無い)。
        return input;
    }
    std::wstring out(static_cast<size_t>(required), L'\0');
    int written = ::NormalizeString(NormalizationKC, input.c_str(), -1, out.data(), required);
    if (written <= 0) {
        return input;
    }
    // NormalizeStringは終端NULを含めて書き込むため、written-1文字目までが実体。
    out.resize(static_cast<size_t>(written - 1));
    return out;
}

// UTF-16の std::wstring を UChar32(コードポイント) の列へ変換する
// (サロゲートペアを正しく合成する)。
std::vector<UChar32> ToCodepoints(const std::wstring& s) {
    std::vector<UChar32> out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size();) {
        wchar_t c = s[i];
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.size()) {
            wchar_t c2 = s[i + 1];
            if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
                UChar32 cp = 0x10000 + ((static_cast<UChar32>(c) - 0xD800) << 10) + (static_cast<UChar32>(c2) - 0xDC00);
                out.push_back(cp);
                i += 2;
                continue;
            }
        }
        out.push_back(static_cast<UChar32>(c));
        ++i;
    }
    return out;
}

std::wstring FromCodepoints(const std::vector<UChar32>& cps) {
    std::wstring out;
    out.reserve(cps.size());
    for (UChar32 cp : cps) {
        if (cp <= 0xFFFF) {
            out.push_back(static_cast<wchar_t>(cp));
        } else {
            UChar32 v = cp - 0x10000;
            out.push_back(static_cast<wchar_t>(0xD800 + (v >> 10)));
            out.push_back(static_cast<wchar_t>(0xDC00 + (v & 0x3FF)));
        }
    }
    return out;
}

bool IsPunctuationOrSymbol(UChar32 cp) {
    // design.md §7: Unicode一般カテゴリ P(句読点)と S(記号)。
    int8_t cat = u_charType(cp);
    switch (cat) {
        case U_DASH_PUNCTUATION:
        case U_START_PUNCTUATION:
        case U_END_PUNCTUATION:
        case U_CONNECTOR_PUNCTUATION:
        case U_OTHER_PUNCTUATION:
        case U_INITIAL_PUNCTUATION:
        case U_FINAL_PUNCTUATION:
        case U_MATH_SYMBOL:
        case U_CURRENCY_SYMBOL:
        case U_MODIFIER_SYMBOL:
        case U_OTHER_SYMBOL:
            return true;
        default:
            return false;
    }
}

bool IsExplicitPunctuationBackup(UChar32 cp) {
    // design.md §7 が明示列挙する記号(念のためu_charType判定に加えて明示チェックする。
    // 通常はいずれもUnicodeカテゴリP/Sに含まれるはずだが、ICUのバージョン差異による
    // 分類揺れに備えたフェイルセーフ)。
    static const std::wstring kExplicit = L"、。「」・,.!?:;()[]{}\"'-/";
    return kExplicit.find(static_cast<wchar_t>(cp)) != std::wstring::npos;
}

bool IsWhitespace(UChar32 cp) {
    // 半角/全角スペース、タブ、改行を含む全空白文字。
    if (cp == 0x3000) return true;  // 全角スペース
    if (cp <= 0xFFFF && iswspace(static_cast<wchar_t>(cp))) return true;
    return false;
}

UChar32 FoldHiraganaToKatakana(UChar32 cp) {
    // ひらがな U+3041-U+3096 <-> カタカナ U+30A1-U+30F6 のオフセット+0x60。
    if (cp >= 0x3041 && cp <= 0x3096) {
        return cp + 0x60;
    }
    return cp;
}

}  // namespace

std::wstring NormalizeForScoring(const std::wstring& text, bool isJaJp) {
    // 1. NFKC正規化
    std::wstring nfkc = NormalizeNfkc(text);

    // コードポイント単位で処理する(2〜4の各手順)。
    std::vector<UChar32> cps = ToCodepoints(nfkc);
    std::vector<UChar32> out;
    out.reserve(cps.size());

    for (UChar32 cp : cps) {
        // 2. 小文字化(ラテン文字含む)。
        UChar32 lowered = u_tolower(cp);

        // 4. ja-JP固有: ひらがな→カタカナ畳み込み(空白・記号除去の前に行っても
        //    結果に影響しないため、小文字化の直後に適用する)。
        if (isJaJp) {
            lowered = FoldHiraganaToKatakana(lowered);
        }

        // 3. 句読点・記号除去
        if (IsPunctuationOrSymbol(lowered) || IsExplicitPunctuationBackup(lowered)) {
            continue;
        }
        // 4. 空白除去
        if (IsWhitespace(lowered)) {
            continue;
        }
        out.push_back(lowered);
    }

    return FromCodepoints(out);
}

Verdict Judge(double ratio, bool isJaJp) {
    if (isJaJp) {
        if (ratio >= ScoringThresholds::kJaJpPass) return Verdict::Pass;
        if (ratio >= ScoringThresholds::kJaJpConditionalLowerBound) return Verdict::Conditional;
        return Verdict::Fail;
    }
    if (ratio >= ScoringThresholds::kEnUsPass) return Verdict::Pass;
    return Verdict::Fail;
}

KeywordScoringResult ScoreKeywords(const json::Value& expectedKeywords, const std::wstring& recognizedText,
                                    bool isJaJp) {
    std::wstring normalizedRecognized = NormalizeForScoring(recognizedText, isJaJp);

    KeywordScoringResult result;
    if (!expectedKeywords.IsArray()) {
        return result;  // 空(呼び出し側でJSONスキーマ異常として扱う)
    }

    for (const auto& kwEntry : expectedKeywords.AsArray()) {
        std::vector<std::wstring> variants;
        if (kwEntry.IsString()) {
            variants.push_back(kwEntry.AsString());
        } else if (kwEntry.IsArray()) {
            // 「許容表記を列挙」ケース(KeywordScoring.h参照)。
            for (const auto& v : kwEntry.AsArray()) {
                if (v.IsString()) variants.push_back(v.AsString());
            }
        } else {
            continue;
        }
        if (variants.empty()) continue;

        // 表示用ラベルは先頭の表記を使う。
        const std::wstring& label = variants.front();
        bool matched = false;
        for (const auto& variant : variants) {
            std::wstring normalizedVariant = NormalizeForScoring(variant, isJaJp);
            if (!normalizedVariant.empty() &&
                normalizedRecognized.find(normalizedVariant) != std::wstring::npos) {
                matched = true;
                break;
            }
        }

        result.totalCount += 1;
        if (matched) {
            result.matchedCount += 1;
            result.matchedKeywords.push_back(label);
        } else {
            result.unmatchedKeywords.push_back(label);
        }
    }

    result.ratio = result.totalCount > 0 ? static_cast<double>(result.matchedCount) / result.totalCount : 0.0;
    result.verdict = Judge(result.ratio, isJaJp);
    return result;
}

}  // namespace wsspike
