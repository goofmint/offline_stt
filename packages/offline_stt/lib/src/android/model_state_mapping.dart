import '../common.dart';

/// Pigeon生成の`pigeon.ModelState`(enum名の文字列表現、`.name`)を
/// [ModelState]へ写像する(design.md §2.2、requirements.md FR-1、
/// Issue #43)。
///
/// `pigeon.ModelState`型そのものではなく`.name`(String)を引数に取って
/// いる理由: Pigeon生成コード(`pigeon.g.dart`)は`BasicMessageChannel`/
/// `EventChannel`を使うため`package:flutter/services.dart`に依存する。
/// この依存を持つファイルを`dart test`(melosの`test`スクリプトが使う、
/// Flutter SDKパッチ〈`dart:ui`〉の無いテストランナー)が辿ると、
/// Flutterウィジェット層(`dart:ui`に依存する`gestures/velocity_tracker.dart`
/// 等)のコンパイルに失敗する。そのため本ファイルは`pigeon.g.dart`を一切
/// importせず、String(enum名)のみを受け取る形にすることで、
/// `flutter`パッケージに依存しない純粋ロジックとして単体テストできる
/// ようにしている(呼び出し側の`model_management.dart`で
/// `pigeon.ModelState.name`を渡す。Darwin実装と同じ構成)。
///
/// Kotlin側(`android/src/main/kotlin/com/moongift/offline_stt/
/// ModelAvailability.kt`)は、requirements.md FR-1が定める写像方針
/// (`SpeechRecognizer.checkRecognitionSupport()`が返す`RecognitionSupport`
/// の4リストの突き合わせ)に従い、既にこの4値のいずれかへ変換した状態で
/// Pigeonの`ModelState`を送出する。本関数はその文字列表現を
/// 共有層(`lib/src/model_state.dart`)の[ModelState]へ変換するだけであり、
/// 4リストの突き合わせロジック自体はネイティブ側の責務である
/// (`dart test`から`RecognitionSupport`等のOS APIに依存するKotlinコードを
/// テストできないため、Kotlin側は別途JVMユニットテストで検証する方針は
/// 取らず、実機E2E検証に委ねる。design.md §7参照)。
///
/// `pigeons/offline_stt_events.dart`の`ModelState`は
/// 共有層(`lib/src/model_state.dart`)の[ModelState]と値・順序を一致させる
/// 契約になっている(同ファイルのdocコメント参照)ため、enum名の文字列は
/// 完全一致する。未知の文字列が来た場合はフォールバックで丸めず
/// [StateError]を投げる(Web/Darwin実装の
/// `model_state_mapping.dart`と同じ方針)。
ModelState mapPigeonModelState(String pigeonEnumName) {
  switch (pigeonEnumName) {
    case 'available':
      return ModelState.available;
    case 'downloadable':
      return ModelState.downloadable;
    case 'downloading':
      return ModelState.downloading;
    case 'unavailable':
      return ModelState.unavailable;
    default:
      throw StateError(
        'Pigeon生成のModelStateが未知の値を返した: "$pigeonEnumName"。'
        'design.md §2.2が定める4値(available/downloadable/downloading/'
        'unavailable)以外の値はフォールバックで丸めず、明確にエラーにする。',
      );
  }
}
