// speech_backend_unavailable.cpp
//
// WinAppSDK の C++/WinRT プロジェクションヘッダーが見つからずにビルドされた
// ときにリンクされる `SpeechBackend` の実装(Issue #52)。
//
// ## これはフォールバックではない
// リポジトリの方針は「設定が取得できない場合は明確にエラーを出す。
// 『とりあえず動く』フォールバックは不具合の温床」と定める。本実装は
// まさにそれに従うもので、`unavailable` や空文字列のような「それらしく
// 動いてしまう値」は一切返さない。すべての呼び出しが
// `TranscribeErrorCode::kPlatformError` と、原因・対処法を書いたメッセージで
// 失敗する。
//
// ## いつこちらがリンクされるか
// `windows/CMakeLists.txt` がアプリの `.winapp/include`(winapp CLI が
// `winapp init` で展開する WinAppSDK ヘッダー)を見つけられなかったとき。
// CI(windows-2025)は winapp CLI を持たないため常にこちらになる。
// 詳細は同ファイル冒頭のコメントと packages/offline_stt_windows/README.md を
// 参照。
#include <memory>
#include <utility>

#include "speech_backend.h"

namespace offline_stt_windows {

namespace {

constexpr char kMessage[] =
    "offline_stt_windows: このプラグインは WinAppSDK "
    "(Microsoft.Windows.AI.Speech) のヘッダー無しでビルドされているため、"
    "音声認識を実行できない。アプリのルートで `winapp init` を実行して "
    "WinAppSDK ヘッダーを .winapp/include へ展開し、ビルドし直すこと。"
    "別の場所にヘッダーがある場合は CMake 変数 "
    "OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR で指定できる。"
    "手順は packages/offline_stt_windows/README.md を参照 "
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
