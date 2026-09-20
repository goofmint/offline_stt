import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// Pigeon生成の`pigeon.ModelState`(enum名の文字列表現、`.name`)を
/// [ModelState]へ写像する(design.md §2.2、requirements.md FR-1、
/// Issue #35)。
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
/// `pigeon.ModelState.name`を渡す)。
///
/// `pigeons/offline_stt_events.dart`の`ModelState`は
/// `offline_stt_platform_interface`の[ModelState]と値・順序を一致させる
/// 契約になっている(同ファイルのdocコメント参照)ため、enum名の文字列は
/// 完全一致する。未知の文字列が来た場合はフォールバックで丸めず
/// [StateError]を投げる(offline_stt_webの`model_state_mapping.dart`と
/// 同じ方針)。
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
