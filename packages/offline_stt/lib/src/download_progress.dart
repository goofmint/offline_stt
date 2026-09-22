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
  /// `null` は不定進捗を表す。Webの `install()` は `Promise<boolean>` のみを
  /// 返し進捗イベントを提供しないため(design.md §4.1)、Webでは常に `null` を
  /// 返す想定である。Androidも再照会ポーリングのため `null` になり得る。
  final double? fraction;

  /// ダウンロードが完了したかどうか。
  final bool completed;

  /// 値等価。
  ///
  /// 進捗イベントはStreamで届くたびに新しく生成されるため、同一性比較では
  /// 一致しない。テストでの期待値比較を成立させるために値等価を定義する。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadProgress &&
        other.fraction == fraction &&
        other.completed == completed;
  }

  /// `==` を上書きしたため対で上書きする(Dartの等価契約)。
  @override
  int get hashCode => Object.hash(fraction, completed);

  @override
  String toString() =>
      'DownloadProgress(fraction: $fraction, completed: $completed)';
}
