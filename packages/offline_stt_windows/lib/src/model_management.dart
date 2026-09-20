import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

import 'model_state_mapping.dart';
import 'pigeon.g.dart' as pigeon;
import 'platform_exception_mapping.dart';
import 'stream_router.dart';

/// モデル管理層(design.md §4.4、requirements.md FR-1/FR-2、Issue #53)。
///
/// PigeonのHostApi/FlutterApiコールバックを直接叩く層であるため、この
/// ファイル自体の単体テストは書かない(状態写像・エラー写像そのものは
/// `model_state_mapping.dart`・`error_code_mapping.dart`に切り出して単体
/// テストする。`offline_stt_darwin`/`offline_stt_android`と同じ切り分け)。
/// `DownloadProgress`はフィールドをそのまま写すだけで分岐ロジックを
/// 持たないため、専用の写像関数には切り出さず呼び出し箇所
/// (`stream_router.dart`)で直接組み立てている。

/// requirements.md FR-1。
///
/// Windowsの写像元は`SpeechRecognitionModel.GetReadyState()`
/// (`AIFeatureReadyState`、7値)であり、4値への写像はネイティブ側
/// (`windows/model_availability.cpp`)で行う。
///
/// ## `locale`引数の扱い
/// design.md §4.4・§8 未決事項2のとおり、`Microsoft.Windows.AI.Speech`
/// にはロケール・言語を指定するAPIが存在しないことがドキュメント調査で
/// 確定している。そのため`locale`はネイティブへ渡されるものの、モデル
/// 状態の判定には使われない(認識される言語はOS側の設定に依存する)。
/// これはdesign.mdが明示的に許容した仕様であって、値が取れないのを
/// 既定値で埋めるフォールバックではない。
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
/// `hostApi.downloadModel()`を呼び始める(`offline_stt_darwin`の
/// `src/model_management.dart`と同じ設計判断)。
///
/// 配送先([WindowsStreamRoute])の登録は`hostApi.downloadModel()`を呼ぶ
/// より先に行う(呼び出し直後に届く早期の進捗イベントを取りこぼさない
/// ようにするため)。
///
/// design.md §3細則3の「`downloadable`以外の状態で呼ばれた場合は何も
/// emitせずに完了する」はネイティブ側(`windows/offline_stt_api_impl.cpp`
/// の`DownloadModel`)が`onStreamDone`だけを返すことで満たす。
Stream<DownloadProgress> downloadModel(
  pigeon.OfflineSttHostApi hostApi,
  String locale,
) {
  final controller = StreamController<DownloadProgress>();
  final router = WindowsStreamRouter.instance;
  var finished = false;
  late final WindowsStreamRoute route;

  void finish({Object? error, StackTrace? stackTrace}) {
    if (finished) return;
    finished = true;
    router.detach(route);
    if (error != null) {
      controller.addError(error, stackTrace ?? StackTrace.current);
    }
    unawaited(controller.close());
  }

  route = WindowsStreamRoute(
    onDownloadProgress: (progress) {
      if (finished) return;
      controller.add(progress);
    },
    onError: (error) => finish(error: error),
    onDone: finish,
  );

  try {
    router.attach(route);
  } on StateError catch (e, st) {
    // 既に別のストリーム(文字起こし、または別のダウンロード)が実行中。
    // 同期throwにせずStreamエラーとして通知する(design.md §3細則2が
    // 2本目のセッションについて定める流儀に揃えている)。
    controller.addError(e, st);
    unawaited(controller.close());
    return controller.stream;
  }

  controller.onCancel = () {
    if (finished) return null;
    finished = true;
    router.detach(route);
    // design.md §5 Cancelled: 購読キャンセル時はネイティブ側へ明示的に
    // キャンセルを要求する。
    return hostApi.cancel();
  };

  unawaited(() async {
    try {
      await hostApi.downloadModel(locale);
    } on PlatformException catch (e, st) {
      finish(error: mapPlatformException(e), stackTrace: st);
    }
  }());

  return controller.stream;
}
