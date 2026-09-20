// speech_backend.h
//
// `Microsoft.Windows.AI.Speech`(WinAppSDK / C++/WinRT)へのアクセスを、
// WinRTの型を一切露出しないインターフェイスの裏へ隔離する(Issue #52)。
//
// ## なぜインターフェイスで隔離するのか
// `windows/CMakeLists.txt` のコメントに詳しく書いたとおり、WinAppSDKの
// C++/WinRT プロジェクションヘッダー(`winrt/Microsoft.Windows.AI.Speech.h`
// 等)を Flutter の CMake ビルドへ取り込む配線は、本リポジトリでは
// **一度も検証できていない**(Windows実機が無い)。そのため
// WinAppSDK のヘッダーが無いビルドでも
// プラグイン全体がコンパイル・リンクできるよう、WinRT に触れるコードを
// 1ファイル(`speech_backend_winrt.cpp` とそこから呼ぶ3ファイル)に
// 閉じ込め、それ以外(Pigeonの受け口・スレッド調停・Media Foundation変換)
// は常にコンパイルされるようにしている。
//
// OFF のビルドでは `speech_backend_unavailable.cpp` の実装が入り、
// すべての呼び出しが「WinAppSDK無しでビルドされた」という明示的なエラーを
// 返す。既定値で取り繕うフォールバックではなく、原因がそのまま利用者へ
// 届く形にしてある。
#ifndef OFFLINE_STT_WINDOWS_SPEECH_BACKEND_H_
#define OFFLINE_STT_WINDOWS_SPEECH_BACKEND_H_

#include <functional>
#include <memory>
#include <optional>
#include <string>

#include "pigeon.g.h"
#include "windows_transcribe_error.h"

namespace offline_stt_windows {

// `QueryModelState()` の結果。成功なら `state`、失敗なら `error` に値が入る
// (両方が空、または両方に値が入ることは無い)。
struct ModelStateResult {
  std::optional<ModelState> state;
  std::optional<TranscribeError> error;
};

class SpeechBackend {
 public:
  virtual ~SpeechBackend() = default;

  // requirements.md FR-1。`SpeechRecognitionModel.GetReadyState()` 相当。
  // 同期(`GetReadyState` に Async 接尾辞が無いことをドキュメントで確認済み。
  // spikes/windows/src/Core/ModelReadiness.h 参照)。
  virtual ModelStateResult QueryModelState() = 0;

  // requirements.md FR-2。`SpeechRecognitionModel.EnsureReadyAsync()` 相当。
  // 即座に戻り、進捗・完了はコールバックで通知する。
  // **コールバックは任意のワーカースレッドから呼ばれる**ので、呼び出し側は
  // `StreamCallbackSender` 経由でプラットフォームスレッドへ戻すこと。
  //
  // `on_progress` は進捗イベント1件につき1回呼ばれる。進捗値を引数に
  // 取らないのは、Windowsでは常に不定進捗として扱うと決めたためである
  // (判断の根拠は `model_acquisition.h` 参照)。
  // `on_complete` は成功なら `std::nullopt`、失敗ならエラーを受け取る。
  virtual void StartEnsureReady(
      std::function<void()> on_progress,
      std::function<void(std::optional<TranscribeError>)> on_complete) = 0;

  // requirements.md FR-3 / FR-4。
  // Media Foundation での wav 変換 → `SpeechRecognitionModel.TryCreateAsync()`
  // → `BatchRecognition.RecognizeFromFile()` を通しで実行する。
  // 即座に戻り、完了はコールバックで通知する(ワーカースレッド)。
  // 成功時は認識結果(UTF-8)と `std::nullopt`、失敗時は空文字列とエラー。
  virtual void StartRecognizeFile(
      std::string file_path_utf8,
      std::function<void(std::string, std::optional<TranscribeError>)>
          on_complete) = 0;

  // requirements.md FR-3。実行中の `StartEnsureReady` /
  // `StartRecognizeFile` にキャンセルを要求する。
  // キャンセルされた操作の `on_complete` は
  // `TranscribeErrorCode::kCancelled` で呼ばれる。
  virtual void Cancel() = 0;
};

// ビルド構成に応じた実装を生成する(`speech_backend_winrt.cpp` または
// `speech_backend_unavailable.cpp` のどちらか一方だけがリンクされる)。
std::unique_ptr<SpeechBackend> CreateSpeechBackend();

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_SPEECH_BACKEND_H_
