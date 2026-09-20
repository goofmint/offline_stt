// stream_callback_sender.h
//
// Pigeon `@FlutterApi()` の `OfflineSttStreamCallbackApi` を包み、
// 必ずプラットフォームスレッドから呼ぶようにする薄いラッパー(Issue #52)。
// `offline_stt_darwin/darwin/Classes/EventChannelWrappers.swift` と
// `offline_stt_android/.../EventChannelWrappers.kt` に対応するファイル。
//
// design.md §2.3 のとおり Android/Darwin は `@EventChannelApi` を使うが、
// PigeonのC++生成器はEventChannelに未対応であるため、Windowsは
// `onSegment` / `onDownloadProgress` / `onStreamError` / `onStreamDone` の
// 4コールバックで代替している(`pigeons/offline_stt_windows.dart` 冒頭
// コメント参照)。EventChannel と違い「ストリームの終了」は暗黙に
// 伝わらないので、**どの経路で終わる場合でも最後に `SendDone()` または
// `SendError()` + `SendDone()` を必ず呼ぶ**契約にしている。
#ifndef OFFLINE_STT_WINDOWS_STREAM_CALLBACK_SENDER_H_
#define OFFLINE_STT_WINDOWS_STREAM_CALLBACK_SENDER_H_

#include <memory>
#include <optional>
#include <string>

#include "pigeon.g.h"
#include "platform_thread_dispatcher.h"
#include "windows_transcribe_error.h"

namespace offline_stt_windows {

class StreamCallbackSender {
 public:
  StreamCallbackSender(std::unique_ptr<OfflineSttStreamCallbackApi> api,
                       PlatformThreadDispatcher* dispatcher);

  StreamCallbackSender(const StreamCallbackSender&) = delete;
  StreamCallbackSender& operator=(const StreamCallbackSender&) = delete;

  // requirements.md FR-3。design.md §4.4 のとおりWindowsのバッチ認識は
  // `is_final = true` の1件のみを送る。
  void SendSegment(const std::string& text, bool is_final);

  // requirements.md FR-2。`fraction` が `std::nullopt` のときは不定進捗。
  // Windowsが常に不定進捗である理由は `model_acquisition.h` を参照。
  void SendDownloadProgress(std::optional<double> fraction, bool completed);

  // requirements.md FR-6。
  void SendError(const TranscribeError& error);

  // ストリームの正常終了。
  void SendDone();

 private:
  std::unique_ptr<OfflineSttStreamCallbackApi> api_;
  PlatformThreadDispatcher* dispatcher_;
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_STREAM_CALLBACK_SENDER_H_
