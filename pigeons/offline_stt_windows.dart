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
  ModelState checkModel(String locale);

  /// モデルダウンロードを開始する(requirements.md FR-2)。
  ///
  /// 進捗は `OfflineSttStreamCallbackApi.onDownloadProgress` で配信される。
  /// 本メソッド自体は開始要求のみを表し、値を返さない。
  void downloadModel(String locale);

  /// 音声ファイルの文字起こしを開始する(requirements.md FR-3)。
  ///
  /// 結果は `OfflineSttStreamCallbackApi.onSegment` で配信される。
  /// 本メソッド自体は開始要求のみを表し、値を返さない。
  ///
  /// design.md §3 のとおり、`checkModel()` が `ModelState.available` 以外
  /// を返す状態でこのメソッドが呼ばれた場合、ネイティブ側は即座にエラーを
  /// 返さなければならない(内部で暗黙的にダウンロードを開始してはならない)。
  void transcribeFile(TranscribeRequest request);

  /// 実行中のダウンロード、または文字起こしセッションをキャンセルする
  /// (requirements.md FR-3)。
  ///
  /// design.md §3 のとおり同時セッションはv1では1本に制限されるため、
  /// キャンセル対象を明示するパラメータは持たない(実行中の1本のみが
  /// 対象になる)。
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
