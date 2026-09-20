// offline_stt_api_impl.cpp
#include "offline_stt_api_impl.h"

#include <utility>

namespace offline_stt_windows {

namespace {

FlutterError ToFlutterError(const TranscribeError& error) {
  return FlutterError(WireCode(error.code), error.message);
}

}  // namespace

OfflineSttApiImpl::OfflineSttApiImpl(
    std::unique_ptr<SpeechBackend> backend,
    std::unique_ptr<StreamCallbackSender> sender)
    : backend_(std::move(backend)), sender_(std::move(sender)) {}

// ---------------------------------------------------------------------------
// FR-1 モデル状態確認(Issue #53)
// ---------------------------------------------------------------------------

void OfflineSttApiImpl::CheckModel(
    const std::string& locale,
    std::function<void(ErrorOr<ModelState> reply)> result) {
  // design.md §4.4 / §8 未決事項2: `Microsoft.Windows.AI.Speech` には
  // ロケール・言語を指定するAPIが存在しないことがドキュメント調査で確定
  // している。したがって `locale` は状態判定に使えない。無視することが
  // 仕様であり、ここで既定ロケールを捏造するようなことはしない。
  // 「どの言語で認識されるか」はOS側の設定に依存する(READMEに明記する
  // のはIssue #57の担当範囲)。
  (void)locale;

  // `EnsureReadyAsync()` 実行中は `downloading` を返す(理由は
  // `offline_stt_api_impl.h` の `ensure_ready_in_flight_` のコメント参照)。
  // 先に判定するのは、ダウンロード中に `GetReadyState()` が返す値が
  // `NotReady` のままなのか、それとも別の値になるのかが未検証だからである。
  // 実行中であることはこのプラグイン自身が知っている確かな事実なので、
  // 未検証の推測より優先する。
  if (ensure_ready_in_flight_.load()) {
    result(ModelState::kDownloading);
    return;
  }

  ModelStateResult query = backend_->QueryModelState();
  if (query.error.has_value()) {
    result(ToFlutterError(*query.error));
    return;
  }
  if (!query.state.has_value()) {
    // `SpeechBackend` の契約違反。既定値で埋めず明確にエラーにする。
    result(FlutterError(
        WireCode(TranscribeErrorCode::kPlatformError),
        "offline_stt_windows: SpeechBackend::QueryModelState() が状態も"
        "エラーも返さなかった(実装の不具合)。"));
    return;
  }
  result(*query.state);
}

// ---------------------------------------------------------------------------
// FR-2 モデルダウンロード(Issue #53)
// ---------------------------------------------------------------------------

std::optional<FlutterError> OfflineSttApiImpl::DownloadModel(
    const std::string& locale) {
  (void)locale;  // 上記 CheckModel と同じ理由でロケールは使えない。

  if (operation_in_flight_.exchange(true)) {
    // ストリームはDart側で既に張られているため、同期エラーではなく
    // ストリームのエラーとして返す(design.md §3細則2と同じ流儀)。
    TranscribeError error;
    error.code = TranscribeErrorCode::kPlatformError;
    error.message =
        "offline_stt_windows: 既に別の操作(ダウンロードまたは文字起こし)が"
        "実行中である。design.md §3 のとおり同時実行は1本に制限される。";
    sender_->SendError(error);
    sender_->SendDone();
    return std::nullopt;
  }

  // design.md §3 細則3: `downloadable` 以外の状態で呼ばれた場合は、
  // 状態を一切変化させず、何も emit せずに完了するStreamを返す。
  ModelStateResult query = backend_->QueryModelState();
  if (query.error.has_value()) {
    sender_->SendError(*query.error);
    sender_->SendDone();
    operation_in_flight_.store(false);
    return std::nullopt;
  }
  if (query.state != ModelState::kDownloadable) {
    sender_->SendDone();
    operation_in_flight_.store(false);
    return std::nullopt;
  }

  ensure_ready_in_flight_.store(true);

  // FR-2: 開始した時点で1件目の進捗を送る。Windowsは常に不定進捗
  // (`fraction = std::nullopt`)である。理由は `model_acquisition.h` 参照。
  sender_->SendDownloadProgress(std::nullopt, false);

  backend_->StartEnsureReady(
      [this]() {
        // `SpeechRecognitionModelProgress` の値は使わず、進捗が動いたこと
        // だけを不定進捗として通知する(理由は `model_acquisition.h`)。
        sender_->SendDownloadProgress(std::nullopt, false);
      },
      [this](std::optional<TranscribeError> error) {
        ensure_ready_in_flight_.store(false);
        if (error.has_value()) {
          sender_->SendError(*error);
        } else {
          sender_->SendDownloadProgress(std::nullopt, true);
        }
        sender_->SendDone();
        operation_in_flight_.store(false);
      });

  return std::nullopt;
}

// ---------------------------------------------------------------------------
// FR-3 ファイル文字起こし(Issue #54 #55)
// ---------------------------------------------------------------------------

std::optional<FlutterError> OfflineSttApiImpl::TranscribeFile(
    const TranscribeRequest& request) {
  if (operation_in_flight_.exchange(true)) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kPlatformError;
    error.message =
        "offline_stt_windows: 既に別の操作(ダウンロードまたは文字起こし)が"
        "実行中である。design.md §3 のとおり同時実行は1本に制限される。";
    sender_->SendError(error);
    sender_->SendDone();
    return std::nullopt;
  }

  // design.md §3 / `pigeons/offline_stt_windows.dart` の `transcribeFile` の
  // docコメント: `checkModel()` が `available` 以外を返す状態で呼ばれた場合、
  // ネイティブ側は即座にエラーを返さなければならない(内部で暗黙的に
  // ダウンロードを開始してはならない)。Dart側
  // (`lib/src/recognition_session.dart`)にも同じガードがあり、二重チェックは
  // 意図的である(スキーマが「ネイティブ側は」と明記しているため)。
  if (ensure_ready_in_flight_.load()) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kModelUnavailable;
    error.message =
        "offline_stt_windows: モデルのダウンロード中は文字起こしを開始できない。";
    sender_->SendError(error);
    sender_->SendDone();
    operation_in_flight_.store(false);
    return std::nullopt;
  }
  ModelStateResult query = backend_->QueryModelState();
  if (query.error.has_value()) {
    sender_->SendError(*query.error);
    sender_->SendDone();
    operation_in_flight_.store(false);
    return std::nullopt;
  }
  if (query.state != ModelState::kAvailable) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kModelUnavailable;
    error.message =
        "offline_stt_windows: モデルが available ではない。"
        "downloadModel() でモデルを取得してから呼び出すこと"
        "(design.md §3。暗黙のダウンロードは行わない)。";
    sender_->SendError(error);
    sender_->SendDone();
    operation_in_flight_.store(false);
    return std::nullopt;
  }

  // design.md §2.2 / §7: `playbackRate` はWeb専用オプションであり、
  // Windows(BatchRecognition)はバッチ処理のため速度という概念が無い。
  // Windows向けPigeonスキーマの `TranscribeRequest` には
  // `path` / `locale` しか無いので、無視は自動的に満たされる。
  backend_->StartRecognizeFile(
      request.path(),
      [this](std::string transcript, std::optional<TranscribeError> error) {
        if (error.has_value()) {
          sender_->SendError(*error);
        } else {
          // design.md §4.4: Windowsバッチ認識は final 1件のみを emit する。
          sender_->SendSegment(transcript, true);
        }
        sender_->SendDone();
        operation_in_flight_.store(false);
      });

  return std::nullopt;
}

// ---------------------------------------------------------------------------
// FR-3 キャンセル(Issue #56)
// ---------------------------------------------------------------------------

std::optional<FlutterError> OfflineSttApiImpl::Cancel() {
  // 実行中でなければ何もしない(冪等)。実行中であれば、キャンセル後に
  // `on_complete` が `kCancelled` で呼ばれ、そこで `SendError` +
  // `SendDone` とフラグの解放が行われる。
  backend_->Cancel();
  return std::nullopt;
}

}  // namespace offline_stt_windows
