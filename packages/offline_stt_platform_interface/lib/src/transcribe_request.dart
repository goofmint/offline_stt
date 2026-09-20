import 'package:meta/meta.dart';

/// `transcribeFile()` へ渡すリクエスト(design.md §2.2)。
@immutable
class TranscribeRequest {
  /// `playbackRate` は 0 より大きい有限値でなければならない。
  ///
  /// `assert` はリリースビルドで無効化されるため、`DownloadProgress` の
  /// `fraction` 検証と同様に実行時に `ArgumentError` を投げる。そのため
  /// `const` コンストラクタにはできない。
  factory TranscribeRequest({
    required String path,
    required String locale,
    double playbackRate = 1.0,
  }) {
    if (!playbackRate.isFinite || playbackRate <= 0.0) {
      throw ArgumentError.value(
        playbackRate,
        'playbackRate',
        '0より大きい有限値でなければならない',
      );
    }
    return TranscribeRequest._(
      path: path,
      locale: locale,
      playbackRate: playbackRate,
    );
  }

  const TranscribeRequest._({
    required this.path,
    required this.locale,
    required this.playbackRate,
  });

  /// 文字起こし対象の音声ファイルパス。
  ///
  /// Webでは Blob URL / ObjectURL を指定する(design.md §4.1)。
  final String path;

  /// BCP-47形式のロケール(例: `ja-JP`)。
  final String locale;

  /// 再生速度(既定 1.0、design.md §2.2 / §7)。
  ///
  /// 意味を持つのはWebのみで、`AudioBufferSourceNode.playbackRate` に
  /// 直結する。1.0より大きい値を指定すると所要時間を短縮できるが、
  /// Web Audio にピッチ保持のタイムストレッチは無いためピッチも同倍率で
  /// 変化し、認識精度が低下しうる(design.md §4.1・§7の実測を参照)。
  /// Darwin(SpeechAnalyzer)・Windows(BatchRecognition)はバッチ処理で
  /// あり速度という概念自体が存在しないため、値は受理するが動作には
  /// 影響しない。Androidは理論上適用余地があるがM0時点では未検証であり、
  /// 現状は無視される(design.md §7)。
  final double playbackRate;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranscribeRequest &&
        other.path == path &&
        other.locale == locale &&
        other.playbackRate == playbackRate;
  }

  @override
  int get hashCode => Object.hash(path, locale, playbackRate);

  @override
  String toString() =>
      'TranscribeRequest(path: $path, locale: $locale, '
      'playbackRate: $playbackRate)';
}
