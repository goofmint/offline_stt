import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// Pigeon生成の`pigeon.ModelState`(enum名の文字列表現、`.name`)を
/// [ModelState]へ写像する(design.md §2.2、requirements.md FR-1、
/// Issue #53)。
///
/// `pigeon.ModelState`型そのものではなく`.name`(String)を引数に取って
/// いる理由は`offline_stt_darwin`/`offline_stt_android`の同名ファイルと
/// 同じである: Pigeon生成コード(`pigeon.g.dart`)は`BasicMessageChannel`
/// を使うため`package:flutter/services.dart`に依存する。この依存を持つ
/// ファイルを`dart test`(melosの`test`スクリプトが使う、Flutter SDK
/// パッチ〈`dart:ui`〉の無いテストランナー)が辿ると、Flutterウィジェット層
/// のコンパイルに失敗する。そのため本ファイルは`pigeon.g.dart`を一切
/// importせず、String(enum名)のみを受け取る形にすることで、
/// `flutter`パッケージに依存しない純粋ロジックとして単体テストできる
/// ようにしている(呼び出し側の`model_management.dart`で
/// `pigeon.ModelState.name`を渡す)。
///
/// ## Windows側で4値がどう決まるか(FR-1の写像はネイティブ側にある)
/// Windowsの写像元は`SpeechRecognitionModel.GetReadyState()`が返す
/// `AIFeatureReadyState`(7値)であり、4値への写像は
/// `windows/model_availability.cpp`で行う。design.md §4.4が明記するとおり
/// `downloading`に一意対応する`AIFeatureReadyState`の値は存在しないため、
/// その補い方も同ファイルのコメントに記載している。本ファイルは
/// 「ネイティブが返した4値の文字列をDartのenumへ戻す」だけを担う。
///
/// `pigeons/offline_stt_windows.dart`の`ModelState`は
/// `offline_stt_platform_interface`の[ModelState]と値・順序を一致させる
/// 契約になっている(同ファイルのdocコメント参照)ため、enum名の文字列は
/// 完全一致する。未知の文字列が来た場合はフォールバックで丸めず
/// [StateError]を投げる(`offline_stt_darwin`の`model_state_mapping.dart`と
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
