// Support.cpp
#include "pch.h"
#include "Support.h"

#include <array>
#include <filesystem>
#include <sstream>

namespace wsspike {

std::wstring ToString(ModelState state) {
    switch (state) {
        case ModelState::Available: return L"available";
        case ModelState::Downloadable: return L"downloadable";
        case ModelState::Downloading: return L"downloading";
        case ModelState::Unavailable: return L"unavailable";
    }
    return L"unknown";
}

std::wstring ToString(ErrorCategory category) {
    switch (category) {
        case ErrorCategory::ModelUnavailable: return L"ModelUnavailable";
        case ErrorCategory::LocaleUnsupported: return L"LocaleUnsupported";
        case ErrorCategory::DecodeFailed: return L"DecodeFailed";
        case ErrorCategory::DeviceUnsupported: return L"DeviceUnsupported";
        case ErrorCategory::Cancelled: return L"Cancelled";
        case ErrorCategory::Timeout: return L"Timeout";
        case ErrorCategory::CapabilityMissing: return L"CapabilityMissing";
        case ErrorCategory::PlatformError: return L"PlatformError";
    }
    return L"Unknown";
}

std::wstring SpikeError::Describe() const {
    std::wstringstream ss;
    ss << ToString(category) << L"(" << message;
    if (hresult.has_value()) {
        ss << L" HRESULT=0x" << std::hex << hresult.value();
    }
    ss << L")";
    return ss.str();
}

std::optional<std::wstring> ResolveBaselineAudioDir(const std::optional<std::wstring>& explicitDir) {
    namespace fs = std::filesystem;

    if (explicitDir.has_value()) {
        fs::path p(*explicitDir);
        if (fs::exists(p)) {
            return p.wstring();
        }
        // 明示指定されたが存在しない場合はフォールバックせずそのまま探索を打ち切る。
        return std::nullopt;
    }

    fs::path current = fs::current_path();
    for (int i = 0; i < 6; ++i) {
        fs::path candidate = current / L"test-assets" / L"baseline-audio";
        if (fs::exists(candidate) && fs::is_directory(candidate)) {
            return candidate.wstring();
        }
        if (!current.has_parent_path() || current == current.parent_path()) {
            break;
        }
        current = current.parent_path();
    }
    return std::nullopt;
}

std::wstring NowIso8601Utc() {
    using namespace std::chrono;
    auto now = system_clock::now();
    auto t = system_clock::to_time_t(now);
    std::tm tmUtc{};
    gmtime_s(&tmUtc, &t);
    std::wstringstream ss;
    ss << std::put_time(&tmUtc, L"%Y-%m-%dT%H:%M:%SZ");
    return ss.str();
}

}  // namespace wsspike
