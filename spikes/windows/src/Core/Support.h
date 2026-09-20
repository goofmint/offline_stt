// Support.h
//
// 共通の型・エラー分類・基準音声パス解決・タイムアウトユーティリティ。
// spikes/darwin/Sources/DarwinSTTSpikeCore/Support.swift の構成に対応する。
//
// 対応 Issue: #15 / #16 / #17 / #18(共通基盤)。
// 対応する設計: design.md §4.4 Windows、§5 エラーマッピング(Windows列)。

#pragma once

#include <chrono>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <string>
#include <winrt/Windows.Foundation.h>

namespace wsspike {

// requirements.md FR-1 が定義する4値状態。
// Windows側の Microsoft.Windows.AI.AIFeatureReadyState との写像は ModelReadiness.h を参照。
enum class ModelState {
    Available,
    Downloadable,
    Downloading,
    Unavailable,
};

std::wstring ToString(ModelState state);

// design.md §5 の共通例外カテゴリ(Windows列)への分類。
// 表の内容:
//   ModelUnavailable  <- NotReady / EnsureNeeded で未同意
//   LocaleUnsupported <- (M0確認後に確定) ※本スパイクでは「ロケール指定API自体が
//                        ドキュメント上存在しない」ことをもって常に N/A として扱う
//   DecodeFailed      <- Media Foundation失敗
//   DeviceUnsupported <- NotSupportedOnCurrentSystem
//   Cancelled         <- 認識中断
enum class ErrorCategory {
    ModelUnavailable,
    LocaleUnsupported,
    DecodeFailed,
    DeviceUnsupported,
    Cancelled,
    // 本スパイク独自の追加分類(design.md §5 表には存在しない)。
    // spikes/darwin と同様、タイムアウト保護用に追加した。
    Timeout,
    // Issue #18: systemAIModels capability が宣言されていない場合の
    // "Not declared by app" 系エラー(winrt::hresult_access_denied)。
    // design.md §5 表には独立の行が無いため、本スパイクでは ModelUnavailable とは
    // 区別して CapabilityMissing として個別に記録する(RESULTS.md 参照)。
    CapabilityMissing,
    // 上記いずれにも分類できない WinRT / OS エラー。
    PlatformError,
};

std::wstring ToString(ErrorCategory category);

// スパイク全体で使う例外型。message には元の HRESULT / winrt::hresult_error の
// メッセージをそのまま含める(捏造禁止のため、分類ラベルと生メッセージを両方保持する)。
struct SpikeError {
    ErrorCategory category;
    std::wstring message;
    std::optional<int32_t> hresult;

    std::wstring Describe() const;
};

// test-assets/baseline-audio を探索する。
// darwin スパイクの Support.swift の baseline-dir 解決処理に対応する。
// 実行カレントディレクトリから最大6階層まで親をたどり、
// "test-assets/baseline-audio" が存在するディレクトリを返す。
// 見つからない場合は std::nullopt(呼び出し側で明示エラーにすること。フォールバック禁止)。
std::optional<std::wstring> ResolveBaselineAudioDir(const std::optional<std::wstring>& explicitDir);

// 現在時刻を ISO8601 (UTC) で返す。RESULTS.md 転記用のJSON出力に使う。
std::wstring NowIso8601Utc();

// --- タイムアウト付きブロッキング待機 -----------------------------------
//
// 本スパイクは Windows 実機を持たないため実測できないが、CLIとしては
// コンソールアプリで一般的なブロッキング `get()` パターンを使う
// (learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/concurrency の
//  "Block the calling thread" 節が示す、コンソールアプリに適した手法であり、
//  実際に `IAsyncAction::get()` はC++/WinRT拡張として文書で確認済み)。
//
// タイムアウト保護は `Completed` デリゲート(IAsyncInfoの標準メンバー。同ページの
// "It's also possible to handle the completed ... events ... by using delegates"
// 節で言及)と `Cancel()`(IAsyncInfoの標準メンバー)を組み合わせ、
// std::condition_variable で timeoutSeconds 秒待って未完了なら Cancel() する。
// `wait_for()` のような時限ブロッキング専用拡張の存在は公式ドキュメントで確認できな
// かったため使用しない(要確認事項として採用を見送った)。
//
// AsyncT は winrt::Windows::Foundation::IAsyncAction /
// IAsyncOperation<T> / IAsyncOperationWithProgress<T, P> のいずれか
// (Completed(handler) / Cancel() / GetResults() を持つ WinRT 非同期型)。
template <typename AsyncT>
void WaitOrCancel(AsyncT const& operation, double timeoutSeconds, const wchar_t* operationName) {
    auto readyPtr = std::make_shared<std::pair<std::mutex, std::condition_variable>>();
    auto done = std::make_shared<bool>(false);

    operation.Completed([done, readyPtr](auto&&, auto&&) {
        {
            std::lock_guard<std::mutex> lock(readyPtr->first);
            *done = true;
        }
        readyPtr->second.notify_all();
    });

    {
        std::unique_lock<std::mutex> lock(readyPtr->first);
        bool completedInTime = readyPtr->second.wait_for(
            lock, std::chrono::duration<double>(timeoutSeconds), [&] { return *done; });
        if (!completedInTime) {
            operation.Cancel();
            SpikeError err;
            err.category = ErrorCategory::Timeout;
            err.message = std::wstring(operationName) + L": " + std::to_wstring(timeoutSeconds) + L"秒超過(スパイク独自分類)";
            throw err;
        }
    }
}

}  // namespace wsspike
