// ModelAcquisition.swift
// #35 モデル管理(取得要求)。requirements.md FR-2、design.md §4.2に対応する。
// spikes/darwin/Sources/DarwinSTTSpikeCore/ModelAcquisition.swift の
// 検証結果(`assetInstallationRequest` → `downloadAndInstall()`)を移植の
// 出発点とした。
//
// ## 進捗報告について(design.md未記載、本実装での判断)
//
// design.md §4.4(Windows)・§4.1(Web)はいずれも進捗の粒度が粗く
// `DownloadProgress(fraction: null)` の不定進捗として扱うと明記している。
// Darwinについてdesign.mdは進捗報告の粒度に触れていない。
//
// 本実装時にSDK調査(`swift-api-digester -dump-sdk`、2026-09-20)で
// `AssetInventory.AssetInstallationRequest.progress` が `Foundation.Progress`
// (NSProgress)型であることを確認した。spikes/darwin/RESULTS.mdはこの
// プロパティを検証していない(M0スパイクはdownloadAndInstall()の所要時間
// 計測のみを行った)が、`Progress.fractionCompleted` をKVOで観測すること
// で、Windows/Webとは異なり実際の進捗率を`DownloadProgress.fraction`へ
// 反映できる。これはdesign.mdに矛盾しない拡張であるため採用する。
import Foundation
import Speech

@available(macOS 26.0, iOS 26.0, *)
enum ModelAcquisition {
  /// requirements.md FR-2。
  ///
  /// 呼び出し前提: design.md §3細則3のとおり、呼び出し元
  /// (`OfflineSttApiImpl.runDownload`)は事前に`ModelAvailability.checkModel`
  /// で`downloadable`であることを確認してから本関数を呼び出す。本関数
  /// 自体は「downloadable以外なら何もしない」制御は持たない(呼び出し前提の
  /// 確認は呼び出し元の責務とすることで、本関数を素直な「取得を実行する」
  /// 処理として保てるようにしている)。
  ///
  /// - Parameter onProgress: `Progress.fractionCompleted`(0.0〜1.0)を
  ///   都度通知するコールバック。呼ばれるスレッドは保証しないため、
  ///   呼び出し側でメインスレッドへのdispatchを行うこと
  ///   (design.md §6、`OfflineSttApiImpl`参照)。
  static func run(
    localeIdentifier: String,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    guard SpeechTranscriber.isAvailable else {
      throw DarwinTranscribeError.modelUnavailable("SpeechTranscriber.isAvailable = false")
    }
    guard let resolved = await ModelAvailability.resolveLocale(localeIdentifier) else {
      throw DarwinTranscribeError.localeUnsupported(localeIdentifier)
    }

    let transcriber = SpeechTranscriber(locale: resolved, preset: TranscriptionPreset.selected)
    let status = await AssetInventory.status(forModules: [transcriber])
    if status == .installed {
      onProgress(1.0)
      return
    }

    let request: AssetInstallationRequest?
    do {
      request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
    } catch is CancellationError {
      throw DarwinTranscribeError.cancelled
    } catch {
      throw DarwinTranscribeError.modelUnavailable(
        "assetInstallationRequest(supporting:) failed: \(error)"
      )
    }

    guard let request else {
      // `assetInstallationRequest` が `nil` を返すのは、要求時点で既に
      // 取得済み(=追加の取得要求が不要)であることを意味する
      // (Speechフレームワークの契約)。
      onProgress(1.0)
      return
    }

    let progressObservation = request.progress.observe(\.fractionCompleted, options: [.new]) {
      progress, _ in
      onProgress(progress.fractionCompleted)
    }
    defer { progressObservation.invalidate() }

    do {
      try await request.downloadAndInstall()
    } catch is CancellationError {
      throw DarwinTranscribeError.cancelled
    } catch {
      throw DarwinTranscribeError.modelUnavailable(
        "downloadAndInstall() failed: \(error)"
      )
    }
    onProgress(1.0)
  }
}
