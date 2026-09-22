import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import '../common.dart';

import 'model_state_mapping.dart';
import '../pigeon.g.dart' as pigeon;
import 'platform_exception_mapping.dart';

/// モデル管理層(design.md §4.2、requirements.md FR-1/FR-2、Issue #35)。
///
/// PigeonのHostApi/EventChannelを直接叩く層であるため、このファイル自体の
/// 単体テストは書かない(状態写像・エラー写像そのものは
/// `model_state_mapping.dart`・`error_code_mapping.dart`に切り出して単体
/// テストする。テスト方針の詳細は`src/darwin/offline_stt_darwin.dart`
/// 冒頭コメントを参照)。`DownloadProgress`はフィールドをそのまま写す
/// だけで分岐ロジックを持たないため、専用の写像関数には切り出さず
/// 呼び出し箇所で直接組み立てている。

/// requirements.md FR-1。
Future<ModelState> checkModel(
  pigeon.OfflineSttHostApi hostApi,
  String locale,
) async {
  try {
    final result = await hostApi.checkModel(locale);
    return mapPigeonModelState(result.name);
  } on PlatformException catch (e) {
    throw mapPlatformException(e);
  }
}

/// requirements.md FR-2。
///
/// design.md §3「状態遷移の細則」3.は「状態変化(downloadable→downloading)
/// は、transcribeFile()とは異なり呼び出し時点で即座に確定させる」と定める。
/// これを満たすため`async*`ジェネレータ(購読されるまで本体が実行されない)
/// は使わず、`downloadModel()`呼び出し時点で即座に
/// `hostApi.downloadModel()`を呼び始める(Web実装の
/// `src/model_management.dart`と同じ設計判断)。
///
/// ネイティブ側の`downloadProgress`EventChannelは、`hostApi.downloadModel()`
/// を呼ぶより先に購読を開始する(呼び出し直後に届く早期の進捗イベントを
/// 取りこぼさないようにするため)。
Stream<DownloadProgress> downloadModel(
  pigeon.OfflineSttHostApi hostApi,
  String locale,
) {
  final controller = StreamController<DownloadProgress>();

  final nativeSubscription = pigeon.downloadProgress().listen(
    (event) => controller.add(
      DownloadProgress(fraction: event.fraction, completed: event.completed),
    ),
    onError: (Object error, StackTrace stackTrace) {
      if (error is PlatformException) {
        controller.addError(mapPlatformException(error), stackTrace);
      } else {
        controller.addError(error, stackTrace);
      }
    },
    onDone: () => unawaited(controller.close()),
  );

  controller.onCancel = () => nativeSubscription.cancel();

  unawaited(() async {
    try {
      await hostApi.downloadModel(locale);
    } on PlatformException catch (e, st) {
      controller.addError(mapPlatformException(e), st);
      await nativeSubscription.cancel();
      await controller.close();
    } catch (e, st) {
      // PlatformException以外(例: プラグイン未登録の`MissingPluginException`)
      // をここで拾わないと、未処理の非同期エラーになるだけでcontrollerは
      // エラーも完了も受け取らない。購読側は失敗を検知できないまま待ち続ける。
      controller.addError(e, st);
      await nativeSubscription.cancel();
      await controller.close();
    }
  }());

  return controller.stream;
}
