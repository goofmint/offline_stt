// CapabilityCheck.h
//
// Issue #18: systemAIModels capability 検証。APIを1回呼び、
// "Not declared by app" 相当のエラーが発生するかを確認する。
//
// 検証方法: 本スパイクは同一バイナリを2種類の Package.appxmanifest
// (packaging/Package.appxmanifest = capability宣言あり、
//  packaging/Package.NoCapability.appxmanifest = capability宣言なし)で
// それぞれMSIXパッケージ化し、両方でこのサブコマンドを実行して差分を観測する
// 想定である(README参照)。コード側は「今回起動したパッケージでcapabilityが
// 有効かどうか」を判定するだけで、宣言の有無そのものをコードから検出することは
// できない(WinRT/MSIXにその照会APIは無いため、パッケージを差し替えて実行するのが
// 唯一の確認方法。要確認: 他の確認手段が無いことの断定はドキュメント上明記されて
// いるわけではなく、本スパイクの調査範囲でも見つからなかったという意味)。
//
// 判定ロジック: GetReadyState() の戻り値が CapabilityMissing であるか、
// または GetReadyState()/EnsureReadyAsync() の呼び出しが
// winrt::hresult_access_denied (0x80070005) を送出するかを見る。
// 根拠: get-started.md「CapabilityMissing ... EnsureReadyAsync and CreateAsync
// will throw winrt::hresult_access_denied (add the systemAIModels capability to
// the app manifest)」(Microsoft.Windows.AI.Text.LanguageModelについての記述。
// Speech固有の明記は無く、同一パターンが適用されると推測したものであり要確認)。

#pragma once

#include <string>

namespace wsspike {

struct CapabilityCheckResult {
    // GetReadyState() が返した生の状態名。
    std::wstring rawState;
    // CapabilityMissing状態、またはhresult_access_deniedが観測されたか。
    bool capabilityMissingObserved = false;
    // 観測できた場合の詳細(SpikeError::Describe())。
    std::wstring detail;
};

CapabilityCheckResult CheckCapability();

}  // namespace wsspike
