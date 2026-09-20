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
      std::unique_ptr<PlatformThreadDispatcher> dispatcher,
      std::unique_ptr<OfflineSttApiImpl> api)
      : dispatcher_(std::move(dispatcher)), api_(std::move(api)) {}

  ~OfflineSttWindowsPlugin() override = default;

  OfflineSttApiImpl* api() { return api_.get(); }

 private:
  // 破棄順の都合で `api_` より先に宣言する(`api_` が保持する
  // `StreamCallbackSender` が `dispatcher_` を参照するため、
  // `dispatcher_` のほうが後に破棄されるようメンバー順を逆にしている)。
  std::unique_ptr<PlatformThreadDispatcher> dispatcher_;
  std::unique_ptr<OfflineSttApiImpl> api_;
};

}  // namespace

void RegisterPlugin(flutter::PluginRegistrarWindows* registrar) {
  // **必ずプラットフォームスレッド上で構築すること**という
  // `PlatformThreadDispatcher` の前提は、プラグイン登録がプラットフォーム
  // スレッドで行われることによって満たされる。
  auto dispatcher = std::make_unique<PlatformThreadDispatcher>();
  if (!dispatcher->IsValid()) {
    // ネイティブ→Dartのコールバックを一切配送できない状態であり、
    // 登録しても「結果が永遠に来ない」プラグインになるだけである。
    // 黙って続けず、ここで登録を打ち切る(HostApiが未登録のままになるため、
    // Dart側の呼び出しは `channel-error` の `PlatformException` になり、
    // 利用者には「ネイティブが応答しない」ことが明示的に伝わる)。
    return;
  }

  auto sender = std::make_unique<StreamCallbackSender>(
      std::make_unique<OfflineSttStreamCallbackApi>(registrar->messenger()),
      dispatcher.get());

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
