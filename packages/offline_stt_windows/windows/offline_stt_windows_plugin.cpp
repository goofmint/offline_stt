// offline_stt_windows_plugin.cpp
//
// offline_stt の Windows ネイティブ側エントリポイント(Issue #52)。
// `offline_stt_darwin/darwin/Classes/OfflineSttDarwinPlugin.swift` および
// `offline_stt_android/.../OfflineSttAndroidPlugin.kt` に対応するファイル。
//
// Pigeon生成コード(`pigeons/offline_stt_windows.dart` から生成、Issue #24)の
// `OfflineSttHostApi`(MethodChannel)・`OfflineSttStreamCallbackApi`
// (FlutterApiコールバック、design.md §2.3)を、`OfflineSttApiImpl`
// (Windows AI Speech Recognition 連携の実装本体、design.md §4.4)と
// 結びつける。
#include "include/offline_stt_windows/offline_stt_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "offline_stt_api_impl.h"
#include "pigeon.g.h"
#include "platform_thread_dispatcher.h"
#include "speech_backend.h"
#include "stream_callback_sender.h"

namespace offline_stt_windows {

namespace {

// プラグインの生存期間(= エンジンの生存期間)にわたって保持する一式。
// Pigeon の `OfflineSttHostApi::SetUp()` は `api` を生ポインタで受け取り
// 所有権を持たないため、どこかで保持し続ける必要がある。
// `flutter::PluginRegistrarWindows::AddPlugin()` にこの保持を委ねる。
class OfflineSttWindowsPlugin : public flutter::Plugin {
 public:
  explicit OfflineSttWindowsPlugin(
      std::shared_ptr<PlatformThreadDispatcher> dispatcher,
      std::unique_ptr<OfflineSttApiImpl> api)
      : dispatcher_(std::move(dispatcher)), api_(std::move(api)) {}

  // Issue #59 / CodeRabbit 指摘「非同期処理の完了前にコールバック対象を
  // 破棄しないでください」への対処。
  //
  // デストラクタは Flutter のプラットフォームスレッドで走る
  // (`PluginRegistrarWindows` が保持しており、エンジン破棄時に解放される)。
  // 順序に意味があるので明示する:
  //   1. `api_->Shutdown()`
  //      Dart への配送を止め(`StreamCallbackSender::Shutdown()`)、
  //      実行中の `EnsureReadyAsync` / 認識セッションへキャンセルを要求する。
  //      **完了は待たない。** 待たない理由と、待ってもデッドロックはしない
  //      ことの確認は `offline_stt_api_impl.cpp` の `Shutdown()` の前に
  //      書いたコメントを参照。
  //   2. `dispatcher_->Shutdown()`
  //      メッセージ専用ウィンドウを破棄し、未実行タスクを捨てる。以後
  //      プラットフォームスレッドでタスクが走ることは無くなるため、破棄済み
  //      の `BinaryMessenger` を触る経路が閉じる。未実行タスクを捨てるのは
  //      「タスク→`StreamCallbackSender`→ディスパッチャ」の参照の循環を
  //      断つためでもある(`platform_thread_dispatcher.h` 参照)。
  //
  // この時点でまだ走っている非同期処理があっても、それが触るのは
  // `AsyncCallbackContext` が `shared_ptr` で生かしているオブジェクトだけ
  // なので、解放済みメモリには触れない。
  ~OfflineSttWindowsPlugin() override {
    api_->Shutdown();
    dispatcher_->Shutdown();
  }

  OfflineSttApiImpl* api() { return api_.get(); }

 private:
  // `dispatcher_` は `StreamCallbackSender` からも `shared_ptr` で握られる
  // ため、メンバーの破棄順に安全性は依存しない。それでも
  // 「`api_` が先に破棄される」という元の並びは維持しておく。
  std::shared_ptr<PlatformThreadDispatcher> dispatcher_;
  std::unique_ptr<OfflineSttApiImpl> api_;
};

}  // namespace

void RegisterPlugin(flutter::PluginRegistrarWindows* registrar) {
  // **必ずプラットフォームスレッド上で構築すること**という
  // `PlatformThreadDispatcher` の前提は、プラグイン登録がプラットフォーム
  // スレッドで行われることによって満たされる。
  auto dispatcher = std::make_shared<PlatformThreadDispatcher>();
  if (!dispatcher->IsValid()) {
    // ネイティブ→Dartのコールバックを一切配送できない状態であり、
    // 登録しても「結果が永遠に来ない」プラグインになるだけである。
    // 黙って続けず、ここで登録を打ち切る(HostApiが未登録のままになるため、
    // Dart側の呼び出しは `channel-error` の `PlatformException` になり、
    // 利用者には「ネイティブが応答しない」ことが明示的に伝わる)。
    return;
  }

  // `dispatcher` は `shared_ptr` で渡す。ワーカースレッドから投函された
  // タスクが、プラグイン破棄と競合して解放済みのディスパッチャを触ることが
  // 無いようにするため(Issue #59)。
  auto sender = StreamCallbackSender::Create(
      std::make_unique<OfflineSttStreamCallbackApi>(registrar->messenger()),
      dispatcher);

  auto api = std::make_unique<OfflineSttApiImpl>(CreateSpeechBackend(),
                                                 std::move(sender));

  auto plugin = std::make_unique<OfflineSttWindowsPlugin>(
      std::move(dispatcher), std::move(api));
  OfflineSttHostApi::SetUp(registrar->messenger(), plugin->api());
  registrar->AddPlugin(std::move(plugin));
}

}  // namespace offline_stt_windows

void OfflineSttWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  offline_stt_windows::RegisterPlugin(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
