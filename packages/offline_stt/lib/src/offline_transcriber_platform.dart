import 'download_progress.dart';
import 'model_state.dart';
import 'transcribe_request.dart';
import 'transcript_segment.dart';

/// `offline_stt` の内部プラットフォーム抽象(design.md §2.1)。
///
/// 各プラットフォーム実装(`src/android/OfflineSttAndroid` /
/// `src/darwin/OfflineSttDarwin` / `src/web/OfflineSttWeb`)はこのクラスを
/// 継承する。どの実装を使うかは `src/backend.dart` が決める。非Webでは
/// `src/backend_io.dart` が実行時の `Platform` 判定で、Webでは
/// `dart.library.js_interop` による条件付きexportで選択する。
///
/// **これは公開APIではない。** 利用者向けの入口は `OfflineTranscriber`
/// 1クラスである(requirements.md §6)。単一パッケージ構成であり外部の
/// 実装パッケージが登録することはないため、旧 federated plugin 構成が
/// 持っていた `instance` の登録機構(`plugin_platform_interface` による
/// token検証)は持たない。
///
/// design.md §2.1 の契約をそのまま実装したものであり、この範囲を超えて
/// 独自にメソッド・型を追加してはならない。
abstract class OfflineTranscriberPlatform {
  /// 対象ロケールのモデル状態を確認する(requirements.md FR-1)。
  Future<ModelState> checkModel(String locale);

  /// 対象ロケールのモデルダウンロードをトリガーし、進捗をStreamで返す
  /// (requirements.md FR-2)。
  ///
  /// ダウンロードはユーザー同意後に呼び出される前提であり、同意UIは
  /// ライブラリ利用者(アプリ側)の責務である。
  Stream<DownloadProgress> downloadModel(String locale);

  /// 音声ファイルを文字起こしし、結果をStreamで返す(requirements.md FR-3)。
  ///
  /// 状態遷移とセッション排他の規則(design.md §3):
  /// - `checkModel()` が `ModelState.available` 以外を返す状態でこの
  ///   メソッドを呼び出した場合、実装は即座に `ModelUnavailableException`
  ///   相当のエラーをStreamエラーとして返さなければならない。内部で暗黙的に
  ///   モデルをダウンロードしてはならない
  /// - 同時セッションはv1では1本に制限する。既に1本のセッションが実行中の
  ///   状態で2本目の `transcribeFile()` が呼ばれた場合、実装は `StateError`
  ///   をStreamエラーとして送出しなければならない
  ///
  /// セッション排他ガードの実装は `TranscribeSessionGuard`
  /// (`lib/src/session_guard.dart`、Issue #23で実装)として共有層に用意
  /// されている。各ネイティブ実装はこれを `with` し、`guardSession()` へ
  /// ネイティブセッション開始処理を渡すことで上記の規則を満たせる。
  /// 「セッション開始」はこのメソッドの呼び出し時点ではなく、返り値の
  /// Streamが購読(listen)された時点とみなす(理由は `TranscribeSessionGuard`
  /// のドキュメントコメントを参照)。
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request);
}
