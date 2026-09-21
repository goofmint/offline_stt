// Copyright (c) MOONGIFT
//
// offline_stt の Android(Kotlin) / Darwin(Swift) 向け Pigeon スキーマ。
//
// 対応: design.md §2.2(データ型)/ §2.3(ブリッジ方式)、requirements.md FR-1
// FR-2 FR-3 FR-6、GitHub Issue #24。
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
  ///
  /// ## `@async` を付与する理由
  /// Darwin実装は `AssetInventory.status(forModules:)` /
  /// `SpeechTranscriber.supportedLocale(equivalentTo:)` という
  /// Swift ConcurrencyのasyncAPIを呼ばなければ戻り値の `ModelState` を
  /// 確定できない(`ModelAvailability.swift` 参照)。`@async` を付けない
  /// 場合、Pigeonが生成するSwiftプロトコルは同期シグネチャ
  /// (`throws -> ModelState`)になり、非同期APIの結果を得るには
  /// `DispatchSemaphore` 等でFlutterのプラットフォームスレッドを
  /// ブロックする回避策が必要になってしまう(ANR・デッドロックの危険が
  /// あり不可)。`@async` を付けることでPigeonは `completion:` クロージャ
  /// 形式の非同期シグネチャを生成し、スレッドをブロックせずに
  /// `async`/`await` へ素直に橋渡しできる。
  @async
  ModelState checkModel(String locale);

  /// モデルダウンロードを開始する(requirements.md FR-2)。
  ///
  /// 進捗は `OfflineSttStreamEvents.downloadProgress()` のEventChannelで
  /// 配信される。本メソッド自体は開始要求のみを表し、値を返さない。
  ///
  /// ## `@async` を付けない理由
  /// このメソッドは「開始要求のみ」を表す契約であり、実装は非同期APIの
  /// 完了を待たずに `Task` を起動して直ちに制御を返せる(Swift実装では
  /// `Task.cancel()` と新規 `Task { ... }` の生成のみを行い、いずれも
  /// 同期処理である。`OfflineSttApiImpl.downloadModel` 参照)。非同期APIの
  /// 実行結果自体は `downloadProgress` のEventChannelで別途配信されるため、
  /// 本メソッドの戻り値(`void`)を得るために非同期処理の完了を待つ必要が
  /// ない。
  void downloadModel(String locale);

  /// 音声ファイルの文字起こしを開始する(requirements.md FR-3)。
  ///
  /// 結果は `OfflineSttStreamEvents.segments()` のEventChannelで配信される。
  /// 本メソッド自体は開始要求のみを表し、値を返さない。
  ///
  /// design.md §3 のとおり、`checkModel()` が `ModelState.available` 以外
  /// を返す状態でこのメソッドが呼ばれた場合、ネイティブ側は即座にエラーを
  /// 返さなければならない(内部で暗黙的にダウンロードを開始してはならない)。
  ///
  /// ## `@async` を付けない理由
  /// `downloadModel` と同様に「開始要求のみ」の契約であり、`Task` を
  /// 起動して直ちに制御を返せる同期的な実装で足りる
  /// (`OfflineSttApiImpl.transcribeFile` 参照)。
  void transcribeFile(TranscribeRequest request);

  /// 実行中のダウンロード、または文字起こしセッションをキャンセルする
  /// (requirements.md FR-3)。
  ///
  /// design.md §3 のとおり同時セッションはv1では1本に制限されるため、
  /// キャンセル対象を明示するパラメータは持たない(実行中の1本のみが
  /// 対象になる)。
  ///
  /// ## `@async` を付けない理由
  /// `Task.cancel()` の呼び出しのみを行う完全に同期的な処理であり、
  /// 非同期APIを一切呼ばない(`OfflineSttApiImpl.cancel` 参照)。
  void cancel();
}

/// EventChannel(design.md §2.3)。Android(Kotlin) / Darwin(Swift) 向け。
@EventChannelApi()
abstract class OfflineSttStreamEvents {
  /// 文字起こし結果のストリーム(requirements.md FR-3)。
  TranscriptSegment segments();

  /// モデルダウンロード進捗のストリーム(requirements.md FR-2)。
  DownloadProgress downloadProgress();
}
