// speech_backend_unavailable.cpp
//
// `OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI` が OFF(既定)のときにリンクされる
// `SpeechBackend` の実装(Issue #52)。
//
// ## これはフォールバックではない
// リポジトリの方針は「設定が取得できない場合は明確にエラーを出す。
// 『とりあえず動く』フォールバックは不具合の温床」と定める。本実装は
// まさにそれに従うもので、`unavailable` や空文字列のような「それらしく
// 動いてしまう値」は一切返さない。すべての呼び出しが
// `TranscribeErrorCode::kPlatformError` と、原因・対処法を書いたメッセージで
// 失敗する。
//
// ## なぜ OFF が既定なのか
// WinAppSDK の C++/WinRT プロジェクションヘッダーを Flutter の CMake ビルドへ
// 取り込む配線は、Windows 実機が無いため一度も検証できていない
// (`windows/CMakeLists.txt` の冒頭コメントに詳述)。検証できていない
// NuGet 復元処理を既定で有効にすると、プラグインを追加しただけで Windows の
// ビルドが壊れる。Issue #58 の実機検証で配線を確定させてから ON を既定に
// 切り替える。
#include <memory>
#include <utility>

#include "speech_backend.h"

namespace offline_stt_windows {

namespace {

constexpr char kMessage[] =
    "offline_stt_windows: このプラグインは WinAppSDK "
    "(Microsoft.Windows.AI.Speech) 無しでビルドされているため、音声認識を "
    "実行できない。windows/CMakeLists.txt の "
    "OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI を ON にし、"
    "OFFLINE_STT_WINDOWS_APP_SDK_VERSION に Speech Recognition API を含む "
    "Windows App SDK のバージョンを指定してビルドし直すこと "
    "(design.md §4.4 / requirements.md NFR-4 / Issue #58)。";

TranscribeError BuildError() {
  TranscribeError error;
  error.code = TranscribeErrorCode::kPlatformError;
  error.message = kMessage;
  return error;
}

class UnavailableSpeechBackend : public SpeechBackend {
 public:
  ModelStateResult QueryModelState() override {
    ModelStateResult result;
    // ここで `ModelState::kUnavailable` を返さないのが要点である。
    // 「端末が非対応」なのではなく「ビルド構成が不足している」のであり、
    // 4値のどれを返しても利用者を誤らせる。エラーとして返す。
    result.error = BuildError();
    return result;
  }

  void StartEnsureReady(
      std::function<void()> on_progress,
      std::function<void(std::optional<TranscribeError>)> on_complete)
      override {
    (void)on_progress;
    if (on_complete) on_complete(BuildError());
  }

  void StartRecognizeFile(
      std::string file_path_utf8,
      std::function<void(std::string, std::optional<TranscribeError>)>
          on_complete) override {
    (void)file_path_utf8;
    if (on_complete) on_complete("", BuildError());
  }

  void Cancel() override {
    // 実行中の操作が存在しないため何もしない。
  }
};

}  // namespace

std::unique_ptr<SpeechBackend> CreateSpeechBackend() {
  return std::make_unique<UnavailableSpeechBackend>();
}

}  // namespace offline_stt_windows
