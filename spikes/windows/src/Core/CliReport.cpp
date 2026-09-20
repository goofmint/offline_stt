// CliReport.cpp
#include "pch.h"
#include "CliReport.h"

#include <iostream>

namespace wsspike {

void InitConsoleUtf8() {
    ::SetConsoleOutputCP(CP_UTF8);
    ::SetConsoleCP(CP_UTF8);
}

void PrintLine(const std::wstring& line) {
    std::wcout << line << std::endl;
}

json::Value ToJson(const ModelReadinessSnapshot& snapshot) {
    auto obj = json::Value::MakeObject();
    obj.Set(L"rawState", json::Value::MakeString(snapshot.rawState));
    obj.Set(L"mapped", json::Value::MakeString(ToString(snapshot.mapped)));
    return obj;
}

json::Value ToJson(const LocaleInquiryResult& result) {
    auto obj = json::Value::MakeObject();
    obj.Set(L"localeApiConfirmedAbsent", json::Value::MakeBool(result.localeApiConfirmedAbsent));
    obj.Set(L"userDefaultLocaleName", json::Value::MakeString(result.userDefaultLocaleName));
    obj.Set(L"systemDefaultLocaleName", json::Value::MakeString(result.systemDefaultLocaleName));
    obj.Set(L"preferredUiLanguage", json::Value::MakeString(result.preferredUiLanguage));
    return obj;
}

json::Value ToJson(const TranscriptionResult& result) {
    auto obj = json::Value::MakeObject();
    obj.Set(L"filePath", json::Value::MakeString(result.filePath));
    obj.Set(L"transcript", json::Value::MakeString(result.transcript));
    obj.Set(L"elapsedSeconds", json::Value::MakeNumber(result.elapsedSeconds));
    return obj;
}

json::Value ToJson(const FormatAcceptance& acceptance) {
    auto obj = json::Value::MakeObject();
    obj.Set(L"filePath", json::Value::MakeString(acceptance.filePath));
    obj.Set(L"accepted", json::Value::MakeBool(acceptance.accepted));
    obj.Set(L"failureDetail", json::Value::MakeString(acceptance.failureDetail));
    obj.Set(L"elapsedSeconds", json::Value::MakeNumber(acceptance.elapsedSeconds));
    return obj;
}

json::Value ToJson(const KeywordScoringResult& scoring) {
    auto obj = json::Value::MakeObject();
    obj.Set(L"matchedCount", json::Value::MakeNumber(scoring.matchedCount));
    obj.Set(L"totalCount", json::Value::MakeNumber(scoring.totalCount));
    obj.Set(L"ratio", json::Value::MakeNumber(scoring.ratio));
    obj.Set(L"verdict", json::Value::MakeString(ToString(scoring.verdict)));

    auto matched = json::Value::MakeArray();
    for (const auto& k : scoring.matchedKeywords) matched.PushBack(json::Value::MakeString(k));
    obj.Set(L"matchedKeywords", matched);

    auto unmatched = json::Value::MakeArray();
    for (const auto& k : scoring.unmatchedKeywords) unmatched.PushBack(json::Value::MakeString(k));
    obj.Set(L"unmatchedKeywords", unmatched);

    return obj;
}

json::Value ToJson(const CapabilityCheckResult& result) {
    auto obj = json::Value::MakeObject();
    obj.Set(L"rawState", json::Value::MakeString(result.rawState));
    obj.Set(L"capabilityMissingObserved", json::Value::MakeBool(result.capabilityMissingObserved));
    obj.Set(L"detail", json::Value::MakeString(result.detail));
    return obj;
}

}  // namespace wsspike
