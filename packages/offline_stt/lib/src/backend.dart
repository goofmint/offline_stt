/// 実行環境に応じたバックエンド実装の選択点(design.md §1)。
///
/// 単一パッケージ構成では federated plugin の `default_package` による
/// 選択が使えないため、コンパイルターゲットごとの切り替えを条件付き
/// export で行う。`dart:js_interop` / `package:web` はWebコンパイル
/// ターゲットでのみ利用できるため、Web実装(`web/`)を非Webビルドへ
/// 混入させてはならない。iOS / macOS / Android の区別はこの時点では
/// 決まらないため、`backend_io.dart` 側が実行時に判定する。
library;

export 'backend_io.dart' if (dart.library.js_interop) 'backend_web.dart';
