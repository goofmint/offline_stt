// ModelReadiness.h
//
// Issue #15: モデル状態照会(GetReadyState → FR-1の4値写像)とモデル取得
// (EnsureReadyAsync → FR-2、進捗の粒度を観測)。
//
// 対応する設計: design.md §4.4 Windows「モデル管理: GetReadyState() → FR-1、
// EnsureReadyAsync() → FR-2」。
//
// 参照した公式ドキュメント(2026-09-20 WebFetchで確認):
// - https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel.getreadystate
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel.ensurereadyasync
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.aifeaturereadystate
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelprogress
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelprogressstatus
//
// 確認できた事実(要確認ではない):
// - `SpeechRecognitionModel.GetReadyState()` は static メソッドで、
//   戻り値は `Microsoft::Windows::AI::AIFeatureReadyState`
//   (cppwinrt: `static AIFeatureReadyState GetReadyState();`)。
// - `SpeechRecognitionModel.EnsureReadyAsync()` は static メソッドで、
//   戻り値は `IAsyncOperationWithProgress<AIFeatureReadyResult, SpeechRecognitionModelProgress>`。
// - `AIFeatureReadyState` は7値: Ready(0) / NotReady(1) /
//   NotSupportedOnCurrentSystem(2) / DisabledByUser(3) / CapabilityMissing(4,
//   WinAppSDK 2.0+) / NotCompatibleWithSystemHardware(5, WinAppSDK 2.0+) /
//   OSUpdateNeeded(6, WinAppSDK 2.0+)。
//   design.md §4.4 / §5 が言及する "EnsureNeeded" という名前の列挙値は
//   AIFeatureReadyState の実際のフィールド一覧には存在しない
//   (conceptual doc の説明文中でNotReadyと並記される非公式な言い回しである)。
//   README/RESULTS.md「design.md/requirements.mdとの齟齬」に記録している。
// - `SpeechRecognitionModelProgress` は `{ double Progress; SpeechRecognitionModelProgressStatus Status; }`
//   の2フィールドを持つ struct。`SpeechRecognitionModelProgressStatus` は
//   Installing(0) / Caching(1) / Loading(2) / CompletedSuccess(3) /
//   CompletedFailure(4) の5値。「進捗の粒度」(tasks.md Windows節)は、
//   0.0〜1.0の連続値(Progress)と5段階のフェーズ(Status)の組み合わせであることが
//   ドキュメント上確定している。ただし各フェーズでProgressが実際にどの粒度で
//   更新されるか(何回コールバックされるか)は実機でしか分からない
//   (RESULTS.md「実機でのみ確認可能な事項」参照)。
//
// 要確認(ドキュメントで確認できず、実機で確認が必要な事項):
// - GetReadyState() が返す7値のうち、FR-1の `downloading` にどう対応する値が
//   あるかはドキュメント上に存在しない(後述)。
// - CapabilityMissing は「WinAppSDK 2.0以降で利用可能」と明記されているが、
//   requirements.md が指定する WinAppSDK 1.7.1 上での CapabilityMissing の
//   挙動(たとえば単に例外がthrowされるだけでこの列挙値自体は返らない可能性)は
//   未確認。README「systemAIModels capabilityを宣言しないとどうなるか」参照。

#pragma once

#include <functional>
#include <optional>

#include "Support.h"

namespace wsspike {

// FR-1: GetReadyState() の戻り値(AIFeatureReadyState、7値)を
// requirements.md FR-1 の4値(available/downloadable/downloading/unavailable)へ
// 写像する。
//
// 本スパイクが採用した写像方針(design.md に明記が無いため、本スパイクの解釈として
// README/RESULTS.mdに明記する):
//   Ready                            -> Available
//   NotReady                         -> Downloadable(EnsureReadyAsync呼び出しで取得可能)
//   DisabledByUser                   -> Unavailable(Windows設定側での再有効化が必要)
//   NotSupportedOnCurrentSystem      -> Unavailable
//   CapabilityMissing                -> Unavailable(実際はアプリ側マニフェスト不備。
//                                        SpikeErrorのCapabilityMissing分類で別途記録)
//   NotCompatibleWithSystemHardware  -> Unavailable
//   OSUpdateNeeded                   -> Unavailable
//
// 「downloading」に一意に対応する AIFeatureReadyState 値は存在しない。
// ダウンロード中であることを知るには EnsureReadyAsync() 実行中に
// SpeechRecognitionModelProgress.Status を観測する必要がある
// (EnsureModelReady() 参照)。この非対称性は design.md/requirements.md との
// 齟齬としてRESULTS.mdに記録している。
struct ModelReadinessSnapshot {
    // Microsoft.Windows.AI.AIFeatureReadyState の名前(文字列化)。
    // 実機値をそのまま記録する(捏造禁止のため生値を保持)。
    std::wstring rawState;
    ModelState mapped;
};

// GetReadyState() を1回呼び出し、写像結果を返す。
// 本関数は WinRT 型を直接返さず、SpikeError 経由で例外を投げる。
ModelReadinessSnapshot QueryModelReadiness();

// EnsureReadyAsync() の進捗コールバック。
// progressFraction: SpeechRecognitionModelProgress.Progress(0.0〜1.0の想定だが
//   実機未検証。ドキュメントに値域の明記は無い)。
// statusName: SpeechRecognitionModelProgressStatus の文字列化
//   (Installing/Caching/Loading/CompletedSuccess/CompletedFailure)。
using ModelProgressCallback = std::function<void(double progressFraction, const std::wstring& statusName)>;

// EnsureReadyAsync() を実行し、完了まで進捗を progressCallback へ通知する。
// design.md「進捗APIの粒度が粗い場合は DownloadProgress(fraction: null) の不定進捗」
// という規定に対して、本スパイクの役割は「粗いかどうか実測する」ことである。
// 失敗時は AIFeatureReadyResult.Status(AIFeatureReadyResultState:
// InProgress/Success/Failure)と ExtendedError を SpikeError に変換して投げる。
void EnsureModelReady(const ModelProgressCallback& progressCallback, double timeoutSeconds);

}  // namespace wsspike
