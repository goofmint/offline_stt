/// Web専用のObjectURL(Blob URL)生成ヘルパー(design.md §2.2)。
///
/// `dart:js_interop` / `package:web` はWebコンパイルターゲットでのみ
/// 利用できるため、非Webプラットフォーム(macOS / iOS 等)のビルドに
/// 混入させないよう条件付きexportで切り替える。呼び出し側
/// (`home_page.dart`)は `kIsWeb` で分岐したうえでのみこれらの関数を
/// 呼び出すこと(非Web版はUnsupportedErrorを送出する)。
library;

export 'object_url_stub.dart'
    if (dart.library.js_interop) 'object_url_web.dart';
