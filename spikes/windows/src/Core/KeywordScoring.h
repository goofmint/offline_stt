// KeywordScoring.h
//
// design.md §7「評価基準(キーワード包含率)」準拠のスコアリング。
// spikes/darwin/Sources/DarwinSTTSpikeCore/KeywordScoring.swift に対応する。
//
// 正規化手順(design.md §7 本文の順序どおり):
//   1. Unicode NFKC正規化
//   2. 小文字化(ja-JPに含まれるラテン文字にも適用)
//   3. 句読点・記号除去(Unicode一般カテゴリ P と S の全文字、および
//      、。「」・,.!?:;()[]{}"'-/ を含む)
//   4. 空白除去(半角/全角スペース、タブ、改行を含む全空白文字)
//   ja-JP固有: 上記に加えてひらがな→カタカナ畳み込み
//
// 採用したAPI(design.mdの指示「ICU または Windows の正規化API(NormalizeString等)
// を使うこと。使う API は調査して確定すること」への回答):
//
// - NFKC正規化: Win32 `NormalizeString(NormalizationKC, ...)` (winnls.h)。
//   https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-normalizestring
//   NORM_FORM列挙体の NormalizationKC (0x5) を使用することをドキュメントで確認済み。
//
// - Unicode一般カテゴリ P / S の判定: Windows 10 version 1903 (build 18362) 以降に
//   同梱される ICU (International Components for Unicode) の C API、
//   `u_charType()` (unicode/uchar.h、icu.lib/icu.dll) を使用する。
//   https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu-
//   「A new combined DLL, icu.dll ... A new import library was added to the
//   Windows 10 SDK: icu.lib」との記載をWebSearchで確認済み。
//   design.md §7 は「Unicode一般カテゴリ P(句読点)と S(記号)」を明示しており、
//   Win32ネイティブの `GetStringTypeW`(C1_PUNCT等)はUnicode一般カテゴリと
//   1対1に対応しないWindows独自分類のため採用しない。ICUの `u_charType()` が
//   返す `UCharCategory` の値のうち、
//     P: U_DASH_PUNCTUATION, U_START_PUNCTUATION, U_END_PUNCTUATION,
//        U_CONNECTOR_PUNCTUATION, U_OTHER_PUNCTUATION, U_INITIAL_PUNCTUATION,
//        U_FINAL_PUNCTUATION
//     S: U_MATH_SYMBOL, U_CURRENCY_SYMBOL, U_MODIFIER_SYMBOL, U_OTHER_SYMBOL
//   をPunctuation/Symbolとして除去する。
//
// - 小文字化: ICU `u_tolower()`(コードポイント単位、Unicodeデフォルトケースマッピング)。
//   design.mdはロケール依存の特殊マッピングを要求していないため、Win32の
//   `LCMapStringEx(LCMAP_LOWERCASE)` ではなくロケール非依存のu_tolower()を採用した
//   (要確認: トルコ語のようなロケール依存ケースマッピングが必要な言語は本スパイクの
//   対象外であり未検証)。
//
// - ひらがな→カタカナ畳み込み: Unicodeのひらがなブロック(U+3041-U+3096)と
//   カタカナブロック(U+30A1-U+30F6)がコードポイント値で概ね+0x60の固定オフセット
//   関係にあることを利用したコードポイント演算による畳み込みを実装した(ICUの
//   Transliterator C++ API を使う案もあったが、C++/WinRTプロジェクトからの
//   C++ ICU APIの利用可否がドキュメントで確認できなかったため、確実に動作すると
//   判断できるコードポイント演算を採用した)。U+3095/U+3096(小書きゐ/ゑ)は
//   対応するカタカナが同オフセットに存在するため通常畳み込みに含める。
//   長音記号 U+30FC(ー)はひらがな側に対応が無いためそのまま保持する。
//   本スパイクの基準音声(test-assets/baseline-audio)の期待テキスト・キーワードは
//   通常のひらがな/カタカナの範囲に収まるため、この単純な範囲演算で
//   design.md §7の要求を満たせると判断した。

#pragma once

#include <string>
#include <vector>

#include "Json.h"

namespace wsspike {

// design.md §7 のしきい値。1箇所にまとめ、design.md §7 由来であることを
// コメントで明記する(spikes/darwin の ScoringThresholds と同じ方針)。
//
// 備考: darwin RESULTS.md が指摘したとおり、design.md §7 表の「クリーン基準音声 /
// ja-JP / 90%以上」という記載と、直後の備考「90〜94%は条件付き合格」は
// 字面上やや不整合である。本スパイクは darwin スパイクと同じ解釈
// (95%以上=合格 / 90〜94%=条件付き合格 / 90%未満=不成立)を踏襲する。
struct ScoringThresholds {
    static constexpr double kJaJpPass = 0.95;
    static constexpr double kJaJpConditionalLowerBound = 0.90;
    static constexpr double kEnUsPass = 0.95;
};

enum class Verdict { Pass, Conditional, Fail };

std::wstring ToString(Verdict v);

struct KeywordScoringResult {
    int matchedCount = 0;
    int totalCount = 0;
    double ratio = 0.0;  // matchedCount / totalCount
    Verdict verdict = Verdict::Fail;
    std::vector<std::wstring> matchedKeywords;
    std::vector<std::wstring> unmatchedKeywords;
};

// design.md §7 の正規化手順を適用する。isJaJp が true の場合のみ
// ひらがな→カタカナ畳み込みを追加で行う。
std::wstring NormalizeForScoring(const std::wstring& text, bool isJaJp);

// expectedKeywords: 基準音声JSONの "keywords" 配列そのもの。各要素は通常は
// 文字列だが、design.md §7「数値・日付」節の「許容表記を列挙」という指示に
// 備え、要素が配列(表記ゆれの列挙)である場合も受理する
// (test-assets/baseline-audio/*.json の現行スキーマはフラットな文字列配列のみで
// あることを確認済みだが、将来のスキーマ拡張に備えて両対応にした)。
KeywordScoringResult ScoreKeywords(const json::Value& expectedKeywords, const std::wstring& recognizedText,
                                    bool isJaJp);

Verdict Judge(double ratio, bool isJaJp);

}  // namespace wsspike
