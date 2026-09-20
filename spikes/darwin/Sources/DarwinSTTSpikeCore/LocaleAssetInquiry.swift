// LocaleAssetInquiry.swift
// Issue #7: ロケール・アセット照会。
// design.md §4.2「モデル管理: AssetInventoryでlocaleのアセット状態を照会・取得要求。FR-1/FR-2に写像」に対応する
// 最初の調査ステップ。

import Foundation
import Speech

/// Issue #7 の照会結果。JSON化してRESULTS.mdへの転記に使う。
public struct LocaleInquiryResult: Codable, Sendable {
    public let isAvailable: Bool
    public let supportedLocaleCount: Int
    public let supportedLocales: [String]      // BCP-47、ソート済み
    public let installedLocales: [String]      // BCP-47、ソート済み
    public let jaLocales: [String]             // 言語コードが "ja" のエントリ
    public let equivalentToJaJP: String?
    public let assetStatusForJaJP: String
    public let maximumReservedLocales: Int
    public let reservedLocales: [String]
    /// `.supported` と `installedLocales` の不整合を検出した場合の警告文。無ければ nil。
    public let statusInstalledMismatchWarning: String?
}

@available(macOS 26.0, iOS 26.0, *)
public enum LocaleAssetInquiry {
    public static func run() async -> LocaleInquiryResult {
        let isAvail = SpeechTranscriber.isAvailable
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let ja = supported.filter { $0.language.languageCode?.identifier == "ja" }
        let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP"))

        // status(forModules:) を呼ぶには SpeechTranscriber インスタンスが必要。
        // 実際に使う preset とは無関係にロケール照会用途なので .transcription を使う。
        let jaJPTranscriber = SpeechTranscriber(
            locale: equivalent ?? Locale(identifier: "ja-JP"),
            preset: .transcription
        )
        let status = await AssetInventory.status(forModules: [jaJPTranscriber])
        let maxReserved = AssetInventory.maximumReservedLocales
        let reserved = await AssetInventory.reservedLocales

        let installedBcp47 = Set(installed.map(bcp47))
        var warning: String? = nil
        if installedBcp47.contains("ja-JP") && status != .installed {
            warning = "installedLocalesにja-JPが含まれているにもかかわらず、AssetInventory.status(forModules:)は" +
                ".installedではなく.\(status)を返した。FR-1の状態写像(available/downloadable/downloading/unavailable)は" +
                "installedLocalesとstatusのいずれか一方のみに単純追従すると誤判定しうるため、両方を突き合わせる必要がある。"
        }

        return LocaleInquiryResult(
            isAvailable: isAvail,
            supportedLocaleCount: supported.count,
            supportedLocales: supported.map(bcp47).sorted(),
            installedLocales: installed.map(bcp47).sorted(),
            jaLocales: ja.map(bcp47).sorted(),
            equivalentToJaJP: equivalent.map(bcp47),
            assetStatusForJaJP: "\(status)",
            maximumReservedLocales: maxReserved,
            reservedLocales: reserved.map(bcp47).sorted(),
            statusInstalledMismatchWarning: warning
        )
    }
}
