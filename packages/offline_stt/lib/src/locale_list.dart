import 'exceptions.dart';

/// `supportedLocales()` が返すロケール一覧を組み立てるための純粋ロジック
/// (requirements.md FR-5)。
///
/// ネイティブAPI・ブラウザAPIに一切依存しないため、`dart test`
/// (melos run test)で単体テストできる(`test/locale_list_test.dart`)。
/// 各プラットフォームの `model_management.dart` はブラウザ/Pigeonを直接
/// 叩く層であり単体テスト対象外という本パッケージの方針に従い、
/// 判断を伴う部分だけをここへ切り出している。

/// BCP-47タグの重複を除き、最初に現れた綴りを保って返す。
///
/// BCP-47のサブタグは大文字小文字を区別しない(RFC 5646 §2.1)。
/// `speechSynthesis.getVoices()` が返す `lang` には `en-US` と `en-us` の
/// ように綴りだけが違う重複が混ざり得るため、比較は小文字化して行い、
/// 返す値は最初に現れた綴りそのままにする(呼び出し側がブラウザへ渡す値を
/// こちらで勝手に書き換えないため)。
///
/// 空文字・空白のみのタグは候補になり得ないため取り除く。
List<String> dedupeLocaleTags(Iterable<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final tag in tags) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) continue;
    if (!seen.add(trimmed.toLowerCase())) continue;
    result.add(trimmed);
  }
  return result;
}

/// 一覧が空なら [DeviceUnsupportedException] を投げ、空でなければそのまま
/// 返す。
///
/// **`supportedLocales()` は空リストを返してはならない。** 「この端末は
/// 1つもロケールを扱えない」と「そもそも列挙できなかった」は意味が全く
/// 異なるのに、空リストは両者を区別できない。受け取った側は前者だと解釈し、
/// しかも原因がどこにも残らない。プロジェクト方針の「取得できない場合は
/// 明確にエラーを出す」に従い、ここで明示的な例外にする。
///
/// ネイティブ側(Kotlin `ModelAvailability.supportedLocales` /
/// Swift `ModelAvailability.supportedLocales()`)も同じ規則で自ら例外を
/// 投げるため、Android/Darwinで通常この関数が発火することはない。Dart側の
/// 最後の砦である。
///
/// 投げる型を [DeviceUnsupportedException] にしているのは、この状況が
/// 「端末・OS・ブラウザが機能自体に対応していない」という同例外の定義
/// (`exceptions.dart`)そのものだからである。ネイティブ側が投げた
/// `deviceUnsupported` が `error_code_mapping.dart` を経て届く場合と
/// 同じ型になり、呼び出し側は1つの `catch` で扱える。
List<String> requireNonEmptyLocales(List<String> locales) {
  if (locales.isEmpty) {
    throw const DeviceUnsupportedException();
  }
  return locales;
}
