// offline_stt_api_impl.h
//
// `OfflineSttHostApi`(Pigeon生成、`pigeon.g.h`)の実装本体。
// `offline_stt_darwin/darwin/Classes/OfflineSttApiImpl.swift` および
// `offline_stt_android/.../OfflineSttApiImpl.kt` に対応するファイル。
// design.md §4.4、requirements.md FR-1〜FR-3 FR-6(Issue #52〜#56)。
//
// WinRT の型には一切触れず、`SpeechBackend` インターフェイス越しに
// Windows AI APIs を叩く(理由は `speech_backend.h` 参照)。
#ifndef OFFLINE_STT_WINDOWS_OFFLINE_STT_API_IMPL_H_
#define OFFLINE_STT_WINDOWS_OFFLINE_STT_API_IMPL_H_

#include <atomic>
#include <memory>
#include <optional>
#include <string>

#include "pigeon.g.h"
#include "speech_backend.h"
#include "stream_callback_sender.h"

namespace offline_stt_windows {

// 非同期コールバックが触れてよい状態だけを集めたオブジェクト。
//
// Issue #59 / CodeRabbit 指摘対応。以前は `StartEnsureReady()` /
// `StartRecognizeFile()` のコールバックが `OfflineSttApiImpl` の生の `this`
// を捕捉していた。認識処理のワーカースレッドは `detach()` されており
// (`recognition_session.cpp`)、プラグインの破棄を待たずに完了しうるため、
// 破棄済みの `sender_` / `dispatcher_` を触る use-after-free が成立していた。
//
// そこで「コールバックが触る状態」をこの構造体へ切り出し、
// `shared_ptr` でコールバックと寿命を共有する。ここには生ポインタが一切
// 無い(`sender` は `shared_ptr`)ので、プラグイン破棄後にコールバックが
// 走っても解放済みメモリには触れない。送信先が既に無効であることは
// `StreamCallbackSender::Shutdown()` が表し、`Send*()` は黙って降りる。
struct AsyncCallbackContext {
  std::shared_ptr<StreamCallbackSender> sender;

  // design.md §4.4 / requirements.md FR-1 の最大の課題への対処。
  //
  // `AIFeatureReadyState` の7値には `downloading` に一意対応する値が
  // **存在しない**ことがドキュメント調査で確定している
  // (spikes/windows/RESULTS.md)。そこで本実装は
  // 「このプラグインが `EnsureReadyAsync()` を実行している間だけ
  //   `checkModel()` は `downloading` を返す」
  // という補い方を採る。判断の詳細と限界は `model_availability.h` の
  // コメントに記載している。
  //
  // `DownloadModel`(プラットフォームスレッド)と `StartEnsureReady` の
  // 完了コールバック(ワーカースレッド)の双方から書かれるため atomic。
  std::atomic<bool> ensure_ready_in_flight{false};

  // 同時に1本しか動かさない(design.md §3)。ここが true の間に
  // `TranscribeFile` / `DownloadModel` が呼ばれることは、Dart側の
  // `TranscribeSessionGuard` と `WindowsStreamRouter` で既に防がれている
  // が、ネイティブ単体でも破綻しないよう二重に持つ。
  std::atomic<bool> operation_in_flight{false};
};

class OfflineSttApiImpl : public OfflineSttHostApi {
 public:
  OfflineSttApiImpl(std::unique_ptr<SpeechBackend> backend,
                    std::shared_ptr<StreamCallbackSender> sender);
  ~OfflineSttApiImpl() override = default;

  // requirements.md FR-1。
  void CheckModel(const std::string& locale,
                  std::function<void(ErrorOr<ModelState> reply)> result)
      override;

  // requirements.md FR-2。
  std::optional<FlutterError> DownloadModel(const std::string& locale) override;

  // requirements.md FR-3。
  std::optional<FlutterError> TranscribeFile(
      const TranscribeRequest& request) override;

  // requirements.md FR-3(キャンセル)。
  std::optional<FlutterError> Cancel() override;

  // プラグイン破棄の直前に、**プラットフォームスレッドから**呼ぶ。
  // Dartへの配送を止め、実行中の非同期処理へキャンセルを要求する。
  // 完了を待たない理由は `offline_stt_api_impl.cpp` の実装コメント参照。
  void Shutdown();

 private:
  std::unique_ptr<SpeechBackend> backend_;

  // コールバックと共有する状態。`backend_` より後に宣言し、`backend_` が
  // 先に破棄されるようにする(`backend_` のデストラクタが走った時点でも、
  // 既に飛んでいるコールバックは `context_` の `shared_ptr` 経由で
  // 生き続けるため、順序そのものは安全性の要件ではない)。
  std::shared_ptr<AsyncCallbackContext> context_;
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_OFFLINE_STT_API_IMPL_H_
