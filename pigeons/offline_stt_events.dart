// Copyright (c) MOONGIFT
//
// offline_stt の Android(Kotlin) / Darwin(Swift) 向け Pigeon スキーマ。
//
// 対応: design.md §2.2(データ型)/ §2.3(ブリッジ方式)、requirements.md FR-1
// FR-2 FR-3 FR-6、GitHub Issue #24。
//
// ## ファイルをWindows用と分けている理由
//
// design.md §2.3 の方針どおり、ストリーム(`segments` / `downloadProgress`)
// は Pigeon の `@EventChannelApi` で定義している。しかし `@EventChannelApi`
// を含むスキーマから C++ 出力を生成しようとすると、Pigeon(v29.0.2)は
// 生成時点で
//
//   Error: <file>: C++ does not support event channels
//
// というエラーで停止する。これは実際に
// `dart pub global run pigeon --input <このファイル> --cpp_header_out ... --cpp_source_out ...`
// を実行して確認した事実である(READMEにも
// "Event channels are supported only on the Swift, Kotlin, and Dart
// generators." と明記されている)。そのため Windows 向けのC++生成は本
// ファイルから行えず、`pigeons/offline_stt_windows.dart` にスキーマを
// 分離した(`@ConfigurePigeon` の出し分けでは解決できない制約である)。
//
// ## データ型がWindows用ファイルと重複している理由
//
// Pigeonの入力ファイルはそれぞれ独立してASTを構築する設計であり、他の
// Pigeon入力ファイルの型をimportして共有する仕組みを持たない。そのため
// `ModelState` / `DownloadProgress` / `TranscribeRequest` /
// `TranscriptSegment` / `TranscribeErrorCode` は
// `pigeons/offline_stt_windows.dart` 側にも同一定義を重複して持つ。
// 定義を変更する場合は両ファイルを同時に更新すること。
//
// 生成コマンドはリポジトリルートの `pubspec.yaml` の melos スクリプト
// `pigeon:android` / `pigeon:darwin` を参照。

import 'package:pigeon/pigeon.dart';

/// モデルの状態を表す4値(design.md §2.2、requirements.md FR-1)。
///
/// `offline_stt_platform_interface` の `ModelState`(
/// `packages/offline_stt_platform_interface/lib/src/model_state.dart`)と
/// 値・順序を一致させること。マッピングは各実装パッケージ側で行う。
enum ModelState { available, downloadable, downloading, unavailable }

/// モデルダウンロードの進捗(design.md §2.2)。
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
/// design.md §2.2 の `TranscribeException` 階層はDartのsealed classとして
/// 定義されているが、Pigeonはsealed classをコード生成対象にできない
/// (Kotlin/Swift/C++いずれの生成器も `_errorOnSealedClass` により拒否する)。
/// そのため、プラットフォーム境界を越えて型安全にエラー種別を伝える用途に
/// 限り、対応する列挙型としてこの `TranscribeErrorCode` を追加定義する
/// (design.mdには存在しない型だが、CodeRabbitの計画で明示的に追加が指示
/// されている)。ネイティブ側はこの列挙値を用いてエラーを通知し、Dart側
/// (各実装パッケージの `lib/`)がこれを `TranscribeException` の具象サブ
/// クラスへマッピングする。マッピング自体はPigeon生成コードの範囲外であり
/// 各実装パッケージ側の責務とする。
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
/// 下記 `OfflineSttStreamEvents`(EventChannel)で配信する
/// (design.md §2.3、requirements.md FR-2 FR-3)。
@HostApi()
abstract class OfflineSttHostApi {
  /// 対象ロケールのモデル状態を確認する(requirements.md FR-1)。
  ModelState checkModel(String locale);

  /// モデルダウンロードを開始する(requirements.md FR-2)。
  ///
  /// 進捗は `OfflineSttStreamEvents.downloadProgress()` のEventChannelで
  /// 配信される。本メソッド自体は開始要求のみを表し、値を返さない。
  void downloadModel(String locale);

  /// 音声ファイルの文字起こしを開始する(requirements.md FR-3)。
  ///
  /// 結果は `OfflineSttStreamEvents.segments()` のEventChannelで配信される。
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

/// EventChannel(design.md §2.3)。Android(Kotlin) / Darwin(Swift) 向け。
///
/// Pigeonの `@EventChannelApi` はDart / Kotlin / Swift の生成器のみに
/// 対応しており、C++には対応していない(本ファイル冒頭のコメント、および
/// 実際に `--cpp_header_out` 等を指定してPigeonを実行した結果で確認済み)。
@EventChannelApi()
abstract class OfflineSttStreamEvents {
  /// 文字起こし結果のストリーム(requirements.md FR-3)。
  TranscriptSegment segments();

  /// モデルダウンロード進捗のストリーム(requirements.md FR-2)。
  DownloadProgress downloadProgress();
}
