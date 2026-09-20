// CLIReport.swift
// CLI(DarwinSTTSpikeCLI)から使う集計用の出力型。人間可読テキストと機械可読JSONの両方の
// 出力元になる、CLI非依存の共通データ構造。

import Foundation

public struct ClipRunOutput: Codable, Sendable {
    public let clipId: String
    public let format: String
    public let locale: String
    public let filePath: String
    public let error: String?
    public let audioDurationSeconds: Double?
    public let warmupElapsedSeconds: Double?
    public let runElapsedSeconds: [Double]?
    public let runRTFs: [Double]?
    public let medianRTF: Double?
    public let finalSegmentCount: Int?
    public let partialSegmentCount: Int?
    public let analyzerReturnedTimeSeconds: Double?
    public let recognizedText: String?
    public let keywordScore: KeywordScore?

    public init(
        clipId: String,
        format: String,
        locale: String,
        filePath: String,
        error: String? = nil,
        audioDurationSeconds: Double? = nil,
        warmupElapsedSeconds: Double? = nil,
        runElapsedSeconds: [Double]? = nil,
        runRTFs: [Double]? = nil,
        medianRTF: Double? = nil,
        finalSegmentCount: Int? = nil,
        partialSegmentCount: Int? = nil,
        analyzerReturnedTimeSeconds: Double? = nil,
        recognizedText: String? = nil,
        keywordScore: KeywordScore? = nil
    ) {
        self.clipId = clipId
        self.format = format
        self.locale = locale
        self.filePath = filePath
        self.error = error
        self.audioDurationSeconds = audioDurationSeconds
        self.warmupElapsedSeconds = warmupElapsedSeconds
        self.runElapsedSeconds = runElapsedSeconds
        self.runRTFs = runRTFs
        self.medianRTF = medianRTF
        self.finalSegmentCount = finalSegmentCount
        self.partialSegmentCount = partialSegmentCount
        self.analyzerReturnedTimeSeconds = analyzerReturnedTimeSeconds
        self.recognizedText = recognizedText
        self.keywordScore = keywordScore
    }
}

public struct AllRunReport: Codable, Sendable {
    public let generatedAt: String
    public let localeInquiry: LocaleInquiryResult
    public let modelAcquisition: ModelAcquisitionResult
    public let clips: [ClipRunOutput]

    public init(generatedAt: String, localeInquiry: LocaleInquiryResult, modelAcquisition: ModelAcquisitionResult, clips: [ClipRunOutput]) {
        self.generatedAt = generatedAt
        self.localeInquiry = localeInquiry
        self.modelAcquisition = modelAcquisition
        self.clips = clips
    }
}

public enum JSONReporter {
    public static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"json encoding failed\"}"
        }
        return string
    }
}
