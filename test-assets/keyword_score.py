#!/usr/bin/env python3
"""design.md §7「評価基準(キーワード包含率)」の正規化・判定をそのまま実装する。

`spikes/android/.../KeywordScoring.kt` / `spikes/darwin/.../KeywordScoring.swift`
/ `spikes/web/spike.js` と同一の手順である。本スクリプトは本番実装の実機E2E
(Issue #50)で、端末から取り出した確定テキストをホスト側で採点するために
置いている(Dart には Unicode 正規化 (NFKC) が標準で無いため、端末側の
integration_test では採点まで行わない)。

使い方:
    test-assets/keyword_score.py <クリップ名> <確定テキスト>
例:
    test-assets/keyword_score.py jaJP_10s "東京都渋谷区で ..."

`<クリップ名>` は test-assets/baseline-audio/<クリップ名>.json を指す。

`{クリップ名}.json` の `keywords` はキーワードグループの配列であり、
1要素は次のいずれかを取る(design.md §7「許容表記の表現形式」)。

- 文字列: 表記が1つだけのキーワード(例: "東京都渋谷区")
- 文字列の配列: 許容表記の列挙(例: ["2024年11月3日", "2024/11/3"])

グループ内のいずれか1表記が一致すれば、そのグループを一致とみなす。
**包含率の分母はグループ数であり、表記数ではない。**

自己検査:
    test-assets/keyword_score.py --selfcheck
M0 実測テキストで jaJP_10s が 66.7%(4/6)になることを確認する。
"""

import json
import pathlib
import sys
import unicodedata

BASE = pathlib.Path(__file__).resolve().parent / "baseline-audio"

EXPLICIT_SYMBOLS = set("、。「」・,.!?:;()[]{}\"'-/")

HIRAGANA_START = 0x3041
HIRAGANA_END = 0x3096
HIRAGANA_TO_KATAKANA_OFFSET = 0x60

THRESHOLDS = {
    # (合格しきい値, 条件付き合格の下限。None は中間区分なし)
    "ja-JP": (95.0, 90.0),
    "en-US": (95.0, None),
}


def normalize(text: str, locale: str) -> str:
    # 1. Unicode NFKC 正規化
    s = unicodedata.normalize("NFKC", text)
    # 2. 小文字化
    s = s.lower()
    # 3. 句読点・記号の除去(Unicode 一般カテゴリ P と S、および明示列挙)
    s = "".join(
        ch
        for ch in s
        if not unicodedata.category(ch).startswith(("P", "S"))
        and ch not in EXPLICIT_SYMBOLS
    )
    # 4. 空白の除去
    s = "".join(ch for ch in s if not ch.isspace())
    # ja-JP 固有: ひらがな → カタカナ
    if locale == "ja-JP":
        s = "".join(
            chr(ord(ch) + HIRAGANA_TO_KATAKANA_OFFSET)
            if HIRAGANA_START <= ord(ch) <= HIRAGANA_END
            else ch
            for ch in s
        )
    return s


def judge(locale: str, rate: float) -> str:
    threshold = THRESHOLDS.get(locale)
    if threshold is None:
        return "判定基準未定義"
    pass_min, conditional_min = threshold
    if rate >= pass_min:
        return "合格"
    if conditional_min is not None and rate >= conditional_min:
        return "条件付き合格 / 要確認"
    return "不成立"


# 自己検査用の既知の入力と期待値。
# spikes/android/RESULTS.md / spikes/darwin/RESULTS.md / spikes/web/RESULTS.md が
# いずれも記録している M0 の jaJP_10s 実測テキストを入力すると 4/6 = 66.7% になる。
# 不一致の2件(東京都渋谷区・株式会社モーンギフト)は表記差ではなく誤認識であり、
# 許容表記の列挙によって一致に変わってはならない。
SELFCHECK = (
    "jaJP_10s",
    "東京都渋谷で2024年11月3日午後3時株式会社モンギフトが新製品を発表しました"
    "来場者は128名でした",
    4,
    6,
)


def score(clip: str, result_text: str):
    """(ロケール, [(キーワードグループ, 一致した表記 or None), ...]) を返す。"""
    meta = json.loads((BASE / f"{clip}.json").read_text(encoding="utf-8"))
    locale = meta["locale"]
    keywords = meta["keywords"]
    normalized_result = normalize(result_text, locale)
    results = []
    for keyword in keywords:
        # 文字列単体は「要素数1の許容表記リスト」として扱う
        variants = keyword if isinstance(keyword, list) else [keyword]
        hit = None
        for variant in variants:
            normalized_variant = normalize(variant, locale)
            if normalized_variant and normalized_variant in normalized_result:
                hit = variant
                break
        results.append((keyword, hit))
    return locale, results


def selfcheck() -> int:
    clip, text, want_matched, want_total = SELFCHECK
    _, results = score(clip, text)
    total = len(results)
    matched = [k for k, hit in results if hit]
    unmatched = [k for k, hit in results if not hit]
    rate = (len(matched) / total * 100.0) if total else 0.0
    print(f"selfcheck: {clip} → {len(matched)}/{total} = {rate:.1f}%")
    print(f"  不一致: {unmatched}")
    if (len(matched), total) != (want_matched, want_total):
        print(
            f"NG: 期待は {want_matched}/{want_total} "
            f"(= {want_matched / want_total * 100.0:.1f}%)"
        )
        return 1
    print("OK: M0 の実測値 66.7%(4/6)を再現した")
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--selfcheck":
        return selfcheck()
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        return 2
    clip, result_text = sys.argv[1], sys.argv[2]
    locale, results = score(clip, result_text)
    matched = [k for k, hit in results if hit]
    unmatched = [k for k, hit in results if not hit]
    for keyword, hit in results:
        # 許容表記が複数あるグループは、どの表記で一致したかも出す
        suffix = f" (一致表記: {hit})" if hit and isinstance(keyword, list) else ""
        print(f"{'HIT ' if hit else 'MISS'}\t{keyword}{suffix}")

    total = len(results)
    rate = (len(matched) / total * 100.0) if total else 0.0
    print(f"clip={clip} locale={locale}")
    print(f"包含率: {len(matched)}/{total} = {rate:.1f}% → {judge(locale, rate)}")
    print(f"不一致: {unmatched if unmatched else '(なし)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
