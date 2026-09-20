// speech_backend_winrt.cpp
//
// `SpeechBackend` の本実装(Issue #52〜#56)。
// WinAppSDK のヘッダーが見つかったときだけコンパイルされる
// (`windows/CMakeLists.txt` 参照)。
//
// 各APIの詳細と判断の根拠は model_availability.h / model_acquisition.h /
// recognition_session.h のコメントに分けて書いてある。本ファイルは
// それらを束ねて `SpeechBackend` の契約に合わせるだけの薄い層である。
#include <memory>
#include <utility>

#include "model_acquisition.h"
#include "model_availability.h"
#include "recognition_session.h"
#include "speech_backend.h"

namespace offline_stt_windows {

namespace {

class WinRtSpeechBackend : public SpeechBackend {
 public:
  ModelStateResult QueryModelState() override {
    // 呼び出し元は `OfflineSttApiImpl::CheckModel`、すなわち Flutter の
    // プラットフォームスレッドである。C++/WinRT の型を使うにはそのスレッドで
    // COM が初期化されている必要があるが、Flutter の Windows ランナー
    // テンプレート(`runner/main.cpp`)は起動時に
    // `::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)` を呼んでおり、
    // プラットフォームスレッドは STA として初期化済みである。
    // `GetReadyState()` は同期APIでブロックしないため、STA から呼んでも
    // 問題にならない。
    //
    // **未検証**: 上記はFlutterのテンプレートを読んだうえでの理解であり、
    // 実機で確認していない(Issue #58)。もしアプリ側がランナーを改変して
    // `CoInitializeEx` を外していると、ここで例外になる。その場合は
    // `ClassifyHResult` 経由で `platformError` としてそのまま利用者へ届く
    // (黙って別の値を返すことはしない)。
    return QueryModelReadyState();
  }

  void StartEnsureReady(
      std::function<void()> on_progress,
      std::function<void(std::optional<TranscribeError>)> on_complete)
      override {
    acquisition_ = std::make_unique<ModelAcquisition>();
    acquisition_->Start(std::move(on_progress), std::move(on_complete));
  }

  void StartRecognizeFile(
      std::string file_path_utf8,
      std::function<void(std::string, std::optional<TranscribeError>)>
          on_complete) override {
    session_ = std::make_unique<RecognitionSession>();
    session_->Start(std::move(file_path_utf8), std::move(on_complete));
  }

  void Cancel() override {
    // design.md §3 のとおり同時に走るのは1本だけだが、どちらが走っている
    // かを呼び出し側が指定しない契約
    // (`pigeons/offline_stt_windows.dart` の `cancel`)なので両方に投げる。
    // どちらも実行中でなければ何もしない(冪等)。
    if (acquisition_) acquisition_->Cancel();
    if (session_) session_->Cancel();
  }

 private:
  std::unique_ptr<ModelAcquisition> acquisition_;
  std::unique_ptr<RecognitionSession> session_;
};

}  // namespace

std::unique_ptr<SpeechBackend> CreateSpeechBackend() {
  return std::make_unique<WinRtSpeechBackend>();
}

}  // namespace offline_stt_windows
