import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

import 'model_management.dart' as model_management;
import 'pigeon.g.dart' as pigeon;
import 'platform_exception_mapping.dart';
import 'stream_router.dart';

/// 認識セッション本体(design.md §4.4、requirements.md FR-3、
/// Issue #55 #56)。
///
/// 呼び出し側(`OfflineSttWindows.transcribeFile()`)が
/// `offline_stt_platform_interface`の`TranscribeSessionGuard`でこの
/// Streamをラップし、design.md §3のセッション排他規則(同時1本まで・
/// 2本目はStreamエラーでStateError)を満たす前提である。
///
/// ## Windowsのセグメント数
/// design.md §4.4のとおり、`BatchRecognition.RecognizeFromFile()` は
/// 単一の文字列を返すバッチAPIであり、partial結果を通知するイベントを
/// 持たない(partialは`StreamingRecognition`側にのみ存在する。
/// spikes/windows/src/Core/FileRecognition.h参照)。したがってこの
/// Streamに流れるのは`isFinal: true`のセグメント1件のみで、その直後に
/// `onStreamDone`が届く。
///
/// ## このファイルの責務と単体テストの切り分け
/// PigeonのHostApi/FlutterApiコールバックを直接叩く層であるため、この
/// ファイル自体の単体テストは書かない。純粋ロジック(状態写像・エラー
/// 写像)は別ファイルへ切り出し、そちらを単体テストする
/// (`model_state_mapping.dart`・`error_code_mapping.dart`)。
/// ネイティブ依存部分の検証はIssue #58の実機E2Eでカバーする
/// (Windows実機が無いため、本パッケージのネイティブ側はビルドも実行も
/// 一度も行えていない)。
Stream<TranscriptSegment> runTranscriptionSession(
  pigeon.OfflineSttHostApi hostApi,
  TranscribeRequest request,
) {
  late final StreamController<TranscriptSegment> controller;
  final router = WindowsStreamRouter.instance;
  late final WindowsStreamRoute route;
  var attached = false;
  var finished = false;

  void finish({Object? error, StackTrace? stackTrace}) {
    if (finished) return;
    finished = true;
    if (attached) router.detach(route);
    if (error != null) {
      controller.addError(error, stackTrace ?? StackTrace.current);
    }
    unawaited(controller.close());
  }

  route = WindowsStreamRoute(
    onSegment: (segment) {
      if (finished) return;
      controller.add(segment);
    },
    onError: (error) => finish(error: error),
    onDone: finish,
  );

  controller = StreamController<TranscriptSegment>(
    onListen: () {
      unawaited(() async {
        // design.md §3: transcribeFile()はcheckModel()相当がavailable
        // 以外なら即座にModelUnavailableExceptionをStreamエラーで返す。
        // 内部で暗黙的にモデルをダウンロードしてはならない
        // (`offline_stt_darwin`の`recognition_session.dart`と同じ方針)。
        // ネイティブ側(windows/offline_stt_api_impl.cpp)にも同じガードが
        // ある。`pigeons/offline_stt_windows.dart`の`transcribeFile`の
        // docコメントが「ネイティブ側は即座にエラーを返さなければ
        // ならない」と定めているためで、二重チェックは意図的である。
        final ModelState state;
        try {
          state = await model_management.checkModel(hostApi, request.locale);
        } on TranscribeException catch (e) {
          finish(error: e);
          return;
        }
        if (finished) return; // 上記await中にキャンセルされた場合。
        if (state != ModelState.available) {
          finish(error: const ModelUnavailableException());
          return;
        }

        // 配送先の登録は hostApi.transcribeFile() 呼び出しより先に行う
        // (呼び出し直後にネイティブが早期のセグメントを送出しても
        // 取りこぼさないようにするため)。
        try {
          router.attach(route);
          attached = true;
        } on StateError catch (e, st) {
          finish(error: e, stackTrace: st);
          return;
        }

        // design.md §2.2: `playbackRate`はWeb専用オプションであり、
        // Windows(BatchRecognition)はバッチ処理で速度という概念自体が
        // 無いため無視する。`pigeons/offline_stt_windows.dart`の
        // `TranscribeRequest`には現行ブランチの時点で`playbackRate`
        // フィールド自体が存在しないため、`path`/`locale`のみを
        // ネイティブへ渡す形で自然に無視される。
        final nativeRequest = pigeon.TranscribeRequest(
          path: request.path,
          locale: request.locale,
        );

        try {
          await hostApi.transcribeFile(nativeRequest);
        } on PlatformException catch (e, st) {
          finish(error: mapPlatformException(e), stackTrace: st);
          return;
        }
      }());
    },
    onCancel: () {
      // design.md §3・§5 Cancelled: 購読キャンセル時はネイティブ側へ
      // 明示的にキャンセルを要求する(`OfflineSttHostApi.cancel()`)。
      if (finished) return null;
      finished = true;
      if (!attached) {
        // まだ hostApi.transcribeFile() を呼ぶ前(checkModel待ちなど)。
        // ネイティブ側に止めるものが無いのでcancelは呼ばない。
        return null;
      }
      router.detach(route);
      return hostApi.cancel();
    },
  );

  return controller.stream;
}
