// model_acquisition.cpp
//
// 進捗を常に不定進捗として扱う理由は model_acquisition.h のコメントを参照。
#include "model_acquisition.h"

#include <mutex>
#include <utility>

#include "winrt_includes.h"

namespace offline_stt_windows {

namespace {

using EnsureOperation =
    wf::IAsyncOperationWithProgress<wai::AIFeatureReadyResult,
                                    wais::SpeechRecognitionModelProgress>;

}  // namespace

struct ModelAcquisition::State {
  std::mutex mutex;
  EnsureOperation operation{nullptr};
  bool completed = false;
  bool cancel_requested = false;
  std::function<void(std::optional<TranscribeError>)> on_complete;

  // `on_complete` は必ず1回だけ呼ぶ(ストリームのエラーが二重に流れるのを
  // 防ぐため)。
  void CompleteOnce(std::optional<TranscribeError> error) {
    std::function<void(std::optional<TranscribeError>)> callback;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (completed) return;
      completed = true;
      callback = std::move(on_complete);
      on_complete = nullptr;
      operation = nullptr;
    }
    if (callback) callback(std::move(error));
  }
};

ModelAcquisition::ModelAcquisition() : state_(std::make_shared<State>()) {}

ModelAcquisition::~ModelAcquisition() = default;

void ModelAcquisition::Start(
    std::function<void()> on_progress,
    std::function<void(std::optional<TranscribeError>)> on_complete) {
  auto state = state_;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->completed = false;
    state->cancel_requested = false;
    state->on_complete = std::move(on_complete);
  }

  EnsureOperation operation{nullptr};
  try {
    operation = wais::SpeechRecognitionModel::EnsureReadyAsync();
  } catch (const winrt::hresult_error& ex) {
    state->CompleteOnce(ClassifyHResult(ex.code(), "EnsureReadyAsync"));
    return;
  }

  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->operation = operation;
  }

  // Progress ハンドラは Completed より先に登録する(登録前に届いた進捗は
  // 取りこぼすため)。値は使わない ―― 理由は model_acquisition.h。
  operation.Progress(
      [on_progress](auto const&, wais::SpeechRecognitionModelProgress const&) {
        if (on_progress) on_progress();
      });

  operation.Completed([state](EnsureOperation const& sender,
                              wf::AsyncStatus status) {
    if (status == wf::AsyncStatus::Canceled) {
      TranscribeError error;
      error.code = TranscribeErrorCode::kCancelled;
      error.message = "";
      state->CompleteOnce(error);
      return;
    }
    if (status == wf::AsyncStatus::Error) {
      state->CompleteOnce(
          ClassifyHResult(sender.ErrorCode(), "EnsureReadyAsync"));
      return;
    }

    try {
      const wai::AIFeatureReadyResult result = sender.GetResults();
      if (result.Status() != wai::AIFeatureReadyResultState::Success) {
        // design.md §5 Windows列: ModelUnavailable <- EnsureReadyAsync の失敗。
        TranscribeError error;
        error.code = TranscribeErrorCode::kModelUnavailable;
        error.message = "EnsureReadyAsync が失敗した: " +
                        winrt::to_string(result.ErrorDisplayText());
        state->CompleteOnce(error);
        return;
      }
      state->CompleteOnce(std::nullopt);
    } catch (const winrt::hresult_error& ex) {
      state->CompleteOnce(
          ClassifyHResult(ex.code(), "EnsureReadyAsync(GetResults)"));
    }
  });
}

void ModelAcquisition::Cancel() {
  auto state = state_;
  EnsureOperation operation{nullptr};
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->completed) return;
    state->cancel_requested = true;
    operation = state->operation;
  }
  if (operation) {
    try {
      // `Cancel()` は IAsyncInfo の標準メンバー。キャンセルが受理されると
      // 上の Completed ハンドラが `AsyncStatus::Canceled` で呼ばれる。
      operation.Cancel();
    } catch (const winrt::hresult_error&) {
      // 既に完了している操作の `Cancel()` は失敗しうる
      // (`recognition_session.cpp` の `Cancel()` と同じ扱い)。
      //
      // ここを握り潰すことには、もう1つ積極的な理由がある。Issue #59 以降、
      // この経路はプラグインのデストラクタからも呼ばれる
      // (`OfflineSttApiImpl::Shutdown()` → `SpeechBackend::Cancel()`)。
      // デストラクタから例外を投げると `std::terminate` になるため、
      // 外へ漏らしてはならない。`cancel_requested` は立っているので、
      // 完了ハンドラ側の扱いは変わらない。
    }
  }
}

}  // namespace offline_stt_windows
