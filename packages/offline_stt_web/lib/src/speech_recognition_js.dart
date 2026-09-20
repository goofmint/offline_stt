import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Chrome専用の実験的 Web Speech API 拡張への `dart:js_interop` バインディング
/// (design.md §4.1、§8未決事項4、spikes/web/spike.js が実機で検証済みの
/// API形状をそのまま移植する)。
///
/// `package:web` の標準 `SpeechRecognition` 型(`package:web`
/// `speech_api.dart`)は標準Web IDLに存在するメンバーのみを持つ。
/// `available()` / `install()`(コンストラクタの静的メソッド)、
/// `processLocally` プロパティ、`start(audioTrack)` の1引数オーバーロードは
/// いずれもChromeの実験的拡張であり標準Web IDLに存在しないため
/// `package:web` には型が無い。そのためここでは `dart:js_interop_unsafe`
/// (動的プロパティ・メソッドアクセス)を使って直接呼び出す。
///
/// ## テスト方針
/// このファイルはブラウザAPIを直接叩く層であるため単体テストを書かない。
/// 本パッケージでは「ブラウザAPIに依存しない純粋ロジック」
/// (`model_state_mapping.dart` / `speech_error_mapping.dart` /
/// `final_text_formatting.dart`)だけを切り出して単体テストし、この層は
/// Issue #31 の手動E2Eチェックリストでカバーする方針を採る。

/// `SpeechRecognition.available()` / `install()` に渡すオプション
/// (`{langs: [locale], processLocally: true}`)。
extension type _AvailabilityOptions._(JSObject _) implements JSObject {
  external factory _AvailabilityOptions({
    required JSArray<JSString> langs,
    required bool processLocally,
  });
}

/// `window.SpeechRecognition` または `window.webkitSpeechRecognition` の
/// コンストラクタを返す。いずれも存在しなければ `null`
/// (design.md §4.1「機能検出」、Issue #30)。
JSFunction? findSpeechRecognitionConstructor() {
  final global = globalContext;
  for (final name in const ['SpeechRecognition', 'webkitSpeechRecognition']) {
    if (!global.has(name)) continue;
    final ctor = global[name] as JSFunction;
    // Safari 等の非Chrome系ブラウザは webkitSpeechRecognition を提供するが、
    // Chrome固有のオンデバイス拡張である available() / install() は持たない。
    // これらを持たない実装を返してしまうと checkModel() / downloadModel() が
    // 未定義メソッド呼び出しで例外になり、Issue #30 の「非Chrome環境では
    // unavailable を返す」要件に違反する。両方を持つ実装のみ対応環境とみなす。
    if (ctor.has('available') && ctor.has('install')) return ctor;
  }
  return null;
}

/// `SpeechRecognition.available({langs:[locale], processLocally:true})` を
/// 呼び出し、解決値の文字列をそのまま返す。
///
/// reject時の扱いはこの関数の責務ではなく、呼び出し側
/// (`model_management.dart` / `recognition_session.dart`)のドキュメント
/// コメントを参照。ここでは単にPromiseをFutureへ変換するのみで、例外は
/// そのまま伝播させる。
Future<String> callAvailable(JSFunction ctor, String locale) async {
  final options = _AvailabilityOptions(
    langs: <JSString>[locale.toJS].toJS,
    processLocally: true,
  );
  final promise = ctor.callMethod<JSPromise<JSAny?>>('available'.toJS, options);
  final result = await promise.toDart;
  return (result! as JSString).toDart;
}

/// `SpeechRecognition.install({langs:[locale], processLocally:true})` を
/// 呼び出し、解決した真偽値を返す。
///
/// `install()` は進捗イベントを持たず `Promise<boolean>` のみを返すことを
/// Chrome 153実機で確認済み(design.md §4.1、spikes/web/RESULTS.md)。
Future<bool> callInstall(JSFunction ctor, String locale) async {
  final options = _AvailabilityOptions(
    langs: <JSString>[locale.toJS].toJS,
    processLocally: true,
  );
  final promise = ctor.callMethod<JSPromise<JSAny?>>('install'.toJS, options);
  final result = await promise.toDart;
  return (result! as JSBoolean).toDart;
}

/// `new SR()` でインスタンスを生成する。
web.SpeechRecognition createRecognition(JSFunction ctor) =>
    ctor.callAsConstructor<web.SpeechRecognition>();

/// `processLocally` を `true` に設定し、直後に読み戻して検証する。
///
/// NFR-2(サーバーへのサイレントフォールバック禁止)により、設定直後の
/// 読み戻し値が `true` でなければ、呼び出し側がフォールバックせず明確に
/// エラーとして扱わなければならない。この関数はその判定材料として
/// 真偽値を返すのみで、エラー化の判断・例外送出は呼び出し側
/// (`recognition_session.dart`)の責務とする。
bool setAndVerifyProcessLocally(web.SpeechRecognition recognition) {
  recognition.setProperty('processLocally'.toJS, true.toJS);
  final readBack = recognition.getProperty<JSAny?>('processLocally'.toJS);
  if (readBack == null || !readBack.isA<JSBoolean>()) return false;
  return (readBack as JSBoolean).toDart;
}

/// `recognition.start(audioTrack)` を呼び出す。
///
/// `package:web` の `SpeechRecognition.start()` は引数なしの標準シグネチャ
/// しか持たないため、動的メソッド呼び出しでChrome拡張の1引数版を叩く。
void startWithAudioTrack(
  web.SpeechRecognition recognition,
  web.MediaStreamTrack audioTrack,
) {
  recognition.callMethod<JSAny?>('start'.toJS, audioTrack);
}
