// OfflineSttApiImpl.swift
// `OfflineSttHostApi`(Pigeon生成、Pigeon.g.swift)の実装本体。
// design.md §4.2、requirements.md FR-1〜FR-3 FR-6(Issue #33〜#39)に対応する。
//
// ## 同期プロトコルと非同期Speech APIの橋渡しについて
// `pigeons/offline_stt_events.dart` の `checkModel` には `@async` を
// 付与しているため、Pigeonが生成するSwiftプロトコルは
// `completion: @escaping (Result<ModelState, Error>) -> Void` を受け取る
// 非同期シグネチャである。これにより `AssetInventory` / `SpeechTranscriber`
// のSwift ConcurrencyのasyncAPIを、Flutterのプラットフォームスレッドを
// ブロックせずに`Task`経由でそのまま呼び出せる(以前は`SyncBridge.swift`の
// `runBlocking`でスレッドをブロックしていたが、ANR・デッドロックの危険が
// あるため廃止した)。
// - `downloadModel` / `transcribeFile` / `cancel` は「開始のみ」を表す
//   契約(`pigeons/offline_stt_events.dart`の各メソッドのドキュメント
//   コメント参照)であり `@async` を付与していないため、引き続き同期
//   シグネチャ(`throws`)である。`Task`を起動して即座に返り、結果は
//   `segments` / `downloadProgress` のEventChannelで非同期に配信する。
#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif
import Foundation
import Speech

final class OfflineSttApiImpl: NSObject, OfflineSttHostApi {
  private let segmentsWrapper: SegmentsEventWrapper
  private let downloadProgressWrapper: DownloadProgressEventWrapper

  private var currentTranscriptionTask: Task<Void, Never>?
  private var currentDownloadTask: Task<Void, Never>?

  init(segmentsWrapper: SegmentsEventWrapper, downloadProgressWrapper: DownloadProgressEventWrapper) {
    self.segmentsWrapper = segmentsWrapper
    self.downloadProgressWrapper = downloadProgressWrapper
  }

  // MARK: - OfflineSttHostApi (#34 #35)

  func checkModel(locale: String, completion: @escaping (Result<ModelState, Error>) -> Void) {
    // #34 OSバージョンゲート: 26未満では`unavailable`を返す。`if #available`
    // による分岐のため、パッケージ全体は26未満でもコンパイルが通る
    // (design.md §4.2)。
    guard #available(macOS 26.0, iOS 26.0, *) else {
      completion(.success(.unavailable))
      return
    }
    Task {
      let state = await ModelAvailability.checkModel(localeIdentifier: locale)
      completion(.success(state))
    }
  }

  func supportedLocales(completion: @escaping (Result<[String], Error>) -> Void) {
    // OSバージョンゲート。`checkModel` は26未満で `unavailable`(FR-1の
    // 終端状態)を返せるが、一覧には「対応ロケールが無い」を表す正しい値が
    // 無いため、ここは明示的なエラーにする(空配列は「このOSは1言語も
    // 扱えない」と誤解されるため返さない)。
    guard #available(macOS 26.0, iOS 26.0, *) else {
      completion(
        .failure(
          DarwinTranscribeError.deviceUnsupported(
            "対応ロケールの列挙には macOS 26 / iOS 26 以上が必要である。"
          ).asPigeonError))
      return
    }
    Task {
      do {
        completion(.success(try await ModelAvailability.supportedLocales()))
      } catch let error as DarwinTranscribeError {
        completion(.failure(error.asPigeonError))
      } catch {
        completion(.failure(DarwinTranscribeError.platformError("\(error)").asPigeonError))
      }
    }
  }

  func downloadModel(locale: String) throws {
    guard #available(macOS 26.0, iOS 26.0, *) else {
      // design.md §3細則3: downloadable以外(ここではOS非対応=unavailable)
      // で呼ばれた場合は、状態を変化させず何もemitせず完了する。
      downloadProgressWrapper.sendEndOfStream()
      return
    }
    currentDownloadTask?.cancel()
    currentDownloadTask = Task { [weak self] in
      await self?.runDownload(locale: locale)
    }
  }

  func transcribeFile(request: TranscribeRequest) throws {
    guard #available(macOS 26.0, iOS 26.0, *) else {
      segmentsWrapper.sendError(.deviceUnsupported("OS 26未満"))
      return
    }
    // design.md §3の同時セッション排他(v1では1本まで)はDart側
    // `TranscribeSessionGuard`が担うため、通常この時点で前のTaskが
    // 生きていることはない。念のため多重起動を防ぐ。
    currentTranscriptionTask?.cancel()
    currentTranscriptionTask = Task { [weak self] in
      await self?.runTranscription(request: request)
    }
  }

  func cancel() throws {
    currentTranscriptionTask?.cancel()
    currentDownloadTask?.cancel()
  }

  /// `segments` EventChannel自体がキャンセルされた場合の保険
  /// (EventChannelWrappers.swift のドキュメントコメント参照)。
  ///
  /// 停止するのは文字起こしTaskのみである。2本のEventChannelは独立して
  /// いるため、片方の購読解除でもう片方を巻き添えにしてはならない
  /// (例: ja-JPの文字起こし中にen-USのダウンロードStreamの購読を
  /// 解除しても、文字起こしは継続しなければならない)。明示的な
  /// `cancel()` HostApiは従来どおり両方を停止する。
  func cancelTranscriptionFromEventChannel() {
    currentTranscriptionTask?.cancel()
  }

  /// `downloadProgress` EventChannel自体がキャンセルされた場合の保険。
  /// 停止するのはダウンロードTaskのみである(理由は
  /// `cancelTranscriptionFromEventChannel()` のコメント参照)。
  func cancelDownloadFromEventChannel() {
    currentDownloadTask?.cancel()
  }

  // MARK: - ダウンロード(#35)

  @available(macOS 26.0, iOS 26.0, *)
  private func runDownload(locale: String) async {
    // design.md §3細則3: downloadable以外で呼ばれた場合は状態を変化させず
    // 何もemitせず完了する。
    let state = await ModelAvailability.checkModel(localeIdentifier: locale)
    guard state == .downloadable else {
      downloadProgressWrapper.sendEndOfStream()
      return
    }

    downloadProgressWrapper.send(fraction: 0.0, completed: false)
    do {
      try await ModelAcquisition.run(localeIdentifier: locale) { [weak self] fraction in
        self?.downloadProgressWrapper.send(fraction: fraction, completed: false)
      }
      downloadProgressWrapper.send(fraction: 1.0, completed: true)
      downloadProgressWrapper.sendEndOfStream()
    } catch let error as DarwinTranscribeError {
      downloadProgressWrapper.sendError(error)
      downloadProgressWrapper.sendEndOfStream()
    } catch is CancellationError {
      downloadProgressWrapper.sendError(.cancelled)
      downloadProgressWrapper.sendEndOfStream()
    } catch {
      downloadProgressWrapper.sendError(.platformError("\(error)"))
      downloadProgressWrapper.sendEndOfStream()
    }
  }

  // MARK: - 文字起こし(#36 #37 #38)

  @available(macOS 26.0, iOS 26.0, *)
  private func runTranscription(request: TranscribeRequest) async {
    // design.md §2.2: `playbackRate`はWeb専用オプションであり、Darwinでは
    // 無視する。`pigeons/offline_stt_events.dart`のTranscribeRequestに
    // そもそも`playbackRate`フィールドが存在しない(現行ブランチのPigeon
    // スキーマにはPR#74で追加予定のplaybackRateが未反映であるため)ため、
    // 本メソッドの引数`request`は元々`path`/`locale`のみで構成されており、
    // 無視は自動的に満たされる。
    let session = TranscriptionSession(
      localeIdentifier: request.locale,
      filePath: request.path,
      onSegment: { [weak self] segment in
        self?.segmentsWrapper.send(segment)
      }
    )
    do {
      try await session.run()
      segmentsWrapper.sendEndOfStream()
    } catch let error as DarwinTranscribeError {
      segmentsWrapper.sendError(error)
    } catch is CancellationError {
      segmentsWrapper.sendError(.cancelled)
    } catch {
      segmentsWrapper.sendError(.platformError("\(error)"))
    }
  }
}
