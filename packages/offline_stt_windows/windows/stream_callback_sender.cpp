// stream_callback_sender.cpp
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

StreamCallbackSender::StreamCallbackSender(
    std::unique_ptr<OfflineSttStreamCallbackApi> api,
    PlatformThreadDispatcher* dispatcher)
    : api_(std::move(api)), dispatcher_(dispatcher) {}

void StreamCallbackSender::SendSegment(const std::string& text, bool is_final) {
  dispatcher_->Post([this, text, is_final]() {
    api_->OnSegment(TranscriptSegment(text, is_final), NoopSuccess(),
                    NoopError());
  });
}

void StreamCallbackSender::SendDownloadProgress(std::optional<double> fraction,
                                                bool completed) {
  dispatcher_->Post([this, fraction, completed]() {
    DownloadProgress progress(completed);
    if (fraction.has_value()) {
      progress.set_fraction(*fraction);
    }
    api_->OnDownloadProgress(progress, NoopSuccess(), NoopError());
  });
}

void StreamCallbackSender::SendError(const TranscribeError& error) {
  dispatcher_->Post([this, error]() {
    if (error.message.empty()) {
      api_->OnStreamError(error.code, nullptr, NoopSuccess(), NoopError());
    } else {
      api_->OnStreamError(error.code, &error.message, NoopSuccess(),
                          NoopError());
    }
  });
}

void StreamCallbackSender::SendDone() {
  dispatcher_->Post(
      [this]() { api_->OnStreamDone(NoopSuccess(), NoopError()); });
}

}  // namespace offline_stt_windows
