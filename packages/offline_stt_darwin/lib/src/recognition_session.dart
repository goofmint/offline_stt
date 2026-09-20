import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

import 'model_management.dart' as model_management;
import 'pigeon.g.dart' as pigeon;
import 'platform_exception_mapping.dart';

/// 認識セッション本体(design.md §4.2、requirements.md FR-3、
/// Issue #36 #37 #38)。
///
/// 呼び出し側(`OfflineSttDarwin.transcribeFile()`)が
/// `offline_stt_platform_interface`の`TranscribeSessionGuard`でこの
/// Streamをラップし、design.md §3のセッション排他規則(同時1本まで・
/// 2本目はStreamエラーでStateError)を満たす前提である。
///
/// ## このファイルの責務と単体テストの切り分け
/// PigeonのHostApi/EventChannelを直接叩く層であるため、このファイル自体の
/// 単体テストは書かない。純粋ロジック(状態写像・エラー写像)は別ファイルへ
/// 切り出し、そちらを単体テストする(`model_state_mapping.dart`・
/// `error_code_mapping.dart`)。`TranscriptSegment`はフィールドをそのまま
/// 写すだけで分岐ロジックを持たないため、専用の写像関数には切り出さず
/// 呼び出し箇所で直接組み立てている。ネイティブ依存部分の検証はIssue #40の
/// 実機E2Eでカバーする。
Stream<TranscriptSegment> runTranscriptionSession(
  pigeon.OfflineSttHostApi hostApi,
  TranscribeRequest request,
) {
  late final StreamController<TranscriptSegment> controller;
  StreamSubscription<pigeon.TranscriptSegment>? nativeSubscription;
  var finished = false;

  void finish({Object? error, StackTrace? stackTrace}) {
    if (finished) return;
    finished = true;
    if (error != null) {
      controller.addError(error, stackTrace ?? StackTrace.current);
    }
    unawaited(nativeSubscription?.cancel());
    unawaited(controller.close());
  }

  controller = StreamController<TranscriptSegment>(
    onListen: () {
      unawaited(() async {
        // design.md §3: transcribeFile()はcheckModel()相当がavailable
        // 以外なら即座にModelUnavailableExceptionをStreamエラーで返す。
        // 内部で暗黙的にモデルをダウンロードしてはならない
        // (offline_stt_webの`recognition_session.dart`と同じ方針)。
        final ModelState state;
        try {
          state = await model_management.checkModel(hostApi, request.locale);
        } on TranscribeException catch (e) {
          finish(error: e);
          return;
        } catch (e, st) {
          // TranscribeException 以外(例: プラグイン未登録の
          // `MissingPluginException`)をここで拾わないと、`unawaited` の
          // クロージャ内で未処理の非同期エラーになるだけで Stream は終了
          // せず、`TranscribeSessionGuard` がセッション枠を保持し続ける。
          finish(error: e, stackTrace: st);
          return;
        }
        if (finished) return; // 上記await中にキャンセルされた場合。
        if (state != ModelState.available) {
          finish(error: const ModelUnavailableException());
          return;
        }

        // segments()のEventChannel購読は、hostApi.transcribeFile()呼び出し
        // より先に確立する(呼び出し直後にネイティブが早期のセグメントを
        // 送出しても取りこぼさないようにするため)。
        nativeSubscription = pigeon.segments().listen(
          (event) {
            if (finished) return;
            controller.add(
              TranscriptSegment(text: event.text, isFinal: event.isFinal),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            if (error is PlatformException) {
              finish(
                error: mapPlatformException(error),
                stackTrace: stackTrace,
              );
            } else {
              finish(error: error, stackTrace: stackTrace);
            }
          },
          onDone: finish,
        );

        // design.md §2.2: `playbackRate`はWeb専用オプションであり、
        // Darwinでは無視する。`pigeons/offline_stt_events.dart`の
        // `TranscribeRequest`には現行ブランチの時点で`playbackRate`
        // フィールド自体が存在しない(PR#74で追加予定だが本ブランチは
        // 分岐前のため未反映。同ファイル冒頭コメント参照)ため、
        // `path`/`locale`のみをネイティブへ渡す形で自然に無視される。
        final nativeRequest = pigeon.TranscribeRequest(
          path: request.path,
          locale: request.locale,
        );

        try {
          await hostApi.transcribeFile(nativeRequest);
        } on PlatformException catch (e, st) {
          finish(error: mapPlatformException(e), stackTrace: st);
          return;
        } catch (e, st) {
          // PlatformException 以外も同様に Stream を終了させる(理由は
          // 上の catch のコメント参照)。
          finish(error: e, stackTrace: st);
          return;
        }
      }());
    },
    onCancel: () {
      // design.md §3・§5 Cancelled: 購読キャンセル時はネイティブ側へ
      // 明示的にキャンセルを要求する(`HostApi.cancel()`、
      // `pigeons/offline_stt_events.dart`のドキュメントコメント参照)。
      if (finished) return null;
      finished = true;
      unawaited(nativeSubscription?.cancel());
      return hostApi.cancel();
    },
  );

  return controller.stream;
}
