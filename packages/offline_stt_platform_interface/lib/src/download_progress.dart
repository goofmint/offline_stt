import 'package:meta/meta.dart';

/// モデルダウンロードの進捗を表すデータ型(design.md §2.2)。
@immutable
class DownloadProgress {
  /// `fraction` は `null`(不定進捗)または 0.0〜1.0 でなければならない。
  ///
  /// `assert` はリリースビルドで無効化されるため、実行時に `ArgumentError` を
  /// 投げる。そのため `const` コンストラクタにはできない。
  factory DownloadProgress({
    required double? fraction,
    required bool completed,
  }) {
    if (fraction != null &&
        (fraction.isNaN || fraction < 0.0 || fraction > 1.0)) {
      throw ArgumentError.value(
        fraction,
        'fraction',
        'null(不定進捗)または 0.0〜1.0 でなければならない',
      );
    }
    return DownloadProgress._(fraction: fraction, completed: completed);
  }

  const DownloadProgress._({required this.fraction, required this.completed});

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
