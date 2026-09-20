import 'dart:async';

import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

import 'model_state_mapping.dart';
import 'speech_recognition_js.dart';

/// モデル管理層(design.md §4.1、requirements.md FR-1/FR-2、Issue #26・#30)。
///
/// このファイルはブラウザAPIを直接叩く層であるため単体テストを書かない
/// (状態写像そのものは `model_state_mapping.dart` に切り出して単体テストする。
/// テスト方針の詳細は `speech_recognition_js.dart` 冒頭コメントを参照)。

/// requirements.md FR-1。design.md §4.1「Chrome以外・非対応環境は
/// checkModel()がunavailableを返す」(Issue #30)。
///
/// `window.SpeechRecognition` / `window.webkitSpeechRecognition` のいずれも
/// 存在しなければ、例外を投げず [ModelState.unavailable] を返す。
///
/// `SpeechRecognition.available()` がrejectした場合は、そのまま例外を
/// 伝播させる。design.md §2.1の`checkModel()`契約は「4値のいずれかを返す」
/// ことを定めるのみで、reject時にどの値へ丸めるべきかは定義していない。
/// ここで安易に `unavailable` 等へ丸めるのはプロジェクト方針で禁止された
/// フォールバック処理そのものであり、「取得できない場合は明確にエラーに
/// する」という方針に従い、rejectをそのまま呼び出し側に伝える判断とした。
Future<ModelState> checkModel(String locale) async {
  final ctor = findSpeechRecognitionConstructor();
  if (ctor == null) {
    return ModelState.unavailable;
  }
  final availability = await callAvailable(ctor, locale);
  return mapAvailabilityToModelState(availability);
}

/// requirements.md FR-2。
///
/// design.md §3「状態遷移の細則」3.のとおり、`downloadable` 以外の状態
/// (非Chrome環境を含む `available` / `downloading` / `unavailable`)で
/// 呼ばれた場合は、状態を一切変化させず何もemitせずに完了するStreamを
/// 返す。
///
/// また同細則は「状態変化(downloadable→downloading)は、transcribeFile()とは
/// 異なり呼び出し時点で即座に確定させる」と定める。これを満たすため、
/// `async*` ジェネレータ(購読されるまで本体が実行されない)は使わず、
/// `downloadModel()` 呼び出し時点で即座に非同期処理を開始し、
/// `StreamController` へイベントを積む方式を採る(非購読の
/// `StreamController` へ `add()` してもイベントはバッファされ、後から
/// 購読されれば配信される)。
Stream<DownloadProgress> downloadModel(String locale) {
  final controller = StreamController<DownloadProgress>();
  unawaited(_runDownload(controller, locale));
  return controller.stream;
}

Future<void> _runDownload(
  StreamController<DownloadProgress> controller,
  String locale,
) async {
  try {
    final ctor = findSpeechRecognitionConstructor();
    if (ctor == null) {
      await controller.close();
      return;
    }
    final availability = await callAvailable(ctor, locale);
    final state = mapAvailabilityToModelState(availability);
    if (state != ModelState.downloadable) {
      await controller.close();
      return;
    }

    // install()は進捗イベントを持たずPromise<boolean>のみを返す
    // (Chrome 153実機確認済み、design.md §4.1、spikes/web/RESULTS.md)。
    // そのため不定進捗(fraction: null)として扱い、開始時に未完了を1回、
    // 完了時に完了を1回、計2回emitする(呼び出し側が「開始した」ことと
    // 「終わった」ことの両方を観測できるようにするため)。
    controller.add(DownloadProgress(fraction: null, completed: false));
    final installed = await callInstall(ctor, locale);
    if (!installed) {
      // install()の解決値がfalseの場合。フォールバック禁止の方針により、
      // 「完了扱い」にはせず明確にエラーとして終了する。
      controller.addError(
        const PlatformException_(
          code: 'install-resolved-false',
          message: 'SpeechRecognition.install() が false に解決した',
        ),
      );
      await controller.close();
      return;
    }
    controller.add(DownloadProgress(fraction: null, completed: true));
    await controller.close();
  } on Object catch (e, st) {
    controller.addError(e, st);
    await controller.close();
  }
}
