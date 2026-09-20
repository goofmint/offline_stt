import 'package:meta/meta.dart';

/// 文字起こし結果の1セグメント(design.md §2.2)。
@immutable
class TranscriptSegment {
  /// ネイティブ側から届いた1件分の認識結果をそのまま写す。
  /// 実装パッケージ側は写像関数を挟まずこのコンストラクタを直接呼ぶ
  /// (分岐ロジックが無いため。各実装の `recognition_session.dart` 参照)。
  const TranscriptSegment({required this.text, required this.isFinal});

  /// 認識されたテキスト。
  final String text;

  /// 確定結果かどうか。
  ///
  /// `false` はpartial(暫定)結果を表す。Windowsのバッチ認識はfinalのみを
  /// 1回emitする(requirements.md FR-3、design.md §4.4)。
  final bool isFinal;

  /// 値等価。
  ///
  /// セグメントはStreamで届くたびに新しく生成されるため、同一性比較では
  /// 一致しない。テストでの期待値比較を成立させるために値等価を定義する。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranscriptSegment &&
        other.text == text &&
        other.isFinal == isFinal;
  }

  /// `==` を上書きしたため対で上書きする(Dartの等価契約)。
  @override
  int get hashCode => Object.hash(text, isFinal);

  @override
  String toString() => 'TranscriptSegment(text: $text, isFinal: $isFinal)';
}
