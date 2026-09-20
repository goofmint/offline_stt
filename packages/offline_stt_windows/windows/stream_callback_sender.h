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
//
// =========================================================================
// 寿命 —— なぜ `shared_ptr` 前提にしたのか(Issue #59 / CodeRabbit 指摘対応)
// =========================================================================
// `Send*()` は WinRT のワーカースレッドから呼ばれる。以前の実装は
// `OfflineSttApiImpl` が生の `this` をコールバックへ捕捉し、
// `StreamCallbackSender` を素のポインタで参照していたため、
// 「プラグイン破棄 → その後に非同期処理が完了 → 解放済みの
// `sender_` / `dispatcher_` を触る」という use-after-free が成立していた。
// 認識処理のワーカースレッドは `detach()` されており、プラグインの破棄を
// 待たないので、この順序は実際に起こりうる。
//
// 対処として、コールバック経路に出てくるオブジェクトはすべて共有所有に
// する。`StreamCallbackSender` は必ず `shared_ptr` で保持し、
// `PlatformThreadDispatcher` も `shared_ptr` で握る。投函するタスクは自分
// 自身の `shared_ptr` を捕捉するので、タスクが生きている限り配送先は生きて
// いる。
//
// 生きてはいるが「送ってはいけない」状態を表すのが `Shutdown()` である。
// プラグインの破棄時にプラットフォームスレッドから呼ぶと、以後の `Send*()`
// と投函済みタスクはすべて無視される。`BinaryMessenger` はプラグイン破棄後
// に触れてはならないため、「生かして送る」のではなく「生かしたまま黙らせる」
// のが正しい。
//
// **未検証**: Windows 実機が無く、コンパイルすら通していない(CI は
// WinAppSDK ヘッダーが無いため WinRT 経路をビルドしない。
// `windows/CMakeLists.txt` 冒頭参照)。Issue #58 で確認すること。
#ifndef OFFLINE_STT_WINDOWS_STREAM_CALLBACK_SENDER_H_
#define OFFLINE_STT_WINDOWS_STREAM_CALLBACK_SENDER_H_

#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>

#include "pigeon.g.h"
#include "platform_thread_dispatcher.h"
#include "windows_transcribe_error.h"

namespace offline_stt_windows {

class StreamCallbackSender
    : public std::enable_shared_from_this<StreamCallbackSender> {
 public:
  // `shared_from_this()` を使うため、必ずこのファクトリ経由で生成する
  // (コンストラクタは private)。
  static std::shared_ptr<StreamCallbackSender> Create(
      std::unique_ptr<OfflineSttStreamCallbackApi> api,
      std::shared_ptr<PlatformThreadDispatcher> dispatcher);

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

  // **必ずプラットフォームスレッドから呼ぶこと**(プラグインのデストラクタ)。
  // 冪等。以後 `Send*()` は何も送らず、投函済みタスクも実行時に自分で降りる。
  void Shutdown();

 private:
  StreamCallbackSender(std::unique_ptr<OfflineSttStreamCallbackApi> api,
                       std::shared_ptr<PlatformThreadDispatcher> dispatcher);

  // `task` をプラットフォームスレッドへ投函する。自分自身の `shared_ptr` を
  // 捕捉するので、タスクの実行時に `this` が生きていることは保証される。
  void Dispatch(std::function<void()> task);

  bool IsShutDown() const;

  mutable std::mutex mutex_;
  bool shut_down_ = false;
  std::unique_ptr<OfflineSttStreamCallbackApi> api_;
  std::shared_ptr<PlatformThreadDispatcher> dispatcher_;
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_STREAM_CALLBACK_SENDER_H_
