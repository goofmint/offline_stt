// CLI.swift
// エントリポイント本体。サブコマンドで「ロケール照会のみ」「1クリップ文字起こし」「全クリップ実行」を
// 選べるようにする。加えて「model」サブコマンドでモデル取得(Issue B相当)単体も実行できる。
//
// OSバージョンゲート: design.md §4.2 のとおり `if #available(macOS 26.0, iOS 26.0, *)` で分岐し、
// 26未満では unavailable 相当を出力して終了する。本パッケージの Package.swift 自体は
// `.macOS(.v26)/.iOS(.v26)` を最低デプロイメントターゲットとして宣言しているため、この分岐は
// このスパイク単体では実質的に常に真になるが、design.mdが要求する「下位OSでもコンパイルが通る構成」を
// 満たすコード構造(将来M2の実パッケージへ本ソースを移植する際にそのまま意味を持つ構造)として維持する。

import Foundation
import DarwinSTTSpikeCore
import Speech

enum CLI {
    static func run() async {
        // バックグラウンド実行時に進捗を逐次確認できるよう、標準出力を無バッファ化する。
        setvbuf(stdout, nil, _IONBF, 0)

        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let subcommand = arguments.first else {
            printUsage()
            exit(64) // EX_USAGE
        }
        let rest = Array(arguments.dropFirst())

        guard #available(macOS 26.0, iOS 26.0, *) else {
            let message = "unavailable: \(DarwinSpikeError.osVersionUnsupported.description)"
            print(message)
            if rest.contains("--json") {
                print("{\"error\": \"\(message)\"}")
            }
            exit(1)
        }

        switch subcommand {
        case "locales":
            await runLocales(args: rest)
        case "model":
            await runModel(args: rest)
        case "transcribe":
            await runTranscribe(args: rest)
        case "all":
            await runAll(args: rest)
        default:
            printUsage()
            exit(64)
        }
    }

    private static func printUsage() {
        print("""
        使い方: darwin-stt-spike <subcommand> [options]

        subcommands:
          locales                                  ロケール・アセット照会のみ(Issue #7)
          model [--locale <bcp47>]                 モデル取得(Issue #7/#8前提の資産確保)
          transcribe <clipId> [--format wav|m4a]    1クリップの文字起こし(Issue #8)
          all                                       test-assets/baseline-audio の全8ファイルを実行
                                                     (Issue #8/#9/#6相当をまとめて実行)

        共通オプション:
          --json                 機械可読JSONを追加出力する
          --baseline-dir <path>  test-assets/baseline-audio の場所を明示指定する
          --timeout <seconds>    all サブコマンドの1クリップあたりの最大実行秒数(既定600秒)
        """)
    }

    // MARK: - locales

    @available(macOS 26.0, iOS 26.0, *)
    private static func runLocales(args: [String]) async {
        let result = await LocaleAssetInquiry.run()
        print("=== Issue #7: ロケール・アセット照会 ===")
        print("isAvailable: \(result.isAvailable)")
        print("supportedLocales (\(result.supportedLocaleCount)件): \(result.supportedLocales.joined(separator: ", "))")
        print("installedLocales: \(result.installedLocales.joined(separator: ", "))")
        print("jaLocales: \(result.jaLocales.joined(separator: ", "))")
        print("supportedLocale(equivalentTo: ja-JP): \(result.equivalentToJaJP ?? "nil")")
        print("AssetInventory.status(ja-JP): \(result.assetStatusForJaJP)")
        print("AssetInventory.maximumReservedLocales: \(result.maximumReservedLocales)")
        print("AssetInventory.reservedLocales: \(result.reservedLocales.joined(separator: ", "))")
        if let warning = result.statusInstalledMismatchWarning {
            print("[警告] \(warning)")
        }
        if args.contains("--json") {
            print(JSONReporter.encode(result))
        }
    }

    // MARK: - model

    @available(macOS 26.0, iOS 26.0, *)
    private static func runModel(args: [String]) async {
        let locale = optionValue(args, name: "--locale") ?? "ja-JP"
        let result = await ModelAcquisition.run(localeIdentifier: locale)
        print("=== モデル取得: \(locale) ===")
        print("resolvedLocale: \(result.resolvedLocale ?? "nil")")
        print("statusBefore: \(result.statusBefore)")
        print("requestObtained: \(result.requestObtained.map { "\($0)" } ?? "n/a(既にinstalled)")")
        print("downloadAndInstallElapsedSeconds: \(result.downloadAndInstallElapsedSeconds.map { String(format: "%.3f", $0) } ?? "n/a")")
        print("statusAfter: \(result.statusAfter)")
        print("reservedLocales(reserve前): \(result.reservedLocalesBeforeReserve.joined(separator: ", "))")
        print("reserve(locale:) succeeded: \(result.reserveSucceeded.map { "\($0)" } ?? "n/a")")
        print("reservedLocales(reserve後): \(result.reservedLocalesAfterReserve.joined(separator: ", "))")
        print("release(reservedLocale:) succeeded: \(result.releaseSucceeded.map { "\($0)" } ?? "n/a")")
        print("reservedLocales(release後): \(result.reservedLocalesAfterRelease.joined(separator: ", "))")
        if let error = result.error {
            print("[エラー] \(error)")
        }
        if args.contains("--json") {
            print(JSONReporter.encode(result))
        }
    }

    // MARK: - transcribe

    @available(macOS 26.0, iOS 26.0, *)
    private static func runTranscribe(args: [String]) async {
        guard let clipId = args.first(where: { !$0.hasPrefix("--") }) else {
            print("エラー: clipId を指定してください(例: jaJP_10s)")
            exit(64)
        }
        let format = optionValue(args, name: "--format") ?? "wav"
        let baselineDirOverride = optionValue(args, name: "--baseline-dir")
        // 既定はpartial観測のための.progressiveTranscription。--preset standard で
        // 非progressiveの.transcriptionへ切り替え、精度比較の参考値を取れるようにする。
        let presetName = optionValue(args, name: "--preset") ?? "progressive"
        // 未知の値を既定へ暗黙フォールバックさせない。出力に記録される preset 名と
        // 実際に使用した Preset が食い違うと、測定条件の記録が誤りになるため。
        let preset: SpeechTranscriber.Preset
        switch presetName {
        case "progressive":
            preset = .progressiveTranscription
        case "standard":
            preset = .transcription
        default:
            print("エラー: --preset は progressive または standard を指定すること(指定値: \(presetName))")
            exit(64)
        }

        guard let baselineDir = BaselineAudioLocator.resolve(explicit: baselineDirOverride) else {
            print("エラー: test-assets/baseline-audio が見つからない")
            exit(1)
        }
        guard let clipRef = BaselineClipRef.all.first(where: { $0.id == clipId }) else {
            print("エラー: 未知のclipId: \(clipId)(候補: \(BaselineClipRef.all.map(\.id).joined(separator: ", ")))")
            exit(64)
        }

        let fileURL = baselineDir.appendingPathComponent("\(clipId).\(format)")
        let jsonURL = baselineDir.appendingPathComponent("\(clipId).json")

        print("=== Issue #8: 文字起こし(\(clipId).\(format), preset=\(presetName)) ===")
        do {
            let clipData = try Data(contentsOf: jsonURL)
            let clip = try JSONDecoder().decode(BaselineClip.self, from: clipData)

            let result = try await Transcription.run(fileURL: fileURL, localeIdentifier: clipRef.localeIdentifier, preset: preset)
            print("audioDurationSeconds: \(String(format: "%.3f", result.audioDurationSeconds))")
            print("elapsedSeconds: \(String(format: "%.3f", result.elapsedSeconds))")
            print("RTF: \(String(format: "%.3f", result.elapsedSeconds / result.audioDurationSeconds))")
            print("finalSegmentCount: \(result.finalSegmentCount)")
            print("partialSegmentCount: \(result.partialSegmentCount)")
            print("analyzerReturnedTimeSeconds: \(result.analyzerReturnedTime.map { String(format: "%.3f", $0) } ?? "nil")")
            print("認識結果テキスト:")
            print(result.finalText)

            let score = KeywordScoring.score(recognizedText: result.finalText, clip: clip)
            print("--- キーワード包含率 ---")
            print("matchRate: \(String(format: "%.1f", score.matchRate * 100))% (\(score.matchedKeywords.count)/\(score.totalKeywords))")
            print("verdict: \(score.verdict)")
            print("matched: \(score.matchedKeywords.joined(separator: ", "))")
            print("unmatched: \(score.unmatchedKeywords.joined(separator: ", "))")

            if args.contains("--json") {
                let output = ClipRunOutput(
                    clipId: clipId,
                    format: format,
                    locale: clip.locale,
                    filePath: fileURL.path,
                    audioDurationSeconds: result.audioDurationSeconds,
                    runElapsedSeconds: [result.elapsedSeconds],
                    runRTFs: [result.elapsedSeconds / result.audioDurationSeconds],
                    finalSegmentCount: result.finalSegmentCount,
                    partialSegmentCount: result.partialSegmentCount,
                    analyzerReturnedTimeSeconds: result.analyzerReturnedTime,
                    recognizedText: result.finalText,
                    keywordScore: score
                )
                print(JSONReporter.encode(output))
            }
        } catch let error as DarwinSpikeError {
            print("[エラー] \(error.description)")
            exit(1)
        } catch {
            print("[エラー] \(error)")
            exit(1)
        }
    }

    // MARK: - all

    @available(macOS 26.0, iOS 26.0, *)
    private static func runAll(args: [String]) async {
        let baselineDirOverride = optionValue(args, name: "--baseline-dir")
        let timeoutSeconds = optionValue(args, name: "--timeout").flatMap(Double.init) ?? 600.0
        let jsonOutput = args.contains("--json")

        guard let baselineDir = BaselineAudioLocator.resolve(explicit: baselineDirOverride) else {
            print("エラー: test-assets/baseline-audio が見つからない")
            exit(1)
        }

        print("=== M0 Darwinスパイク: 全クリップ実行 ===")
        print("baselineDir: \(baselineDir.path)")
        print("timeoutSeconds(1クリップあたり): \(timeoutSeconds)")
        print()

        print("--- ロケール・アセット照会(Issue #7) ---")
        let localeInquiry = await LocaleAssetInquiry.run()
        print("isAvailable=\(localeInquiry.isAvailable) supportedLocales=\(localeInquiry.supportedLocales.count)件 installedLocales=\(localeInquiry.installedLocales)")
        if let warning = localeInquiry.statusInstalledMismatchWarning {
            print("[警告] \(warning)")
        }
        print()

        print("--- モデル取得(ja-JP) ---")
        let modelAcquisition = await ModelAcquisition.run(localeIdentifier: "ja-JP")
        print("statusBefore=\(modelAcquisition.statusBefore) statusAfter=\(modelAcquisition.statusAfter) elapsed=\(modelAcquisition.downloadAndInstallElapsedSeconds.map { String(format: "%.3f", $0) } ?? "n/a")")
        print()

        var clipOutputs: [ClipRunOutput] = []

        for clipRef in BaselineClipRef.all {
            for format in BaselineClipRef.formats {
                let clipId = clipRef.id
                let fileURL = baselineDir.appendingPathComponent("\(clipId).\(format)")
                let jsonURL = baselineDir.appendingPathComponent("\(clipId).json")
                print("--- \(clipId).\(format) ---")

                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("[スキップ] ファイルが存在しない: \(fileURL.path)")
                    clipOutputs.append(ClipRunOutput(clipId: clipId, format: format, locale: clipRef.localeIdentifier, filePath: fileURL.path, error: "file not found"))
                    continue
                }

                do {
                    let clipData = try Data(contentsOf: jsonURL)
                    let clip = try JSONDecoder().decode(BaselineClip.self, from: clipData)

                    let localeIdentifier = clipRef.localeIdentifier
                    let (measurement, lastRun) = try await withTimeout(seconds: timeoutSeconds) {
                        try await RTFBenchmark.run(clipId: clipId, fileURL: fileURL, localeIdentifier: localeIdentifier)
                    }

                    let score = KeywordScoring.score(recognizedText: lastRun.finalText, clip: clip)

                    print("audioDurationSeconds=\(String(format: "%.2f", measurement.audioDurationSeconds)) warmup=\(String(format: "%.2f", measurement.warmupElapsedSeconds))s runs=\(measurement.runElapsedSeconds.map { String(format: "%.2f", $0) }) RTFs=\(measurement.runRTFs.map { String(format: "%.3f", $0) }) median=\(String(format: "%.3f", measurement.medianRTF))")
                    print("keyword matchRate=\(String(format: "%.1f", score.matchRate * 100))% verdict=\(score.verdict) unmatched=\(score.unmatchedKeywords)")
                    print("recognizedText: \(lastRun.finalText)")

                    clipOutputs.append(ClipRunOutput(
                        clipId: clipId,
                        format: format,
                        locale: clip.locale,
                        filePath: fileURL.path,
                        audioDurationSeconds: measurement.audioDurationSeconds,
                        warmupElapsedSeconds: measurement.warmupElapsedSeconds,
                        runElapsedSeconds: measurement.runElapsedSeconds,
                        runRTFs: measurement.runRTFs,
                        medianRTF: measurement.medianRTF,
                        finalSegmentCount: lastRun.finalSegmentCount,
                        partialSegmentCount: lastRun.partialSegmentCount,
                        analyzerReturnedTimeSeconds: lastRun.analyzerReturnedTime,
                        recognizedText: lastRun.finalText,
                        keywordScore: score
                    ))
                } catch let error as DarwinSpikeError {
                    print("[エラー] \(error.description)")
                    clipOutputs.append(ClipRunOutput(clipId: clipId, format: format, locale: clipRef.localeIdentifier, filePath: fileURL.path, error: error.description))
                } catch {
                    print("[エラー] \(error)")
                    clipOutputs.append(ClipRunOutput(clipId: clipId, format: format, locale: clipRef.localeIdentifier, filePath: fileURL.path, error: "\(error)"))
                }
                print()
            }
        }

        if jsonOutput {
            let formatter = ISO8601DateFormatter()
            let report = AllRunReport(
                generatedAt: formatter.string(from: Date()),
                localeInquiry: localeInquiry,
                modelAcquisition: modelAcquisition,
                clips: clipOutputs
            )
            print("=== JSON ===")
            print(JSONReporter.encode(report))
        }
    }

    // MARK: - helpers

    private static func optionValue(_ args: [String], name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
