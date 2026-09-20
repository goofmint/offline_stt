import 'dart:async';

import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
// ネイティブ実装が未実装のため(Issue #23の前提)、design.md §3の状態遷移を
// 検証するにはこのフェイク自身が共有ガードを経由する必要がある。本ファイル
// は offline_stt_platform_interface パッケージ自身の test/ 配下にあるため、
// これは「同一パッケージ内の実装詳細を参照する」通常のテストコードであり、
// 他パッケージからのsrc importではない。
import 'package:offline_stt_platform_interface/src/session_guard.dart';

/// design.md §3 が定めるセッション内部フェーズ
/// (idle → decoding → recognizing → done|cancelled|error)。
///
/// 公開契約である [TranscriptSegment] にはこの内部フェーズは含まれない
/// (design.md §2.2)。実際のネイティブ実装ではこのフェーズはネイティブ側
/// 内部にのみ存在し、Dart層(EventChannel/Stream)には個々のフェーズ自体は
/// 露出しない想定である。本フェイクはテストから状態遷移を直接検証できる
/// よう、観測用のプロパティとして公開している。
enum SessionPhase { idle, decoding, recognizing, done, cancelled, error }

/// [OfflineTranscriberPlatform] のテスト用フェイク実装(Issue #23)。
///
/// ## 配置判断
/// `test/` 配下に置く。design.md には公開の `testing` ライブラリについての
/// 記載が無く、design.md にない型を公開API(`lib/`)へ不用意に追加しない
/// という本Issueの制約に従い、公開APIには含めない。将来アプリ開発者向けの
/// テストユーティリティとして公開する必要が生じた場合は `lib/src/testing/`
/// へ移設する余地を残すが、現時点ではネイティブ実装が本パッケージ内から
/// 利用するのみであり、その必要性が無いため見送る。
///
/// [TranscribeSessionGuard] を `with` することで、本番のネイティブ実装と
/// 全く同じ排他ロジックを経由して状態遷移を検証できる。
class FakeOfflineTranscriberPlatform extends OfflineTranscriberPlatform
    with TranscribeSessionGuard {
  FakeOfflineTranscriberPlatform({
    ModelState initialState = ModelState.unavailable,
  }) : modelState = initialState;

  /// 現在のモデル状態(design.md §3)。テストから直接読み書きできるよう
  /// publicにしている。
  ModelState modelState;

  /// [transcribeFile] が呼ばれた回数。
  ///
  /// 「`checkModel()` が available 以外なら内部で暗黙にダウンロードしない」
  /// (design.md §3)ことを検証する際、`downloadModel` が意図せず呼ばれて
  /// いないことの傍証として使う。
  int transcribeFileCallCount = 0;

  /// 直近の文字起こしセッションの内部フェーズ。
  SessionPhase sessionPhase = SessionPhase.idle;

  StreamController<DownloadProgress>? _downloadController;

  @override
  Future<ModelState> checkModel(String locale) async => modelState;

  @override
  Stream<DownloadProgress> downloadModel(String locale) {
    // design.md §3 の状態遷移図は downloadModel() を downloadable からの
    // 遷移としてのみ定義している。unavailable(終端)を含むそれ以外の状態
    // からの呼び出しでは状態を一切変化させない空Streamを返す。これにより
    // 「unavailableは終端であり downloadModel() しても available に遷移
    // しない」ことをテストから確認できる。
    if (modelState != ModelState.downloadable) {
      return const Stream<DownloadProgress>.empty();
    }
    modelState = ModelState.downloading;
    final controller = StreamController<DownloadProgress>();
    _downloadController = controller;
    return controller.stream;
  }

  /// ダウンロード進捗をテストから注入する。
  void emitDownloadProgress(DownloadProgress progress) {
    _downloadController!.add(progress);
  }

  /// ダウンロードを成功として完了させる(downloading → available)。
  void completeDownloadSuccess() {
    modelState = ModelState.available;
    _downloadController!.add(DownloadProgress(fraction: 1.0, completed: true));
    unawaited(_downloadController!.close());
  }

  /// ダウンロードを失敗として終了させる(downloading → downloadable、
  /// エラー通知)。
  void failDownload(Object error) {
    modelState = ModelState.downloadable;
    _downloadController!.addError(error);
    unawaited(_downloadController!.close());
  }

  StreamController<TranscriptSegment>? _sessionController;

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) {
    transcribeFileCallCount++;
    // design.md §3: `checkModel()` が available 以外なら即座に
    // ModelUnavailableException をStreamエラーで返す。内部で暗黙的に
    // ダウンロードを開始してはならない。
    if (modelState != ModelState.available) {
      return Stream<TranscriptSegment>.error(const ModelUnavailableException());
    }
    return guardSession(() {
      sessionPhase = SessionPhase.decoding;
      final controller = StreamController<TranscriptSegment>(
        onCancel: () {
          // completeSession()/errorSession() による正常なclose後にも
          // StreamControllerの仕様上onCancelが呼ばれる場合があるため、
          // 既に終端フェーズ(done/error)に達している場合は上書きしない。
          if (sessionPhase != SessionPhase.done &&
              sessionPhase != SessionPhase.error) {
            sessionPhase = SessionPhase.cancelled;
          }
        },
      );
      _sessionController = controller;
      return controller.stream;
    });
  }

  /// decoding → recognizing の遷移をテストから発火させる。
  void startRecognizing() {
    sessionPhase = SessionPhase.recognizing;
  }

  /// 文字起こし結果のセグメントをテストから注入する。
  void emitSegment(TranscriptSegment segment) {
    _sessionController!.add(segment);
  }

  /// セッションを正常終了させる(→ done)。
  void completeSession() {
    sessionPhase = SessionPhase.done;
    unawaited(_sessionController!.close());
  }

  /// セッションをエラー終了させる(→ error)。
  void errorSession(Object error) {
    sessionPhase = SessionPhase.error;
    _sessionController!.addError(error);
    unawaited(_sessionController!.close());
  }

  /// エラーを通知するがStreamを閉じない(→ error)。
  ///
  /// `startSession()` が返すStreamは `onError` の後に必ず done になるとは
  /// 限らない。ガードがこの場合でも購読を打ち切ることを検証するために使う。
  void errorSessionWithoutClose(Object error) {
    sessionPhase = SessionPhase.error;
    _sessionController!.addError(error);
  }
}
