import 'package:meta/meta.dart';

/// モデルダウンロードの進捗を表すデータ型(design.md §2.2)。
@immutable
class DownloadProgress {
  const DownloadProgress({required this.fraction, required this.completed});

  /// 進捗率(0.0〜1.0)。
  ///
  /// `null` は不定進捗を表す。Windowsは進捗APIの粒度が粗いため、Webの
  /// `install()` は `Promise<boolean>` のみを返し進捗イベントを提供しない
  /// ため(design.md §4.1, §4.4)、いずれも常に `null` を返す想定である。
  final double? fraction;

  /// ダウンロードが完了したかどうか。
  final bool completed;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadProgress &&
        other.fraction == fraction &&
        other.completed == completed;
  }

  @override
  int get hashCode => Object.hash(fraction, completed);

  @override
  String toString() =>
      'DownloadProgress(fraction: $fraction, completed: $completed)';
}
