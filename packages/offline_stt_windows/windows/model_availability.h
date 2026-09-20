// model_availability.h
//
// Issue #53(FR-1): `SpeechRecognitionModel.GetReadyState()` が返す
// `Microsoft.Windows.AI.AIFeatureReadyState`(7値)を、requirements.md FR-1 の
// 4値(available / downloadable / downloading / unavailable)へ写像する。
// `offline_stt_darwin/darwin/Classes/ModelAvailability.swift` および
// `offline_stt_android/.../ModelAvailability.kt` に対応するファイル。
//
// =========================================================================
// FR-1 の4値写像 —— どこまでが文書化された事実で、どこからが判断か
// =========================================================================
//
// ## 文書で確認できた事実(spikes/windows/RESULTS.md、design.md §4.4)
// - `AIFeatureReadyState` は7値である:
//   `Ready` / `NotReady` / `NotSupportedOnCurrentSystem` / `DisabledByUser` /
//   `CapabilityMissing` / `NotCompatibleWithSystemHardware` /
//   `OSUpdateNeeded`。うち後半3つは WinAppSDK 2.0 以降で追加された値。
// - `downloading` に一意対応する値は**存在しない**。
// - design.md §4.4 / §5 に出てくる `EnsureNeeded` という状態は、実際の
//   enum のメンバーには存在しない(概念説明文中の言い回し)。
//
// ## 本実装が採用した写像(★ が付いた行は判断であり、文書化された対応では
//    ない。spikes/windows/src/Core/ModelReadiness.h の方針を踏襲している)
//   Ready                           -> available
//   NotReady                        -> downloadable  ★
//   DisabledByUser                  -> unavailable   ★
//   NotSupportedOnCurrentSystem     -> unavailable
//   CapabilityMissing               -> unavailable   ★
//   NotCompatibleWithSystemHardware -> unavailable
//   OSUpdateNeeded                  -> unavailable   ★
//   上記以外(将来追加された値)     -> unavailable   ★
//
// 判断の理由:
// - `NotReady` → `downloadable`: `NotReady` は「モデルがまだ端末に無い状態」
//   であり、`EnsureReadyAsync()` を呼べば取得が始まる。FR-2 の
//   `downloadModel()` が意味を持つ唯一の状態なので `downloadable` を当てた。
// - `DisabledByUser` → `unavailable`: アプリ側から `EnsureReadyAsync()` で
//   解消できず、Windows の設定でユーザーが再度有効化する必要がある。
//   `downloadable` にするとアプリが `downloadModel()` を呼んでも何も起きず、
//   利用者から見て嘘になる。終端状態である `unavailable` が正しい。
// - `CapabilityMissing` → `unavailable`: 実体はアプリ側MSIXマニフェストの
//   不備であり「端末が非対応」ではないが、FR-1 の4値にこれを表す値は無い。
//   ダウンロードで解消しない以上 `downloadable` ではなく `unavailable`。
//   原因が分かるよう、`EnsureReadyAsync()` / `TryCreateAsync()` 側で
//   `E_ACCESSDENIED` を捕まえたときにメッセージで明示する
//   (`windows_transcribe_error.cpp`)。
// - `OSUpdateNeeded` → `unavailable`: Windows Update が必要で、アプリからは
//   解消できない。上と同じ理由。
//
// ## `downloading` をどう扱うか(★ 全面的に判断)
// `GetReadyState()` だけでは `downloading` を返せない。本実装は
// 「**このプラグイン自身が `EnsureReadyAsync()` を実行している間だけ**
//   `checkModel()` が `downloading` を返す」
// という補い方を採り、その判定は `offline_stt_api_impl.cpp` が持つ
// `ensure_ready_in_flight_` フラグで行う(本ファイルの写像には現れない)。
//
// この方式の限界を明記しておく:
// - 別のアプリ、あるいは同じアプリの別プロセスが開始したダウンロードは
//   見えない。その間 `checkModel()` は `NotReady` 由来の `downloadable` を
//   返しうる。
// - アプリを再起動するとフラグは失われる。OS側のダウンロードが続いていても
//   `downloading` には戻らない。
// より正確にするには `EnsureReadyAsync()` を呼ばずにダウンロード中かどうかを
// 知るAPIが要るが、そのようなAPIは `Microsoft.Windows.AI.Speech` に存在しない
// ことをドキュメント調査で確認している。**この制約は Issue #58 の実機検証で
// 挙動を確認したうえで、README(Issue #57)に明記する必要がある。**
//
// =========================================================================
// WinAppSDK のバージョン差への対処
// =========================================================================
// `CapabilityMissing` / `NotCompatibleWithSystemHardware` / `OSUpdateNeeded`
// は WinAppSDK 2.0 以降でしか定義されていない。requirements.md NFR-4 が言う
// 1.7.1 でビルドするとこれらの識別子が存在せずコンパイルエラーになる。
// そのため実装(`model_availability.cpp`)の `switch` はどのバージョンにも
// 存在する4値だけを明示的に列挙し、残りは `default` で受ける。
// spikes/windows/src/Core/ModelReadiness.cpp は7値すべてを列挙しているが、
// あれは 2.0-experimental 前提のスパイクであり、本実装ではバージョン前提が
// 未確定(design.md §4.4 / NFR-4 の齟齬)であるためこの形にしている。
#ifndef OFFLINE_STT_WINDOWS_MODEL_AVAILABILITY_H_
#define OFFLINE_STT_WINDOWS_MODEL_AVAILABILITY_H_

#include "speech_backend.h"

namespace offline_stt_windows {

// `SpeechRecognitionModel.GetReadyState()` を1回呼び、上記の写像を適用する。
// 呼び出し元スレッドで COM / WinRT が初期化済みであることを前提とする
// (`speech_backend_winrt.cpp` の該当コメント参照)。
ModelStateResult QueryModelReadyState();

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_MODEL_AVAILABILITY_H_
