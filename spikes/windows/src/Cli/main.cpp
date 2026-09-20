// main.cpp — windows-stt-spike CLIエントリポイント。
//
// spikes/darwin/Sources/DarwinSTTSpikeCLI/main.swift + CLI.swift に対応する
// サブコマンド構成。詳細はREADME.mdのサブコマンド表を参照。
//
// 実行にはMSIXパッケージ化 + systemAIModels capability宣言が必須である
// (README「前提」参照)。本スパイクはWindows機を持たないため、以下のロジックは
// 一度もビルド・実行できていない(README冒頭の注記を参照)。

#include "pch.h"

#include <iostream>
#include <optional>

#include "CapabilityCheck.h"
#include "CliReport.h"
#include "FileRecognition.h"
#include "Json.h"
#include "KeywordScoring.h"
#include "LocaleInquiry.h"
#include "ModelReadiness.h"
#include "Support.h"

using namespace wsspike;

namespace {

constexpr double kDefaultTimeoutSeconds = 600.0;

struct Args {
    std::wstring command;
    std::vector<std::wstring> positional;
    std::optional<std::wstring> baselineDir;
    std::optional<std::wstring> format;
    double timeoutSeconds = kDefaultTimeoutSeconds;
    bool json = false;
};

Args ParseArgs(int argc, wchar_t** argv) {
    Args args;
    if (argc >= 2) {
        args.command = argv[1];
    }
    for (int i = 2; i < argc; ++i) {
        std::wstring a = argv[i];
        if (a == L"--json") {
            args.json = true;
        } else if (a == L"--baseline-dir" && i + 1 < argc) {
            args.baselineDir = argv[++i];
        } else if (a == L"--format" && i + 1 < argc) {
            args.format = argv[++i];
        } else if (a == L"--timeout" && i + 1 < argc) {
            args.timeoutSeconds = std::stod(argv[++i]);
        } else {
            args.positional.push_back(a);
        }
    }
    return args;
}

struct ClipSpec {
    std::wstring id;      // 例: jaJP_10s
    std::wstring locale;  // ja-JP / en-US (design.md §5同様、表示用ラベルに過ぎない。
                           // LocaleInquiry.h記載のとおりAPIには渡していない)
};

const std::vector<ClipSpec>& AllClips() {
    static const std::vector<ClipSpec> clips = {
        {L"jaJP_10s", L"ja-JP"},
        {L"jaJP_3m", L"ja-JP"},
        {L"enUS_10s", L"en-US"},
        {L"enUS_3m", L"en-US"},
    };
    return clips;
}

bool IsJaJp(const std::wstring& locale) { return locale == L"ja-JP"; }

std::wstring JoinPath(const std::wstring& dir, const std::wstring& file) {
    if (!dir.empty() && (dir.back() == L'\\' || dir.back() == L'/')) {
        return dir + file;
    }
    return dir + L"\\" + file;
}

// baseline-audio/<clipId>.json を読み、"keywords" フィールドを取り出す。
// 見つからない/形式不正の場合は例外(フォールバック禁止)。
json::Value LoadKeywords(const std::wstring& baselineDir, const std::wstring& clipId) {
    std::wstring jsonPath = JoinPath(baselineDir, clipId + L".json");
    json::Value doc = json::ParseFile(jsonPath);
    const json::Value& keywords = doc.Get(L"keywords");
    if (!keywords.IsArray()) {
        throw std::runtime_error("keywords field missing or not an array in " + json::WideToUtf8(jsonPath));
    }
    return keywords;
}

int CmdModelState(const Args& /*args*/) {
    auto snapshot = QueryModelReadiness();
    PrintLine(L"GetReadyState (raw)   : " + snapshot.rawState);
    PrintLine(L"FR-1 4値写像 (mapped) : " + ToString(snapshot.mapped));
    return 0;
}

int CmdModelEnsure(const Args& args) {
    PrintLine(L"EnsureReadyAsync() 開始(タイムアウト " + std::to_wstring(args.timeoutSeconds) + L"秒)");
    int progressEventCount = 0;
    EnsureModelReady(
        [&](double fraction, const std::wstring& status) {
            ++progressEventCount;
            PrintLine(L"  progress#" + std::to_wstring(progressEventCount) + L" status=" + status +
                       L" fraction=" + std::to_wstring(fraction));
        },
        args.timeoutSeconds);
    PrintLine(L"EnsureReadyAsync() 完了。進捗コールバック回数=" + std::to_wstring(progressEventCount) +
               L"(この回数が「進捗の粒度」の実測値。README参照)");
    return 0;
}

int CmdLocale(const Args& /*args*/) {
    auto result = QueryLocaleInquiry();
    PrintLine(L"ロケール指定API: 存在しない(LocaleInquiry.h参照。ドキュメント調査で確定)");
    PrintLine(L"GetUserDefaultLocaleName   : " + result.userDefaultLocaleName);
    PrintLine(L"GetSystemDefaultLocaleName : " + result.systemDefaultLocaleName);
    PrintLine(L"優先UI言語(先頭)           : " + result.preferredUiLanguage);
    return 0;
}

int CmdCapabilityCheck(const Args& /*args*/) {
    auto result = CheckCapability();
    PrintLine(L"GetReadyState (raw) : " + result.rawState);
    PrintLine(L"CapabilityMissing観測: " + std::wstring(result.capabilityMissingObserved ? L"YES" : L"NO"));
    if (!result.detail.empty()) {
        PrintLine(L"詳細: " + result.detail);
    }
    PrintLine(L"※ systemAIModels宣言あり/なしの2種のMSIXパッケージそれぞれで本コマンドを実行し、"
               L"結果を突き合わせること(README参照)");
    return 0;
}

int CmdTranscribe(const Args& args) {
    if (args.positional.empty()) {
        std::wcerr << L"使い方: transcribe <clipId> [--format wav|m4a|mp3] [--baseline-dir <path>]" << std::endl;
        return 2;
    }
    std::wstring clipId = args.positional[0];
    std::wstring format = args.format.value_or(L"wav");

    auto baselineDir = ResolveBaselineAudioDir(args.baselineDir);
    if (!baselineDir.has_value()) {
        std::wcerr << L"test-assets/baseline-audio が見つかりません" << std::endl;
        return 1;
    }
    std::wstring filePath = JoinPath(*baselineDir, clipId + L"." + format);

    bool isJa = clipId.rfind(L"jaJP", 0) == 0;

    void* model = CreateSpeechModelOrThrow(args.timeoutSeconds);
    TranscriptionResult transcription;
    try {
        transcription = RecognizeFile(model, filePath, args.timeoutSeconds);
    } catch (...) {
        ReleaseSpeechModel(model);
        throw;
    }
    ReleaseSpeechModel(model);

    PrintLine(L"transcript: " + transcription.transcript);
    PrintLine(L"elapsedSeconds: " + std::to_wstring(transcription.elapsedSeconds));

    auto keywords = LoadKeywords(*baselineDir, clipId);
    auto scoring = ScoreKeywords(keywords, transcription.transcript, isJa);
    PrintLine(L"keyword ratio: " + std::to_wstring(scoring.matchedCount) + L"/" +
               std::to_wstring(scoring.totalCount) + L" = " + std::to_wstring(scoring.ratio * 100.0) + L"% (" +
               ToString(scoring.verdict) + L")");

    if (args.json) {
        auto obj = json::Value::MakeObject();
        obj.Set(L"transcription", ToJson(transcription));
        obj.Set(L"scoring", ToJson(scoring));
        PrintLine(obj.Dump(0));
    }
    return 0;
}

int CmdFormatTest(const Args& args) {
    if (args.positional.empty()) {
        std::wcerr << L"使い方: format-test <clipId> [--baseline-dir <path>]" << std::endl;
        return 2;
    }
    std::wstring clipId = args.positional[0];
    auto baselineDir = ResolveBaselineAudioDir(args.baselineDir);
    if (!baselineDir.has_value()) {
        std::wcerr << L"test-assets/baseline-audio が見つかりません" << std::endl;
        return 1;
    }

    // Issue #16: wav / m4a / mp3 の受理テスト。mp3は
    // scripts/generate_mp3.sh で生成した spikes/windows 側のフィクスチャを使う
    // (共通資産 test-assets/ は変更しない。README参照)。
    void* model = CreateSpeechModelOrThrow(args.timeoutSeconds);
    auto obj = json::Value::MakeObject();
    auto results = json::Value::MakeArray();
    for (const wchar_t* ext : {L"wav", L"m4a", L"mp3"}) {
        std::wstring filePath = JoinPath(*baselineDir, clipId + L"." + ext);
        auto acceptance = TryRecognizeForFormatTest(model, filePath, args.timeoutSeconds);
        PrintLine(std::wstring(ext) + L": " + (acceptance.accepted ? L"ACCEPTED" : L"REJECTED") +
                   (acceptance.accepted ? L"" : (L" (" + acceptance.failureDetail + L")")));
        results.PushBack(ToJson(acceptance));
    }
    ReleaseSpeechModel(model);

    obj.Set(L"clipId", json::Value::MakeString(clipId));
    obj.Set(L"results", results);
    if (args.json) {
        PrintLine(obj.Dump(0));
    }
    return 0;
}

int CmdAll(const Args& args) {
    auto baselineDir = ResolveBaselineAudioDir(args.baselineDir);
    if (!baselineDir.has_value()) {
        std::wcerr << L"test-assets/baseline-audio が見つかりません" << std::endl;
        return 1;
    }

    auto readiness = QueryModelReadiness();
    PrintLine(L"[model] raw=" + readiness.rawState + L" mapped=" + ToString(readiness.mapped));
    if (readiness.mapped != ModelState::Available) {
        PrintLine(L"モデル未取得のため EnsureReadyAsync を実行します");
        EnsureModelReady(
            [](double fraction, const std::wstring& status) {
                PrintLine(L"  progress status=" + status + L" fraction=" + std::to_wstring(fraction));
            },
            args.timeoutSeconds);
    }

    auto reportRoot = json::Value::MakeObject();
    reportRoot.Set(L"generatedAt", json::Value::MakeString(NowIso8601Utc()));
    auto clipsJson = json::Value::MakeArray();

    for (const auto& clip : AllClips()) {
        for (const wchar_t* ext : {L"wav", L"m4a"}) {
            std::wstring filePath = JoinPath(*baselineDir, clip.id + L"." + ext);
            PrintLine(L"=== " + clip.id + L"." + ext + L" ===");

            void* model = CreateSpeechModelOrThrow(args.timeoutSeconds);
            TranscriptionResult transcription;
            std::wstring errorDetail;
            bool ok = true;
            try {
                transcription = RecognizeFile(model, filePath, args.timeoutSeconds);
            } catch (const SpikeError& err) {
                ok = false;
                errorDetail = err.Describe();
                PrintLine(L"  [エラー] " + errorDetail);
            }
            ReleaseSpeechModel(model);

            auto clipJson = json::Value::MakeObject();
            clipJson.Set(L"clipId", json::Value::MakeString(clip.id));
            clipJson.Set(L"format", json::Value::MakeString(ext));
            clipJson.Set(L"ok", json::Value::MakeBool(ok));

            if (ok) {
                PrintLine(L"  transcript: " + transcription.transcript);
                PrintLine(L"  elapsedSeconds: " + std::to_wstring(transcription.elapsedSeconds));
                clipJson.Set(L"transcription", ToJson(transcription));

                auto keywords = LoadKeywords(*baselineDir, clip.id);
                auto scoring = ScoreKeywords(keywords, transcription.transcript, IsJaJp(clip.locale));
                PrintLine(L"  keyword ratio: " + std::to_wstring(scoring.ratio * 100.0) + L"% (" +
                           ToString(scoring.verdict) + L")");
                clipJson.Set(L"scoring", ToJson(scoring));
            } else {
                clipJson.Set(L"error", json::Value::MakeString(errorDetail));
            }
            clipsJson.PushBack(clipJson);
        }
    }

    reportRoot.Set(L"model", ToJson(readiness));
    reportRoot.Set(L"clips", clipsJson);

    if (args.json) {
        PrintLine(reportRoot.Dump(0));
    }
    return 0;
}

void PrintUsage() {
    std::wcerr << L"windows-stt-spike <command> [options]\n"
                   L"commands:\n"
                   L"  model-state\n"
                   L"  model-ensure [--timeout <seconds>]\n"
                   L"  locale\n"
                   L"  capability-check\n"
                   L"  transcribe <clipId> [--format wav|m4a|mp3] [--baseline-dir <path>] [--json]\n"
                   L"  format-test <clipId> [--baseline-dir <path>] [--json]\n"
                   L"  all [--baseline-dir <path>] [--timeout <seconds>] [--json]\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    winrt::init_apartment();
    InitConsoleUtf8();

    Args args = ParseArgs(argc, argv);
    if (args.command.empty()) {
        PrintUsage();
        return 2;
    }

    try {
        if (args.command == L"model-state") return CmdModelState(args);
        if (args.command == L"model-ensure") return CmdModelEnsure(args);
        if (args.command == L"locale") return CmdLocale(args);
        if (args.command == L"capability-check") return CmdCapabilityCheck(args);
        if (args.command == L"transcribe") return CmdTranscribe(args);
        if (args.command == L"format-test") return CmdFormatTest(args);
        if (args.command == L"all") return CmdAll(args);
        PrintUsage();
        return 2;
    } catch (const SpikeError& err) {
        std::wcerr << L"[エラー] " << err.Describe() << std::endl;
        return 1;
    } catch (const winrt::hresult_error& ex) {
        std::wcerr << L"[WinRTエラー] 0x" << std::hex << static_cast<uint32_t>(ex.code().value) << L" "
                    << std::wstring(ex.message()) << std::endl;
        return 1;
    } catch (const std::exception& ex) {
        std::wcerr << L"[エラー] " << ex.what() << std::endl;
        return 1;
    }
}
