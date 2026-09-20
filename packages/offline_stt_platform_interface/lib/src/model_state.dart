/// モデルの状態を表す4値。
///
/// requirements.md FR-1、design.md §2.2 で定義された値をそのまま実装した
/// ものである。各OSの状態モデルとの対応は requirements.md FR-1 を参照。
enum ModelState {
  /// モデルが取得済みで、即座に文字起こしに利用できる状態。
  available,

  /// モデルは未取得だが、ダウンロードで取得可能な状態。
  downloadable,

  /// モデルのダウンロードが進行中の状態。
  downloading,

  /// 端末・OS・ブラウザが対応しておらず、モデルを利用できない状態。
  unavailable,
}
