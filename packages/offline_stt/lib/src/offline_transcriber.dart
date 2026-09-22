import 'backend.dart';
import 'common.dart';

/// 利用者向けのファサード。
///
/// requirements.md §6 は「利用者は `offline_stt` にのみ依存する」と定めて
/// いる。本クラスはその契約を成立させるための唯一の入口であり、
/// プラットフォーム実装(design.md §2.1 の `OfflineTranscriberPlatform`)
/// へ委譲するだけの薄い層である。**独自のロジック・状態・既定値を
/// 持たない。** 状態遷移と
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
/// ## プラットフォーム実装の選択について
///
/// 実装は `src/backend.dart` が選ぶ。Web かどうかは
/// `dart.library.js_interop` による条件付きexportでコンパイル時に、
/// Android / iOS / macOS の区別は `src/backend_io.dart` が実行時に判定
/// する。サポート対象外のプラットフォームではフォールバック実装を持たず
/// [UnsupportedError] を送出する。「とりあえず動く」既定値は不具合の
/// 温床になるためである。
class OfflineTranscriber {
  /// ファサードを生成する。状態を持たないため `const` である。
  const OfflineTranscriber();

  /// このライブラリが使うプラットフォーム実装。
  ///
  /// 生成は1回だけである。ネイティブ実装はセッション排他
  /// (`TranscribeSessionGuard`、design.md §3)の状態をインスタンスに
  /// 持つため、呼び出しごとに作り直すと「同時セッションは1本」の制約が
  /// 成立しなくなる。
  static final OfflineTranscriberPlatform _platform = createBackend();

  /// 対象ロケールのモデル状態を確認する(requirements.md FR-1)。
  ///
  /// 戻り値の4値の意味と、プラットフォームごとの写像・既知の制約は
  /// `lib/src/android/` / `lib/src/darwin/` / `lib/src/web/` の
  /// `model_state_mapping.dart` とパッケージ README を参照すること。
  Future<ModelState> checkModel(String locale) => _platform.checkModel(locale);

  /// 対象ロケールのモデルダウンロードをトリガーし、進捗を返す
  /// (requirements.md FR-2)。
  ///
  /// **同意UIはアプリ側の責務である。** 本メソッドは同意が済んでいる前提で
  /// 呼ばれる。`checkModel()` が `downloadable` 以外を返す状態で呼ばれた
  /// 場合、実装は状態を変化させず、何も emit せずに完了する Stream を返す
  /// (design.md §3 細則3)。
  ///
  /// [DownloadProgress.fraction] は `null` のことがある。Web は進捗の
  /// 粒度が得られないため常に不定進捗である。
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
