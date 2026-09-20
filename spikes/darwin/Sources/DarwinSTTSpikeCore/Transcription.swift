// Transcription.swift
// Issue #8: 文字起こしパイプライン(design.md §4.2 Darwin に忠実に実装)。
//
// AVAudioFile(forReading:) → SpeechAnalyzer + SpeechTranscriber(locale指定)
//   → analyzeSequence(from:) でファイルを流し込み、transcriber.results の AsyncSequence を
//     並行 Task で消費して volatile(partial) / final を isFinal で区別する。
//
// preset選択理由:
//   design.md の TranscriptSegment は isFinal で partial/final を区別する設計であり、本スパイクでも
//   partial(volatile)結果を実際に観測できるかを確認したい。Speech.swiftinterface で確認できる
//   SpeechTranscriber.Preset は次の5種:
//     .transcription / .transcriptionWithAlternatives /
//     .timeIndexedTranscriptionWithAlternatives /
//     .progressiveTranscription / .timeIndexedProgressiveTranscription
//   このうち名称上 "progressive" を含むものが逐次(volatile)結果の提供を意図したプリセットと判断し、
//   `.progressiveTranscription` を採用する(reportingOptionsの内部構成はSDK非公開のため、
//   実行結果のpartialCountが0か否かで実際にvolatileが得られているかをRESULTS.mdに記録する)。

import Foundation
import AVFoundation
import CoreMedia
import Speech

public struct TranscriptionRunResult: Sendable {
    public let finalText: String
    public let finalSegmentCount: Int
    public let partialSegmentCount: Int
    public let analyzerReturnedTime: Double?     // analyzeSequence(from:) の戻り値(CMTime?)を秒に変換したもの
    public let elapsedSeconds: Double            // このパイプライン全体(認識開始〜finalize完了)の壁時計時間
    public let audioDurationSeconds: Double
}

@available(macOS 26.0, iOS 26.0, *)
public enum Transcription {
    /// 1クリップを1回、最後まで文字起こしする。
    /// design.md §5 のDarwin列エラー分類(ModelUnavailable/LocaleUnsupported/DecodeFailed/
    /// DeviceUnsupported/Cancelled)に対応づけて `DarwinSpikeError` を投げる。
    /// `preset` は既定で `.progressiveTranscription`(partial結果観測のため。ファイル冒頭のコメント参照)。
    /// `.transcription`(非progressive、単一パスの高品質プリセット)との精度比較用に、
    /// CLIの `transcribe --preset standard` から差し替えられるようにしている。
    public static func run(
        fileURL: URL,
        localeIdentifier: String,
        preset: SpeechTranscriber.Preset = .progressiveTranscription
    ) async throws -> TranscriptionRunResult {
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)) else {
            throw DarwinSpikeError.localeUnsupported(localeIdentifier)
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw DarwinSpikeError.decodeFailed("\(fileURL.lastPathComponent): \(error)")
        }

        let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: preset)

        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .unsupported {
            throw DarwinSpikeError.assetUnavailable("AssetInventory.status = .unsupported (locale=\(bcp47(resolvedLocale)))")
        }
        if status != .installed {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            } catch is CancellationError {
                // design.md §5: Darwin の Task cancel は Cancelled に分類する。
                throw DarwinSpikeError.cancelled
            } catch {
                throw DarwinSpikeError.assetUnavailable("assetInstallationRequest/downloadAndInstall failed: \(error)")
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let clock = ContinuousClock()
        let start = clock.now

        let resultsTask = Task<(text: String, finalCount: Int, partialCount: Int), Error> {
            var finalParts: [String] = []
            var finalCount = 0
            var partialCount = 0
            for try await result in transcriber.results {
                if result.isFinal {
                    finalParts.append(String(result.text.characters))
                    finalCount += 1
                } else {
                    partialCount += 1
                }
            }
            return (finalParts.joined(), finalCount, partialCount)
        }

        let returnedTime: CMTime?
        do {
            returnedTime = try await analyzer.analyzeSequence(from: audioFile)
        } catch is CancellationError {
            resultsTask.cancel()
            throw DarwinSpikeError.cancelled
        } catch {
            resultsTask.cancel()
            throw DarwinSpikeError.underlying("analyzeSequence(from:) failed: \(error)")
        }

        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch is CancellationError {
            // design.md §5: Darwin の Task cancel は Cancelled に分類する。
            resultsTask.cancel()
            throw DarwinSpikeError.cancelled
        } catch {
            resultsTask.cancel()
            throw DarwinSpikeError.underlying("finalizeAndFinishThroughEndOfInput() failed: \(error)")
        }

        let collected: (text: String, finalCount: Int, partialCount: Int)
        do {
            collected = try await resultsTask.value
        } catch is CancellationError {
            throw DarwinSpikeError.cancelled
        } catch {
            throw DarwinSpikeError.underlying("results AsyncSequence consumption failed: \(error)")
        }

        let elapsed = start.duration(to: clock.now).asSeconds
        let durationSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        return TranscriptionRunResult(
            finalText: collected.text,
            finalSegmentCount: collected.finalCount,
            partialSegmentCount: collected.partialCount,
            analyzerReturnedTime: returnedTime.map { CMTimeGetSeconds($0) },
            elapsedSeconds: elapsed,
            audioDurationSeconds: durationSeconds
        )
    }
}
