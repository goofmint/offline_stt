import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'download_progress.dart';
import 'model_state.dart';
import 'transcribe_request.dart';
import 'transcript_segment.dart';

/// `offline_stt` の共通プラットフォームインターフェース(design.md §2.1)。
///
/// 各プラットフォーム実装パッケージ(offline_stt_android / offline_stt_darwin
/// / offline_stt_windows / offline_stt_web)はこのクラスを継承し、
/// [OfflineTranscriberPlatform.instance] を自身のインスタンスへ差し替える
/// ことで登録する。`PlatformInterface`(plugin_platform_interface)による
/// token検証を伴う標準構成を採用しており、`extends` 以外(`implements` /
/// `with` によるモック化)での登録は [PlatformInterface.verify] が
/// [AssertionError] を送出して拒否する。
///
/// design.md §2.1 の契約をそのまま実装したものであり、本パッケージの範囲を
/// 超えて独自にメソッド・型を追加してはならない。
abstract class OfflineTranscriberPlatform extends PlatformInterface {
  /// token検証を伴うコンストラクタ。サブクラスは `super()` を呼ぶだけで
  /// 正しいtokenが設定される。
  OfflineTranscriberPlatform() : super(token: _token);

  static final Object _token = Object();

  static OfflineTranscriberPlatform? _instance;

  /// 現在登録されているプラットフォーム実装を返す。
  ///
  /// まだ実装パッケージが [instance] をsetしていない場合は [StateError] を
  /// 送出する。本パッケージはフォールバック実装を持たない(フォールバック
  /// 処理は方針として禁止されている)。
  static OfflineTranscriberPlatform get instance {
    final current = _instance;
    if (current == null) {
      throw StateError(
        'OfflineTranscriberPlatform.instance が未設定である。'
        'offline_stt_android / offline_stt_darwin / offline_stt_windows / '
        'offline_stt_web のいずれかのプラットフォーム実装パッケージが '
        'instance を設定する必要がある。',
      );
    }
    return current;
  }

  /// プラットフォーム実装を登録する。
  ///
  /// [PlatformInterface.verify] によるtoken検証を通過しないインスタンス
  /// (`extends OfflineTranscriberPlatform` によらないモック等)を渡すと
  /// [AssertionError] が送出される。
  static set instance(OfflineTranscriberPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

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
  /// セッション排他ガードの実装は本パッケージの `TranscribeSessionGuard`
  /// (`lib/src/session_guard.dart`、Issue #23で実装)として共有層に用意
  /// されている。各ネイティブ実装はこれを `with` し、`guardSession()` へ
  /// ネイティブセッション開始処理を渡すことで上記の規則を満たせる。
  /// 「セッション開始」はこのメソッドの呼び出し時点ではなく、返り値の
  /// Streamが購読(listen)された時点とみなす(理由は `TranscribeSessionGuard`
  /// のドキュメントコメントを参照)。
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request);
}
