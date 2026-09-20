// ModelAcquisition.swift
// モデル取得(FR-2写像の検討材料)。
// AssetInventory.status が .installed でない場合に assetInstallationRequest(supporting:) を呼び、
// downloadAndInstall() の所要時間を計測する。あわせて reserve(locale:) / release(reservedLocale:) の
// 挙動も記録し、FR-1/FR-2 の状態写像検討材料とする(design.md §4.2, §8未決事項3関連)。

import Foundation
import Speech

public struct ModelAcquisitionResult: Codable, Sendable {
    public let localeIdentifier: String
    public let resolvedLocale: String?
    public let statusBefore: String
    public let requestObtained: Bool?          // nil = 既に.installedのため要求自体を行わなかった
    public let downloadAndInstallElapsedSeconds: Double?
    public let statusAfter: String
    public let reservedLocalesBeforeReserve: [String]
    public let reserveSucceeded: Bool?
    public let reservedLocalesAfterReserve: [String]
    public let releaseSucceeded: Bool?
    public let reservedLocalesAfterRelease: [String]
    public let error: String?
}

@available(macOS 26.0, iOS 26.0, *)
public enum ModelAcquisition {
    public static func run(localeIdentifier: String) async -> ModelAcquisitionResult {
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)) else {
            return ModelAcquisitionResult(
                localeIdentifier: localeIdentifier,
                resolvedLocale: nil,
                statusBefore: "n/a",
                requestObtained: nil,
                downloadAndInstallElapsedSeconds: nil,
                statusAfter: "n/a",
                reservedLocalesBeforeReserve: [],
                reserveSucceeded: nil,
                reservedLocalesAfterReserve: [],
                releaseSucceeded: nil,
                reservedLocalesAfterRelease: [],
                error: DarwinSpikeError.localeUnsupported(localeIdentifier).description
            )
        }

        let transcriber = SpeechTranscriber(locale: resolved, preset: .transcription)
        let statusBefore = await AssetInventory.status(forModules: [transcriber])

        var requestObtained: Bool? = nil
        var elapsed: Double? = nil
        var errorMessage: String? = nil

        if statusBefore != .installed {
            requestObtained = false
            let clock = ContinuousClock()
            let start = clock.now
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    requestObtained = true
                    try await request.downloadAndInstall()
                }
            } catch {
                errorMessage = DarwinSpikeError.assetUnavailable("\(error)").description
            }
            elapsed = start.duration(to: clock.now).asSeconds
        }

        let statusAfter = await AssetInventory.status(forModules: [transcriber])

        let reservedBefore = await AssetInventory.reservedLocales
        var reserveOk: Bool? = nil
        var reservedAfterReserve = reservedBefore
        var releaseOk: Bool? = nil
        var reservedAfterRelease = reservedBefore
        do {
            reserveOk = try await AssetInventory.reserve(locale: resolved)
            reservedAfterReserve = await AssetInventory.reservedLocales
        } catch {
            errorMessage = (errorMessage.map { $0 + " / " } ?? "") + "reserve(locale:) error: \(error)"
        }
        // reserve(locale:) は既に予約済みの場合 false を返す(エラーにはならない)ことを確認済みのため、
        // release(reservedLocale:) の挙動を観測するために reserveOk の真偽にかかわらず呼び出す。
        releaseOk = await AssetInventory.release(reservedLocale: resolved)
        reservedAfterRelease = await AssetInventory.reservedLocales

        return ModelAcquisitionResult(
            localeIdentifier: localeIdentifier,
            resolvedLocale: bcp47(resolved),
            statusBefore: "\(statusBefore)",
            requestObtained: requestObtained,
            downloadAndInstallElapsedSeconds: elapsed,
            statusAfter: "\(statusAfter)",
            reservedLocalesBeforeReserve: reservedBefore.map(bcp47).sorted(),
            reserveSucceeded: reserveOk,
            reservedLocalesAfterReserve: reservedAfterReserve.map(bcp47).sorted(),
            releaseSucceeded: releaseOk,
            reservedLocalesAfterRelease: reservedAfterRelease.map(bcp47).sorted(),
            error: errorMessage
        )
    }
}
