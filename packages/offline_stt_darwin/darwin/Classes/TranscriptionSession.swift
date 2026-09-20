// TranscriptionSession.swift
// #36 デコード層、#37 認識セッション、#38 キャンセル。
// design.md §4.2「AVAudioFile(任意フォーマット読込) → AnalyzerInputへ変換 →
// SpeechAnalyzer + SpeechTranscriber(locale指定) → AsyncSequenceの結果を
// EventChannelへ転送」に対応する。
// spikes/darwin/Sources/DarwinSTTSpikeCore/Transcription.swift の検証済み
// パイプラインを移植の出発点とした。
//
// ## AnalyzerInputへの変換について(design.md §4.2の文言との対応)
// design.mdのパイプライン図は「AVAudioFile → AnalyzerInputへ変換」という
// ステップを明示しているが、実際のSpeechフレームワークAPIには
// `SpeechAnalyzer.analyzeSequence(from: AVAudioFile)` という、
// AVAudioFileを直接受け取る簡易オーバーロードが存在する
// (spikes/darwin/RESULTS.mdのIssue #10「パイプラインの技術的成立性」で
// 実機確認済み)。このオーバーロードは内部でAnalyzerInputへの変換を行う
// ため、本実装でも手動でAnalyzerInputを構築する処理は書かず、この
// オーバーロードをそのまま使う。
//
// ## spike版との重要な相違点: 暗黙ダウンロードを行わない
// spikes/darwin/Sources/DarwinSTTSpikeCore/Transcription.swiftは
// `status != .installed` の場合に`assetInstallationRequest` →
// `downloadAndInstall()` を自動実行していた(M0検証を完走させるための
// スパイク独自の振る舞い)。design.md §3「transcribeFile()は
// checkModel()がavailable以外なら即座にModelUnavailableExceptionを
// Streamエラーで返す。内部で暗黙的にモデルをダウンロードしてはならない」
// という細則に反するため、本実装ではこの自動ダウンロードを行わず、
// `available`以外なら即座に失敗させる。
import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(macOS 26.0, iOS 26.0, *)
final class TranscriptionSession {
  private let localeIdentifier: String
  private let filePath: String
  private let onSegment: @Sendable (TranscriptSegment) -> Void

  init(
    localeIdentifier: String,
    filePath: String,
    onSegment: @escaping @Sendable (TranscriptSegment) -> Void
  ) {
    self.localeIdentifier = localeIdentifier
    self.filePath = filePath
    self.onSegment = onSegment
  }

  /// セッション全体を実行する。正常終了時は戻り値なしで返る。
  /// 失敗時(`Cancelled`含む)は`DarwinTranscribeError`を投げる。
  ///
  /// #38 キャンセル: `Task.cancel()`が呼ばれると、`Task.checkCancellation()`
  /// および`analyzer`/`resultsTask`の各awaitが`CancellationError`を投げる。
  /// M0のレビュー指摘(design.md冒頭の指示に明記)を踏まえ、これらすべての
  /// 経路で`CancellationError`を確実に捕捉し`DarwinTranscribeError.cancelled`
  /// へ写像する。
  func run() async throws {
    // design.md §3: available以外なら即座に失敗する。暗黙ダウンロード禁止
    // (ファイル冒頭コメント参照)。呼び出し元(Dart側recognition_session.dart)
    // でも同等の事前チェックを行うが、チェックと呼び出しの間の競合状態
    // (他プロセスがモデルを削除する等)に備え、ネイティブ側でも再度検証する
    // (defense in depth)。
    let state = await ModelAvailability.checkModel(localeIdentifier: localeIdentifier)
    guard state == .available else {
      throw DarwinTranscribeError.modelUnavailable(
        "checkModel()がavailable以外(\(state))の状態でtranscribeFileが呼ばれた"
      )
    }

    guard let resolvedLocale = await ModelAvailability.resolveLocale(localeIdentifier) else {
      throw DarwinTranscribeError.localeUnsupported(localeIdentifier)
    }

    try Task.checkCancellation()

    let fileURL = URL(fileURLWithPath: filePath)
    let audioFile: AVAudioFile
    do {
      audioFile = try AVAudioFile(forReading: fileURL)
    } catch {
      throw DarwinTranscribeError.decodeFailed("\(fileURL.lastPathComponent): \(error)")
    }

    let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: TranscriptionPreset.selected)
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    let onSegment = self.onSegment
    let resultsTask = Task<Void, Error> {
      for try await result in transcriber.results {
        try Task.checkCancellation()
        onSegment(TranscriptSegment(text: String(result.text.characters), isFinal: result.isFinal))
      }
    }

    do {
      _ = try await analyzer.analyzeSequence(from: audioFile)
    } catch is CancellationError {
      resultsTask.cancel()
      _ = try? await resultsTask.value
      throw DarwinTranscribeError.cancelled
    } catch {
      resultsTask.cancel()
      _ = try? await resultsTask.value
      throw DarwinTranscribeError.platformError("analyzeSequence(from:) failed: \(error)")
    }

    do {
      try await analyzer.finalizeAndFinishThroughEndOfInput()
    } catch is CancellationError {
      resultsTask.cancel()
      _ = try? await resultsTask.value
      throw DarwinTranscribeError.cancelled
    } catch {
      resultsTask.cancel()
      _ = try? await resultsTask.value
      throw DarwinTranscribeError.platformError(
        "finalizeAndFinishThroughEndOfInput() failed: \(error)"
      )
    }

    do {
      try await resultsTask.value
    } catch is CancellationError {
      throw DarwinTranscribeError.cancelled
    } catch {
      throw DarwinTranscribeError.platformError(
        "results AsyncSequence consumption failed: \(error)"
      )
    }
  }
}
