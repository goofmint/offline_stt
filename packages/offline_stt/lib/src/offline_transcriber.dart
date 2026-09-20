import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// 利用者向けのファサード。
///
/// requirements.md §6 は「利用者は `offline_stt` にのみ依存する」と定めて
/// いる。本クラスはその契約を成立させるための唯一の入口であり、
/// `OfflineTranscriberPlatform.instance`(design.md §2.1)へ委譲するだけの
/// 薄い層である。**独自のロジック・状態・既定値を持たない。** 状態遷移と
/// セッション排他(design.md §3)は各プラットフォーム実装と
/// `TranscribeSessionGuard` が担う。
///
/// ## 使い方
///
/// ```dart
/// const transcriber = OfflineTranscriber();
///
/// // 1. モデルの状態を確認する。
/// final state = await transcriber.checkModel('ja-JP');
///
/// // 2. downloadable なら、アプリ側で同意を取ってからダウンロードする。
/// //    ライブラリは同意UIを出さない(requirements.md FR-2)。
/// if (state == ModelState.downloadable) {
///   await for (final progress in transcriber.downloadModel('ja-JP')) {
///     // progress.fraction は null(不定進捗)のことがある。
///   }
/// }
///
/// // 3. available になってから文字起こしする。
/// await for (final segment in transcriber.transcribeFile(
///   TranscribeRequest(path: path, locale: 'ja-JP'),
/// )) {
///   if (segment.isFinal) {
///     // 確定テキスト
///   }
/// }
/// ```
///
/// ## プラットフォーム実装の登録について
///
/// 各メソッドは呼び出し時に `OfflineTranscriberPlatform.instance` を参照する。
/// 実装パッケージが登録される前に呼ぶと [StateError] が送出される。
/// フォールバック実装は**意図的に持たない**。「とりあえず動く」既定値は
/// 不具合の温床になるためである。
class OfflineTranscriber {
  /// ファサードを生成する。状態を持たないため `const` である。
  const OfflineTranscriber();

  /// 現在登録されているプラットフォーム実装。
  ///
  /// 保持せず毎回参照するのは、Flutter のプラグイン登録がアプリ起動時に
  /// 行われるため、`const` コンストラクタで生成したインスタンスを登録前に
  /// 保持していても問題が起きないようにするためである。
  OfflineTranscriberPlatform get _platform =>
      OfflineTranscriberPlatform.instance;

  /// 対象ロケールのモデル状態を確認する(requirements.md FR-1)。
  ///
  /// 戻り値の4値の意味と、プラットフォームごとの写像・既知の制約は各実装
  /// パッケージの README を参照すること。特に Windows には `downloading` に
  /// 一意対応する状態が存在しない。
  Future<ModelState> checkModel(String locale) => _platform.checkModel(locale);

  /// 対象ロケールのモデルダウンロードをトリガーし、進捗を返す
  /// (requirements.md FR-2)。
  ///
  /// **同意UIはアプリ側の責務である。** 本メソッドは同意が済んでいる前提で
  /// 呼ばれる。`checkModel()` が `downloadable` 以外を返す状態で呼ばれた
  /// 場合、実装は状態を変化させず、何も emit せずに完了する Stream を返す
  /// (design.md §3 細則3)。
  ///
  /// [DownloadProgress.fraction] は `null` のことがある。Web と Windows は
  /// 進捗の粒度が得られないため常に不定進捗である。
  Stream<DownloadProgress> downloadModel(String locale) =>
      _platform.downloadModel(locale);

  /// 音声ファイルを文字起こしする(requirements.md FR-3)。
  ///
  /// 返す [Stream] は購読された時点でセッションを開始する(design.md §3
  /// 細則1)。以下はいずれも Stream エラーとして通知される:
  ///
  /// - モデルが `available` でない場合の [ModelUnavailableException]。
  ///   **内部で暗黙的にダウンロードはしない**(同意UXをアプリ側に強制する
  ///   ため)
  /// - 同時セッションは v1 では1本に制限しており、2本目の開始は [StateError]
  ///
  /// 購読を `cancel()` するとセッションも終了する。
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      _platform.transcribeFile(request);
}
