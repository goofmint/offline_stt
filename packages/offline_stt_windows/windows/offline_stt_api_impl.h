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

class OfflineSttApiImpl : public OfflineSttHostApi {
 public:
  OfflineSttApiImpl(std::unique_ptr<SpeechBackend> backend,
                    std::unique_ptr<StreamCallbackSender> sender);
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

 private:
  std::unique_ptr<SpeechBackend> backend_;
  std::unique_ptr<StreamCallbackSender> sender_;

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
  std::atomic<bool> ensure_ready_in_flight_{false};

  // 同時に1本しか動かさない(design.md §3)。ここが true の間に
  // `TranscribeFile` / `DownloadModel` が呼ばれることは、Dart側の
  // `TranscribeSessionGuard` と `WindowsStreamRouter` で既に防がれている
  // が、ネイティブ単体でも破綻しないよう二重に持つ。
  std::atomic<bool> operation_in_flight_{false};
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_OFFLINE_STT_API_IMPL_H_
