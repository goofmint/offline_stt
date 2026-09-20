// Copyright (c) MOONGIFT
//
// offline_stt の Windows(C++/WinRT) 向け Pigeon スキーマ。
//
// 対応: design.md §2.2(データ型)/ §2.3(ブリッジ方式)、requirements.md FR-1
// FR-2 FR-3 FR-6、GitHub Issue #24。
//
// ## Android/Darwin用ファイルと分けている理由
//
// design.md §2.3 はストリーム(`segments` / `downloadProgress`)を
// Pigeonの `@EventChannelApi` で定義する方針だが、Pigeon(v29.0.2)の
// C++生成器は `@EventChannelApi` を含むスキーマを拒否する。実際に
// `pigeons/offline_stt_events.dart`(`@EventChannelApi` を含む)に対して
// `--cpp_header_out` / `--cpp_source_out` を指定してPigeonを実行すると
//
//   Error: <file>: C++ does not support event channels
//
// で失敗することを確認した。README にも
// "Event channels are supported only on the Swift, Kotlin, and Dart
// generators." と明記されている。
//
// そのため Windows 向けにはEventChannelを使わず、`@HostApi()` +
// `@FlutterApi()` のコールバックで同等のストリーム機能を代替する。
// これにより手書きのMethodChannel/EventChannelを避けつつ(design.md §2.3
// の「手書きMethodChannelは使わない」方針は維持)、C++で生成可能な形に
// 収める。
//
// ## データ型がAndroid/Darwin用ファイルと重複している理由
//
// Pigeonの入力ファイルは他のPigeon入力ファイルの型をimportして共有する
// 仕組みを持たないため、`ModelState` / `DownloadProgress` /
// `TranscribeRequest` / `TranscriptSegment` / `TranscribeErrorCode` は
// `pigeons/offline_stt_events.dart` 側と同一定義を重複して持つ。定義を
// 変更する場合は両ファイルを同時に更新すること。
//
// 生成コマンドはリポジトリルートの `pubspec.yaml` の melos スクリプト
// `pigeon:windows` を参照。

import 'package:pigeon/pigeon.dart';

/// モデルの状態を表す4値(design.md §2.2、requirements.md FR-1)。
///
/// `pigeons/offline_stt_events.dart` の同名enumと値・順序を一致させる
/// こと(重複定義の理由は本ファイル冒頭コメント参照)。
enum ModelState { available, downloadable, downloading, unavailable }

/// モデルダウンロードの進捗(design.md §2.2)。
///
/// design.md §4.4 のとおり、Windowsは `EnsureReadyAsync()` の進捗API粒度が
/// 粗い場合があり、`fraction: null` の不定進捗として通知することを想定する。
class DownloadProgress {
  DownloadProgress({this.fraction, required this.completed});

  /// 進捗率(0.0〜1.0)。`null` は不定進捗を表す。
  double? fraction;

  /// ダウンロードが完了したかどうか。
  bool completed;
}

/// `transcribeFile` へ渡すリクエスト(design.md §2.2)。
///
/// 注記: 現行の design.md §2.2 に `playbackRate` フィールドは存在しない
/// (2026-09-20 時点。PR #74 で追加予定だが本ブランチは分岐前のため未反映)。
/// そのため本スキーマでも `path` / `locale` の2フィールドのみを定義する。
class TranscribeRequest {
  TranscribeRequest({required this.path, required this.locale});

  /// 文字起こし対象の音声ファイルパス。
  String path;

  /// BCP-47形式のロケール(例: `ja-JP`)。
  String locale;
}

/// 文字起こし結果の1セグメント(design.md §2.2)。
///
/// design.md §4.4 のとおり、Windowsのバッチ認識は `isFinal: true` のセグ
/// メントを1回だけemitする想定である。
class TranscriptSegment {
  TranscriptSegment({required this.text, required this.isFinal});

  /// 認識されたテキスト。
  String text;

  /// 確定結果かどうか(`false` はpartial)。
  bool isFinal;
}

/// 共通エラー型(requirements.md FR-6、design.md §2.2 の `TranscribeException`
/// sealed階層に対応する列挙型)。
///
/// C++/WinRTはPigeonのsealed class生成対象外である
/// (Kotlin/Swift/C++いずれの生成器も `_errorOnSealedClass` により拒否する)
/// ため、型安全にエラー種別を伝える手段としてこの列挙型を用いる。
/// Windows実装では特に、後述の `OfflineSttStreamCallbackApi.onStreamError`
/// のワイヤ型としてそのまま使用する(EventChannelの組み込みエラーシンクが
/// 無いため、明示的なコールバックとして表現する必要がある)。
///
/// `PlatformException_`(design.mdの命名)には `code` / `message` の
/// 自由形式フィールドがあるため、`platformError` 1値に対応させる。
enum TranscribeErrorCode {
  modelUnavailable,
  localeUnsupported,
  decodeFailed,
  deviceUnsupported,
  cancelled,
  platformError,
}

/// Method チャネル(design.md §2.3)。
///
/// `downloadModel` / `transcribeFile` は開始のみを担う。進捗・結果は
/// 下記 `OfflineSttStreamCallbackApi`(FlutterApiコールバック)で配信する。
@HostApi()
abstract class OfflineSttHostApi {
  /// 対象ロケールのモデル状態を確認する(requirements.md FR-1)。
  ///
  /// ## `@async` を付与する理由
  /// `pigeons/offline_stt_events.dart` の同名メソッドと契約(HostApi)を
  /// 揃えるため付与する。design.md §4.4 のとおりWindowsの写像元は
  /// `GetReadyState()`(Async接尾辞が無いためAPI自体は同期の見込み)だが、
  /// PigeonのC++生成器は `@async` を付けたメソッドを
  /// `std::function<void(ErrorOr<ModelState> reply)>` を受け取るコール
  /// バック形式で生成する(実際に生成して確認済み。`windows/pigeon.g.h`
  /// 参照)。M4実装では `GetReadyState()` の結果を即座に
  /// `result(...)` で返せばよく、同期実装しか用意できない場合でも
  /// 不利にならない。将来的にWindows側の判定処理が非同期化しても
  /// このコールバック形式のまま自然に対応できる。
  @async
  ModelState checkModel(String locale);

  /// モデルダウンロードを開始する(requirements.md FR-2)。
  ///
  /// 進捗は `OfflineSttStreamCallbackApi.onDownloadProgress` で配信される。
  /// 本メソッド自体は開始要求のみを表し、値を返さない。
  ///
  /// ## `@async` を付けない理由
  /// `pigeons/offline_stt_events.dart` の同名メソッドと同様「開始要求
  /// のみ」の契約である。`EnsureReadyAsync()`(design.md §4.4)の完了を
  /// 待たずに開始要求だけを受け付けて直ちに制御を返せる設計とし、進捗・
  /// 完了は `OfflineSttStreamCallbackApi.onDownloadProgress` /
  /// `onStreamDone` で別途通知する。
  void downloadModel(String locale);

  /// 音声ファイルの文字起こしを開始する(requirements.md FR-3)。
  ///
  /// 結果は `OfflineSttStreamCallbackApi.onSegment` で配信される。
  /// 本メソッド自体は開始要求のみを表し、値を返さない。
  ///
  /// design.md §3 のとおり、`checkModel()` が `ModelState.available` 以外
  /// を返す状態でこのメソッドが呼ばれた場合、ネイティブ側は即座にエラーを
  /// 返さなければならない(内部で暗黙的にダウンロードを開始してはならない)。
  ///
  /// ## `@async` を付けない理由
  /// `downloadModel` と同様に「開始要求のみ」の契約であり、
  /// `BatchRecognition.RecognizeFromFile` の完了を待たずに開始要求だけを
  /// 受け付けて直ちに制御を返せる。
  void transcribeFile(TranscribeRequest request);

  /// 実行中のダウンロード、または文字起こしセッションをキャンセルする
  /// (requirements.md FR-3)。
  ///
  /// design.md §3 のとおり同時セッションはv1では1本に制限されるため、
  /// キャンセル対象を明示するパラメータは持たない(実行中の1本のみが
  /// 対象になる)。
  ///
  /// ## `@async` を付けない理由
  /// 実行中の非同期処理へキャンセル要求を送るだけの同期的な操作である
  /// (完了を待つ必要がない)。
  void cancel();
}

/// FlutterApiコールバック(design.md §2.3)。Windows(C++/WinRT) 向け。
///
/// Android/Darwinの `@EventChannelApi` に相当するストリーム機能を、Pigeon
/// の C++ 生成器が対応していないため `@FlutterApi()` のコールバック列で
/// 代替する(本ファイル冒頭のコメント参照)。EventChannelと異なり暗黙の
/// ストリーム終了・エラー伝播が無いため、`onStreamError` /
/// `onStreamDone` を明示的なメソッドとして定義する。
@FlutterApi()
abstract class OfflineSttStreamCallbackApi {
  /// 文字起こし結果1件を通知する(requirements.md FR-3)。
  ///
  /// design.md §4.4 のとおりWindowsは `isFinal: true` の1件のみをemitし、
  /// 直後に `onStreamDone` が呼ばれる想定である。
  void onSegment(TranscriptSegment segment);

  /// モデルダウンロード進捗を通知する(requirements.md FR-2)。
  void onDownloadProgress(DownloadProgress progress);

  /// ストリームがエラーで終了したことを通知する(requirements.md FR-6)。
  ///
  /// `message` はプラットフォーム固有の詳細情報(存在する場合)であり、
  /// `code` が `TranscribeErrorCode.platformError` の場合に主として使う
  /// 想定である。
  void onStreamError(TranscribeErrorCode code, String? message);

  /// ストリームが正常に終了したことを通知する。
  void onStreamDone();
}
