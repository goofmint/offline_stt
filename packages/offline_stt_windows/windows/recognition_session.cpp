// recognition_session.cpp
//
// 設計の根拠は recognition_session.h のコメントを参照。
#include "recognition_session.h"

#include <mutex>
#include <thread>
#include <utility>

#include "audio_conversion.h"
#include "string_conversion.h"
#include "winrt_includes.h"

namespace offline_stt_windows {

namespace {

using TryCreateOperation =
    wf::IAsyncOperationWithProgress<wais::SpeechRecognitionModelResult,
                                    wais::SpeechRecognitionModelProgress>;
using RecognizeOperation = wf::IAsyncOperation<winrt::hstring>;

TranscribeError Cancelled() {
  TranscribeError error;
  error.code = TranscribeErrorCode::kCancelled;
  error.message = "";
  return error;
}

}  // namespace

struct RecognitionSession::State {
  std::mutex mutex;
  bool cancel_requested = false;
  bool completed = false;
  // 実行中の WinRT 非同期操作。キャンセル時に `Cancel()` を呼ぶため保持する。
  wf::IAsyncInfo current_operation{nullptr};
  std::function<void(std::string, std::optional<TranscribeError>)> on_complete;

  bool IsCancelRequested() {
    std::lock_guard<std::mutex> lock(mutex);
    return cancel_requested;
  }

  void SetCurrentOperation(const wf::IAsyncInfo& operation) {
    std::lock_guard<std::mutex> lock(mutex);
    current_operation = operation;
  }

  void CompleteOnce(std::string transcript,
                    std::optional<TranscribeError> error) {
    std::function<void(std::string, std::optional<TranscribeError>)> callback;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (completed) return;
      completed = true;
      current_operation = nullptr;
      callback = std::move(on_complete);
      on_complete = nullptr;
    }
    if (callback) callback(std::move(transcript), std::move(error));
  }
};

RecognitionSession::RecognitionSession()
    : state_(std::make_shared<State>()) {}

RecognitionSession::~RecognitionSession() = default;

void RecognitionSession::Start(
    std::string file_path_utf8,
    std::function<void(std::string, std::optional<TranscribeError>)>
        on_complete) {
  auto state = state_;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->cancel_requested = false;
    state->completed = false;
    state->current_operation = nullptr;
    state->on_complete = std::move(on_complete);
  }

  std::thread worker([state, file_path_utf8]() {
    // C++/WinRT の型を使う前にアパートメントを初期化する。MTA にするのは、
    // 後段で `IAsyncOperation::get()` によるブロッキング待機を行うためで
    // ある(C++/WinRT のドキュメントは STA スレッドでの `get()` を禁じている)。
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    struct ApartmentGuard {
      ~ApartmentGuard() { winrt::uninit_apartment(); }
    } apartment_guard;

    // --- Issue #54: Media Foundation で wav へ変換 --------------------
    // 常に変換する。その判断の理由と、前提が未検証であることは
    // audio_conversion.h のコメントに記載している。
    if (state->IsCancelRequested()) {
      state->CompleteOnce("", Cancelled());
      return;
    }
    AudioConversionResult converted = ConvertToPcmWav(file_path_utf8);
    if (converted.error.has_value()) {
      state->CompleteOnce("", converted.error);
      return;
    }
    struct TempFileGuard {
      std::wstring path;
      ~TempFileGuard() { DeleteTemporaryFile(path); }
    } temp_file_guard{converted.output_path};

    if (state->IsCancelRequested()) {
      state->CompleteOnce("", Cancelled());
      return;
    }

    // --- Issue #55: TryCreateAsync ------------------------------------
    wais::SpeechRecognitionModel model{nullptr};
    try {
      TryCreateOperation create_operation =
          wais::SpeechRecognitionModel::TryCreateAsync();
      state->SetCurrentOperation(create_operation.as<wf::IAsyncInfo>());
      const wais::SpeechRecognitionModelResult create_result =
          create_operation.get();

      // 公式サンプル(speech-recognition.md)が示す失敗判定:
      //   if (speechModelResult.SpeechModel == null) throw ...
      if (create_result.SpeechModel() == nullptr) {
        TranscribeError error;
        error.code = TranscribeErrorCode::kModelUnavailable;
        error.message =
            "TryCreateAsync が SpeechModel を返さなかった"
            "(モデルが利用可能な状態ではない)。";
        state->CompleteOnce("", error);
        return;
      }
      model = create_result.SpeechModel();
    } catch (const winrt::hresult_error& ex) {
      if (state->IsCancelRequested()) {
        state->CompleteOnce("", Cancelled());
      } else {
        state->CompleteOnce("", ClassifyHResult(ex.code(), "TryCreateAsync"));
      }
      return;
    }

    if (state->IsCancelRequested()) {
      state->CompleteOnce("", Cancelled());
      return;
    }

    // --- Issue #55: BatchRecognition.RecognizeFromFile ------------------
    std::string transcript_utf8;
    try {
      wais::BatchRecognition batch_recognition(model);
      RecognizeOperation recognize_operation =
          batch_recognition.RecognizeFromFile(
              winrt::hstring(converted.output_path));
      state->SetCurrentOperation(recognize_operation.as<wf::IAsyncInfo>());
      const winrt::hstring transcript = recognize_operation.get();
      transcript_utf8 = winrt::to_string(transcript);
    } catch (const winrt::hresult_error& ex) {
      if (state->IsCancelRequested()) {
        state->CompleteOnce("", Cancelled());
      } else {
        state->CompleteOnce("",
                            ClassifyHResult(ex.code(), "RecognizeFromFile"));
      }
      return;
    }

    if (state->IsCancelRequested()) {
      state->CompleteOnce("", Cancelled());
      return;
    }

    // design.md §4.4: 最終テキスト1件を isFinal=true で emit する
    // (emit 自体は offline_stt_api_impl.cpp が行う)。
    state->CompleteOnce(std::move(transcript_utf8), std::nullopt);
  });
  // 呼び出し側(`OfflineSttHostApi.transcribeFile`)は「開始のみ」の契約
  // (`pigeons/offline_stt_windows.dart` 参照)なので、スレッドは join せず
  // detach する。完了は `on_complete` で通知される。
  worker.detach();
}

void RecognitionSession::Cancel() {
  auto state = state_;
  wf::IAsyncInfo operation{nullptr};
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->completed) return;
    state->cancel_requested = true;
    operation = state->current_operation;
  }
  if (operation) {
    try {
      operation.Cancel();
    } catch (const winrt::hresult_error&) {
      // 既に完了している操作の `Cancel()` は失敗しうる。フラグは立てて
      // あるので、後続のチェックポイントでキャンセルとして扱われる。
    }
  }
  // Media Foundation の変換中(WinRT 非同期がまだ無い段階)は、変換関数を
  // 途中で止める手段が無い。変換完了直後のチェックポイントでキャンセルが
  // 反映される。**未検証**: 長時間音声での変換打ち切り遅延は実機で測ること
  // (Issue #58)。
}

}  // namespace offline_stt_windows
