import 'dart:async';

import '../common.dart';
import '../locale_list.dart';

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

/// requirements.md FR-5。
///
/// **このブラウザが扱えるロケールの集合を返す。`available` なロケールの
/// 一覧ではない**(意味と制約は `OfflineTranscriber.supportedLocales()` の
/// ドキュメントコメント参照)。
///
/// ## 手順
/// 1. `speechSynthesis.getVoices()` の各 `lang` を候補にする
///    ([browserVoiceLocaleTags])。**ロケールの静的リストは持たない**
///    (requirements.md FR-5)
/// 2. 候補の重複を除く([dedupeLocaleTags])
/// 3. 候補を **1件ずつ** `SpeechRecognition.available()` へ問い合わせ、
///    `unavailable` 以外が返ったものだけを採る
///
/// ## 1件ずつ問い合わせる理由
/// `available({langs: [...]})` は複数ロケールを受け取れるが、返るのは
/// **「1つでも非対応なら `unavailable`」という集約結果**だけであり、
/// どのロケールが対応しているかは分からない。したがってまとめて渡しては
/// ならず、1ロケールにつき1回呼ぶ必要がある。件数分の往復が発生するため
/// 他のプラットフォームより時間がかかる。
///
/// 判定は `processLocally: true`(オンデバイス、requirements.md NFR-2)で
/// 行う。`quality` は指定せず既定値(`command`)のままである
/// (`checkModel` / 認識セッションと同じ条件に揃えるため)。
///
/// ## 空リストを返さない
/// 非Chrome環境(`SpeechRecognition` が無い、または Chrome 固有の
/// `available()` / `install()` を持たない)は `checkModel` と同じ判定
/// ([findSpeechRecognitionConstructor])で検出し、
/// [DeviceUnsupportedException] を投げる。ボイス一覧が空のまま取れない
/// 場合、および1件も対応ロケールが無かった場合も同様である。
Future<List<String>> supportedLocales() async {
  final ctor = findSpeechRecognitionConstructor();
  if (ctor == null) {
    // `checkModel` は非Chrome環境で `unavailable`(FR-1 の終端状態)を
    // 返せるが、一覧には「対応ロケールが無い」を表す正しい値が無いため、
    // ここは明示的なエラーにする。
    throw const DeviceUnsupportedException();
  }

  final candidates = dedupeLocaleTags(await browserVoiceLocaleTags());
  // 候補が1つも作れなければ、対応状況を問い合わせる相手がいない。
  // 「対応ロケールが無い」と report してはならない(まだ何も判定していない)。
  requireNonEmptyLocales(candidates);

  final supported = <String>[];
  for (final tag in candidates) {
    final availability = await callAvailable(ctor, tag);
    if (mapAvailabilityToModelState(availability) != ModelState.unavailable) {
      supported.add(tag);
    }
  }
  return requireNonEmptyLocales(supported);
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
