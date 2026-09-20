import 'package:meta/meta.dart';

/// 文字起こし結果の1セグメント(design.md §2.2)。
@immutable
class TranscriptSegment {
  const TranscriptSegment({required this.text, required this.isFinal});

  /// 認識されたテキスト。
  final String text;

  /// 確定結果かどうか。
  ///
  /// `false` はpartial(暫定)結果を表す。Windowsのバッチ認識はfinalのみを
  /// 1回emitする(requirements.md FR-3、design.md §4.4)。
  final bool isFinal;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranscriptSegment &&
        other.text == text &&
        other.isFinal == isFinal;
  }

  @override
  int get hashCode => Object.hash(text, isFinal);

  @override
  String toString() => 'TranscriptSegment(text: $text, isFinal: $isFinal)';
}
