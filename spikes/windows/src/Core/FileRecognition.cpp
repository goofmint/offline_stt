// FileRecognition.cpp
#include "pch.h"
#include "FileRecognition.h"

#include <chrono>

namespace wai = winrt::Microsoft::Windows::AI;
namespace wais = winrt::Microsoft::Windows::AI::Speech;

namespace wsspike {

namespace {

[[noreturn]] void ThrowPlatformError(const winrt::hresult_error& ex, const wchar_t* context) {
    SpikeError err;
    err.category = ErrorCategory::PlatformError;
    err.hresult = ex.code().value;
    err.message = std::wstring(context) + L": " + std::wstring(ex.message());
    // Media Foundation由来と思われる典型的なHRESULT帯(MF_E_*は0xC00D....)は
    // DecodeFailedへ寄せる。ただし実機でしか実際の値を確認できないため、
    // 「該当する場合はDecodeFailedへ、それ以外はPlatformErrorへ」という
    // 分類ロジック自体を要確認としてコメントに明記する。
    uint32_t code = static_cast<uint32_t>(ex.code().value);
    if ((code & 0xFFFF0000) == 0xC00D0000) {
        err.category = ErrorCategory::DecodeFailed;
    }
    throw err;
}

}  // namespace

void* CreateSpeechModelOrThrow(double timeoutSeconds) {
    try {
        auto operation = wais::SpeechRecognitionModel::TryCreateAsync();
        WaitOrCancel(operation, timeoutSeconds, L"TryCreateAsync");
        wais::SpeechRecognitionModelResult result = operation.GetResults();

        // 公式サンプル(speech-recognition.md)の判定パターンに合わせる:
        //   if (speechModelResult.SpeechModel == null) throw ...
        if (result.SpeechModel() == nullptr) {
            SpikeError err;
            err.category = ErrorCategory::ModelUnavailable;
            // ExtendedError の正確な型(winrt::hresultか否か)は
            // SpeechRecognitionModelResultのプロパティ一覧ページでは確認できたが
            // (Name一覧に存在)、型注釈までは取得できなかった。ここでは
            // 公式サンプル("throw new InvalidOperationException($"...{speechModelResult.ExtendedError}"")
            // の書式文字列展開と同様に、そのまま文字列化できる前提で扱っている
            // (要確認: 実際の型がwinrt::hresultでなければビルドエラーになる)。
            err.message = L"TryCreateAsync: SpeechModel is null. ExtendedError(code)=" +
                           std::to_wstring(result.ExtendedError().value);
            throw err;
        }

        auto* handle = new wais::SpeechRecognitionModel(result.SpeechModel());
        return handle;
    } catch (const winrt::hresult_error& ex) {
        ThrowPlatformError(ex, L"TryCreateAsync");
    }
}

void ReleaseSpeechModel(void* modelHandle) {
    auto* model = static_cast<wais::SpeechRecognitionModel*>(modelHandle);
    delete model;
}

TranscriptionResult RecognizeFile(void* modelHandle, const std::wstring& filePath, double timeoutSeconds) {
    auto* model = static_cast<wais::SpeechRecognitionModel*>(modelHandle);

    try {
        wais::BatchRecognition batchRecognition(*model);

        auto start = std::chrono::steady_clock::now();
        auto operation = batchRecognition.RecognizeFromFile(winrt::hstring(filePath));
        WaitOrCancel(operation, timeoutSeconds, L"RecognizeFromFile");
        winrt::hstring transcript = operation.GetResults();
        auto end = std::chrono::steady_clock::now();

        TranscriptionResult result;
        result.filePath = filePath;
        result.transcript = std::wstring(transcript);
        result.elapsedSeconds = std::chrono::duration<double>(end - start).count();
        return result;
    } catch (const winrt::hresult_error& ex) {
        ThrowPlatformError(ex, L"RecognizeFromFile");
    }
}

FormatAcceptance TryRecognizeForFormatTest(void* modelHandle, const std::wstring& filePath, double timeoutSeconds) {
    FormatAcceptance acceptance;
    acceptance.filePath = filePath;
    auto start = std::chrono::steady_clock::now();
    try {
        auto result = RecognizeFile(modelHandle, filePath, timeoutSeconds);
        acceptance.accepted = true;
        acceptance.elapsedSeconds = result.elapsedSeconds;
    } catch (const SpikeError& err) {
        acceptance.accepted = false;
        acceptance.failureDetail = err.Describe();
        auto end = std::chrono::steady_clock::now();
        acceptance.elapsedSeconds = std::chrono::duration<double>(end - start).count();
    }
    return acceptance;
}

}  // namespace wsspike
