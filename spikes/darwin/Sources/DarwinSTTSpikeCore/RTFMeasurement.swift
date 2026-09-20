// RTFMeasurement.swift
// Issue #9: RTF(Real Time Factor)計測。
// RTF = 処理時間 ÷ 音声の実時間長。ウォームアップ実行を1回行ってから計測を3回実行し、
// 各回の値と中央値を記録する(NFR-1: ファイル処理速度の実測に対応)。

import Foundation

public struct RTFMeasurement: Codable, Sendable {
    public let clipId: String
    public let audioDurationSeconds: Double
    public let warmupElapsedSeconds: Double
    public let warmupRTF: Double
    public let runElapsedSeconds: [Double]
    public let runRTFs: [Double]
    public let medianRTF: Double
}

@available(macOS 26.0, iOS 26.0, *)
public enum RTFBenchmark {
    /// ウォームアップ1回 + 計測3回を実行する。最後の計測実行の `TranscriptionRunResult` を
    /// キーワード包含率スコアリング(Issue #6相当)にそのまま再利用するため、あわせて返す。
    public static func run(
        clipId: String,
        fileURL: URL,
        localeIdentifier: String
    ) async throws -> (measurement: RTFMeasurement, lastRun: TranscriptionRunResult) {
        let warmup = try await Transcription.run(fileURL: fileURL, localeIdentifier: localeIdentifier)
        let audioDuration = warmup.audioDurationSeconds

        var elapsedList: [Double] = []
        var lastRun = warmup
        for _ in 0..<3 {
            let result = try await Transcription.run(fileURL: fileURL, localeIdentifier: localeIdentifier)
            elapsedList.append(result.elapsedSeconds)
            lastRun = result
        }

        let rtfs = elapsedList.map { $0 / audioDuration }
        let sortedRtfs = rtfs.sorted()
        let median = sortedRtfs[sortedRtfs.count / 2]

        let measurement = RTFMeasurement(
            clipId: clipId,
            audioDurationSeconds: audioDuration,
            warmupElapsedSeconds: warmup.elapsedSeconds,
            warmupRTF: warmup.elapsedSeconds / audioDuration,
            runElapsedSeconds: elapsedList,
            runRTFs: rtfs,
            medianRTF: median
        )
        return (measurement, lastRun)
    }
}
