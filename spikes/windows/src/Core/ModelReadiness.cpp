// ModelReadiness.cpp
#include "pch.h"
#include "ModelReadiness.h"

namespace wai = winrt::Microsoft::Windows::AI;
namespace wais = winrt::Microsoft::Windows::AI::Speech;

namespace wsspike {

namespace {

std::wstring StateName(wai::AIFeatureReadyState state) {
    switch (state) {
        case wai::AIFeatureReadyState::Ready: return L"Ready";
        case wai::AIFeatureReadyState::NotReady: return L"NotReady";
        case wai::AIFeatureReadyState::NotSupportedOnCurrentSystem: return L"NotSupportedOnCurrentSystem";
        case wai::AIFeatureReadyState::DisabledByUser: return L"DisabledByUser";
        case wai::AIFeatureReadyState::CapabilityMissing: return L"CapabilityMissing";
        case wai::AIFeatureReadyState::NotCompatibleWithSystemHardware: return L"NotCompatibleWithSystemHardware";
        case wai::AIFeatureReadyState::OSUpdateNeeded: return L"OSUpdateNeeded";
        default: return L"Unknown(" + std::to_wstring(static_cast<int>(state)) + L")";
    }
}

ModelState MapToModelState(wai::AIFeatureReadyState state) {
    // ModelReadiness.h のコメントに記載した本スパイクの写像方針。
    switch (state) {
        case wai::AIFeatureReadyState::Ready:
            return ModelState::Available;
        case wai::AIFeatureReadyState::NotReady:
            return ModelState::Downloadable;
        default:
            // DisabledByUser / NotSupportedOnCurrentSystem / CapabilityMissing /
            // NotCompatibleWithSystemHardware / OSUpdateNeeded はいずれも
            // Unavailable に写像する(理由はModelReadiness.h参照)。
            return ModelState::Unavailable;
    }
}

std::wstring ProgressStatusName(wais::SpeechRecognitionModelProgressStatus status) {
    switch (status) {
        case wais::SpeechRecognitionModelProgressStatus::Installing: return L"Installing";
        case wais::SpeechRecognitionModelProgressStatus::Caching: return L"Caching";
        case wais::SpeechRecognitionModelProgressStatus::Loading: return L"Loading";
        case wais::SpeechRecognitionModelProgressStatus::CompletedSuccess: return L"CompletedSuccess";
        case wais::SpeechRecognitionModelProgressStatus::CompletedFailure: return L"CompletedFailure";
        default: return L"Unknown(" + std::to_wstring(static_cast<int>(status)) + L")";
    }
}

// winrt::hresult_error を SpikeError に分類する。design.md §5(Windows列)準拠。
[[noreturn]] void ThrowAsSpikeError(const winrt::hresult_error& ex, const wchar_t* context) {
    SpikeError err;
    err.hresult = ex.code().value;
    err.message = std::wstring(context) + L": " + std::wstring(ex.message());

    // Issue #18: systemAIModels capability 未宣言時、公式ドキュメントは
    // 「EnsureReadyAsync / CreateAsync が winrt::hresult_access_denied を throw する」
    // と明記している(get-started.md, LanguageModel.EnsureReadyAsyncの記述を
    // SpeechRecognitionModelにも同様に適用できると推測。ただし Speech 固有の
    // 明記は無いため要確認)。E_ACCESSDENIED = 0x80070005。
    if (ex.code() == winrt::hresult(0x80070005)) {
        err.category = ErrorCategory::CapabilityMissing;
    } else {
        err.category = ErrorCategory::PlatformError;
    }
    throw err;
}

}  // namespace

ModelReadinessSnapshot QueryModelReadiness() {
    try {
        auto state = wais::SpeechRecognitionModel::GetReadyState();
        ModelReadinessSnapshot snapshot;
        snapshot.rawState = StateName(state);
        snapshot.mapped = MapToModelState(state);
        return snapshot;
    } catch (const winrt::hresult_error& ex) {
        ThrowAsSpikeError(ex, L"GetReadyState");
    }
}

void EnsureModelReady(const ModelProgressCallback& progressCallback, double timeoutSeconds) {
    try {
        auto operation = wais::SpeechRecognitionModel::EnsureReadyAsync();

        // IAsyncOperationWithProgress<TResult, TProgress> の標準メンバー Progress(handler)
        // で進捗を購読する(WinRT非同期プログレスパターン。
        // https://learn.microsoft.com/en-us/uwp/api/windows.foundation.iasyncoperationwithprogress-2
        // で定義されるインターフェイスのC++/WinRTプロジェクション標準機能)。
        operation.Progress([progressCallback](auto const&, wais::SpeechRecognitionModelProgress const& p) {
            if (progressCallback) {
                progressCallback(p.Progress, ProgressStatusName(p.Status));
            }
        });

        WaitOrCancel(operation, timeoutSeconds, L"EnsureReadyAsync");

        wai::AIFeatureReadyResult result = operation.GetResults();
        if (result.Status() != wai::AIFeatureReadyResultState::Success) {
            SpikeError err;
            err.category = ErrorCategory::ModelUnavailable;
            err.message = L"EnsureReadyAsync failed: " + std::wstring(result.ErrorDisplayText());
            throw err;
        }
    } catch (const winrt::hresult_error& ex) {
        ThrowAsSpikeError(ex, L"EnsureReadyAsync");
    }
}

}  // namespace wsspike
