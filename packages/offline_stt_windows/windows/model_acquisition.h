// model_acquisition.h
//
// Issue #53(FR-2): `SpeechRecognitionModel.EnsureReadyAsync()` によるモデル
// 取得。`offline_stt_darwin/darwin/Classes/ModelAcquisition.swift` および
// `offline_stt_android/.../ModelAcquisition.kt` に対応するファイル。
//
// =========================================================================
// 進捗の粒度 —— なぜ常に「不定進捗」にするのか
// =========================================================================
// design.md §4.4 は「進捗APIの粒度が粗い場合は `DownloadProgress(fraction:
// null)` の不定進捗」と定め、requirements.md FR-2 も「Windowsは進捗APIの粒度が
// 異なるため、進捗が取得できない場合は不定進捗として通知」と定めている。
//
// 本実装は **常に不定進捗(`fraction = null`)** とする。理由:
//
// 1. `SpeechRecognitionModelProgress` は `{ double Progress;
//    SpeechRecognitionModelProgressStatus Status; }` の2フィールドを持つ、
//    ということまではドキュメントで確認できている(spikes/windows/RESULTS.md)。
//    しかし **`Progress` の値域はドキュメントに一切記載が無い**。0.0〜1.0 で
//    ある保証が無いものを `DownloadProgress.fraction`(design.md §2.2 が
//    「0.0〜1.0」と定義)として素通しするのは、未確認の前提を確認済みである
//    かのように扱うことになる。
// 2. `Status` は `Installing` / `Caching` / `Loading` / `CompletedSuccess` /
//    `CompletedFailure` の5フェーズを持つ。`Progress` がフェーズごとに
//    0→1 を繰り返すのか、全体で単調増加するのかは**どこにも書かれていない**。
//    前者だった場合、素通しすると進捗バーが3回巻き戻る。
// 3. 3フェーズを 0.0〜0.33 / 0.33〜0.66 / 0.66〜1.0 に割り当てるような
//    「補正」は、根拠のない数値をライブラリ利用者へ提示することになる。
//    リポジトリ方針(フォールバック・既定値の捏造の禁止)に反する。
//
// したがって「値は出せないが、進んでいることは伝える」という形に倒し、
// 進捗イベントが届くたびに `fraction = null, completed = false` を1件送る。
// これは requirements.md FR-2 が Web(`install()` が進捗を返さない)に対して
// 採った扱いと同じである。
//
// **Issue #58 で確認すべきこと**: `Progress` の実際の値域、フェーズごとの
// 挙動、コールバックの発火回数。全体で単調増加する 0.0〜1.0 だと確認できた
// なら、そのときに初めて実値の通知へ切り替えればよい。
#ifndef OFFLINE_STT_WINDOWS_MODEL_ACQUISITION_H_
#define OFFLINE_STT_WINDOWS_MODEL_ACQUISITION_H_

#include <functional>
#include <memory>
#include <optional>

#include "windows_transcribe_error.h"

namespace offline_stt_windows {

// `EnsureReadyAsync()` の1回分の実行を表す。
// WinRT の型をヘッダーに出さないため pimpl にしている
// (理由は `speech_backend.h` の隔離方針を参照)。
class ModelAcquisition {
 public:
  ModelAcquisition();
  ~ModelAcquisition();

  ModelAcquisition(const ModelAcquisition&) = delete;
  ModelAcquisition& operator=(const ModelAcquisition&) = delete;

  // 即座に戻る。`on_progress` / `on_complete` は WinRT のワーカースレッドから
  // 呼ばれる。`on_progress` が進捗値を取らないのは、上記のとおり常に不定進捗
  // として扱うためである。
  void Start(std::function<void()> on_progress,
             std::function<void(std::optional<TranscribeError>)> on_complete);

  // 実行中であればキャンセルを要求する。`on_complete` は
  // `TranscribeErrorCode::kCancelled` で呼ばれる。
  void Cancel();

 private:
  struct State;
  std::shared_ptr<State> state_;
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_MODEL_ACQUISITION_H_
