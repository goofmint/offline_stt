// CapabilityCheck.cpp
#include "pch.h"
#include "CapabilityCheck.h"
#include "ModelReadiness.h"
#include "Support.h"

namespace wai = winrt::Microsoft::Windows::AI;

namespace wsspike {

CapabilityCheckResult CheckCapability() {
    CapabilityCheckResult result;
    try {
        ModelReadinessSnapshot snapshot = QueryModelReadiness();
        result.rawState = snapshot.rawState;
        if (snapshot.rawState == L"CapabilityMissing") {
            result.capabilityMissingObserved = true;
            result.detail = L"GetReadyState() returned CapabilityMissing";
        }
    } catch (const SpikeError& err) {
        result.rawState = L"(GetReadyState threw)";
        if (err.category == ErrorCategory::CapabilityMissing) {
            result.capabilityMissingObserved = true;
        }
        result.detail = err.Describe();
    }

    // GetReadyState() だけでは access_denied は発生しない可能性がある
    // (get-started.mdの記述はEnsureReadyAsync/CreateAsyncについてのものであり、
    // GetReadyStateは含まれていない)。そのため、GetReadyStateがCapabilityMissingを
    // 返さなかった場合でも、EnsureReadyAsyncを実際に一度呼んで確認する。
    // ダウンロードを実際にトリガーしてしまう副作用があるため、
    // capabilityMissingが既に確認できていれば追加呼び出しはスキップする。
    if (!result.capabilityMissingObserved) {
        try {
            EnsureModelReady(nullptr, /*timeoutSeconds=*/30.0);
        } catch (const SpikeError& err) {
            if (err.category == ErrorCategory::CapabilityMissing) {
                result.capabilityMissingObserved = true;
                result.detail = err.Describe();
            }
            // CapabilityMissing以外(例: 実際にモデル取得が進行中でタイムアウトした
            // 等)はこのサブコマンドの関心事ではないため無視する。
        }
    }

    return result;
}

}  // namespace wsspike
