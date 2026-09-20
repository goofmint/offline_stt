/// Web版の確定(final)結果テキストの整形(design.md §4.1、Issue #28)。
///
/// ブラウザAPIに依存しない純粋な文字列処理のみであるため単体テストが書ける
/// (`test/final_text_formatting_test.dart` 参照)。
///
/// ## 空白除去の判断とその理由
/// Chromeのオンデバイス認識は確定(final)結果を形態素単位で空白区切りして
/// 返すことをChrome 153実機で確認済みである(例:
/// `東京 都 渋谷 で 2024 年 ...`。spikes/web/RESULTS.md参照)。一方でpartial
/// (interim)結果にはこの区切りが入らない。design.md §4.1は「アプリへ返す前に
/// この空白を除去するかどうか、実装時にテキスト整形の方針を決める必要が
/// ある」として実装側の判断に委ねている。
///
/// 本実装は**除去する**方針を採る。理由は次の2点である。
/// 1. これはChromeのオンデバイス認識エンジン固有の実装詳細であり、
///    `TranscriptSegment.text`(design.md §2.2)はプラットフォーム共通の
///    公開APIである。Android/Darwin/Windowsの認識結果がこのような形態素
///    区切りの空白を持つ想定は無く、Web版だけ空白入りのテキストを返すと
///    プラットフォーム間でAPIの見た目が一貫しなくなる。
/// 2. 空白除去は不可逆ではあるが、design.md §7の評価基準(キーワード包含率)
///    の正規化ルールも同様に空白を除去してから比較しており、空白の有無が
///    利用者にとって意味を持つ情報とはみなされていない。
///
/// 対象は半角/全角スペース・タブ・改行を含む全空白文字(design.md §7の
/// 正規化ルールにある空白除去と同じ対象範囲)。partial結果には元々空白が
/// 入らないため、この関数はfinal結果(通常のisFinal=true結果、および
/// isFinalが一度も発火しなかった場合に採用する末尾interim結果の両方)に
/// のみ適用する(recognition_session.dart参照)。
String stripChromeSegmentationWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s'), '');
