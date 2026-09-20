// CliReport.h
//
// CLI出力用の集計型・JSONエンコード。spikes/darwin の CLIReport.swift に対応する。
// 標準出力への人間可読ログと、--json 指定時の機械可読JSON(RESULTS.md転記用)の
// 両方をこのモジュールに集約する。

#pragma once

#include <string>

#include "CapabilityCheck.h"
#include "FileRecognition.h"
#include "Json.h"
#include "KeywordScoring.h"
#include "LocaleInquiry.h"
#include "ModelReadiness.h"

namespace wsspike {

// コンソール出力をUTF-8として正しく行うための初期化
// (SetConsoleOutputCP(CP_UTF8)を呼ぶ。日本語を含むためJSON/ログ双方に必要)。
void InitConsoleUtf8();

void PrintLine(const std::wstring& line);

json::Value ToJson(const ModelReadinessSnapshot& snapshot);
json::Value ToJson(const LocaleInquiryResult& result);
json::Value ToJson(const TranscriptionResult& result);
json::Value ToJson(const FormatAcceptance& acceptance);
json::Value ToJson(const KeywordScoringResult& scoring);
json::Value ToJson(const CapabilityCheckResult& result);

}  // namespace wsspike
