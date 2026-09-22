import 'common.dart';
import 'web/offline_stt_web.dart';

/// Webコンパイルターゲット向けのバックエンド生成(design.md §4.1)。
///
/// `dart.library.js_interop` が使える場合のみ `backend.dart` の条件付き
/// export からこのライブラリが選ばれる。Webの実装は1つだけであるため
/// 実行時の分岐は無い。ブラウザ側の前提(Chrome 142以上のデスクトップ版、
/// localhost または https 配信)を満たさない場合は、`checkModel()` が
/// `ModelState.unavailable` を返すか、セッション開始時にエラーとなる
/// (requirements.md NFR-4)。
OfflineTranscriberPlatform createBackend() => OfflineSttWeb();
