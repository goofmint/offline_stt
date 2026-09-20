import 'package:meta/meta.dart';

/// `transcribeFile()` へ渡すリクエスト(design.md §2.2)。
///
/// 注記: design.md §2.2 の現行定義は `path` / `locale` の2フィールドのみ
/// である。`playbackRate` は design.md には存在しないため、本パッケージでは
/// 実装していない(詳細は本Issueの報告を参照)。
@immutable
class TranscribeRequest {
  const TranscribeRequest({required this.path, required this.locale});

  /// 文字起こし対象の音声ファイルパス。
  ///
  /// Webでは Blob URL / ObjectURL を指定する(design.md §4.1)。
  final String path;

  /// BCP-47形式のロケール(例: `ja-JP`)。
  final String locale;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranscribeRequest &&
        other.path == path &&
        other.locale == locale;
  }

  @override
  int get hashCode => Object.hash(path, locale);

  @override
  String toString() => 'TranscribeRequest(path: $path, locale: $locale)';
}
