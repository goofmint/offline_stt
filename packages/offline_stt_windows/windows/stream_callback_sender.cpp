// stream_callback_sender.cpp
//
// 共有所有にした理由は stream_callback_sender.h のコメントを参照。
#include "stream_callback_sender.h"

#include <utility>

namespace offline_stt_windows {

namespace {

// Pigeon生成の FlutterApi 呼び出しは成功・失敗のコールバックを要求する。
// 配送結果に対してこちらから行える回復処理は無い(Dart側が既にストリームを
// 破棄している場合などにエラーになる)ため、いずれも何もしない。
// ここで既定値を作っているわけではないので、方針上のフォールバックではない。
std::function<void(void)> NoopSuccess() {
  return []() {};
}

std::function<void(const FlutterError&)> NoopError() {
  return [](const FlutterError&) {};
}

}  // namespace

std::shared_ptr<StreamCallbackSender> StreamCallbackSender::Create(
    std::unique_ptr<OfflineSttStreamCallbackApi> api,
    std::shared_ptr<PlatformThreadDispatcher> dispatcher) {
  // コンストラクタが private のため `make_shared` は使えない。
  return std::shared_ptr<StreamCallbackSender>(
      new StreamCallbackSender(std::move(api), std::move(dispatcher)));
}

StreamCallbackSender::StreamCallbackSender(
    std::unique_ptr<OfflineSttStreamCallbackApi> api,
    std::shared_ptr<PlatformThreadDispatcher> dispatcher)
    : api_(std::move(api)), dispatcher_(std::move(dispatcher)) {}

void StreamCallbackSender::Shutdown() {
  std::lock_guard<std::mutex> lock(mutex_);
  shut_down_ = true;
}

bool StreamCallbackSender::IsShutDown() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return shut_down_;
}

void StreamCallbackSender::Dispatch(std::function<void()> task) {
  auto self = shared_from_this();
  std::shared_ptr<PlatformThreadDispatcher> dispatcher;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (shut_down_) return;
    dispatcher = dispatcher_;
  }
  // `self` を捕捉することで、タスクがキューに残っている間は `api_` も
  // `dispatcher_` も解放されない。実行はプラットフォームスレッドで行われ、
  // `Shutdown()` も同じスレッドから呼ばれる契約なので、下の判定と
  // `Shutdown()` が交錯することはない(判定後に `shut_down_` が立って
  // そのまま送ってしまう、という競合が起きない)。
  dispatcher->Post([self, task = std::move(task)]() {
    if (self->IsShutDown()) return;
    task();
  });
}

void StreamCallbackSender::SendSegment(const std::string& text, bool is_final) {
  Dispatch([self = shared_from_this(), text, is_final]() {
    self->api_->OnSegment(TranscriptSegment(text, is_final), NoopSuccess(),
                          NoopError());
  });
}

void StreamCallbackSender::SendDownloadProgress(std::optional<double> fraction,
                                                bool completed) {
  Dispatch([self = shared_from_this(), fraction, completed]() {
    DownloadProgress progress(completed);
    if (fraction.has_value()) {
      progress.set_fraction(*fraction);
    }
    self->api_->OnDownloadProgress(progress, NoopSuccess(), NoopError());
  });
}

void StreamCallbackSender::SendError(const TranscribeError& error) {
  Dispatch([self = shared_from_this(), error]() {
    if (error.message.empty()) {
      self->api_->OnStreamError(error.code, nullptr, NoopSuccess(),
                                NoopError());
    } else {
      self->api_->OnStreamError(error.code, &error.message, NoopSuccess(),
                                NoopError());
    }
  });
}

void StreamCallbackSender::SendDone() {
  Dispatch([self = shared_from_this()]() {
    self->api_->OnStreamDone(NoopSuccess(), NoopError());
  });
}

}  // namespace offline_stt_windows
