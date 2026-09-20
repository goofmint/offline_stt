// ModelAvailability.swift
// #34 OSバージョンゲート、#35 モデル管理(照会)。
// design.md §4.2「モデル管理: AssetInventoryでlocaleのアセット状態を照会・
// 取得要求。FR-1/FR-2に写像」、requirements.md FR-1 に対応する。
// spikes/darwin/Sources/DarwinSTTSpikeCore/LocaleAssetInquiry.swift の
// 検証結果を移植の出発点とした。
//
// ## FR-1(4値)への写像方針
//
// `AssetInventory.status(forModules:)` の実際の値は、本実装時に
// `swift-api-digester -dump-sdk` でSDK(macOS 26.5.1、Xcode 26.6)を直接
// 調査した結果、`.unsupported` / `.supported` / `.downloading` /
// `.installed` の4値であることを確認した(2026-09-20)。これは
// spikes/darwin/RESULTS.mdが照会時点で実際に観測した2値
// (`.supported`/`.installed`)に加え、ドキュメント・スパイクのいずれでも
// 未検証だった `.downloading` の実在を新たに確認できたものである
// (design.md §4.2に不足があった点。本ファイル末尾の齟齬メモも参照)。
//
// 一方でspikes/darwin/RESULTS.md(Issue #7)は、`.installed` が
// ディスク上のアセット永続状態そのものではなく「現在の予約(reserve)状態」
// に連動する一時的な状態であることを実機(macOS・iOS双方)で確認している。
// `SpeechTranscriber.installedLocales` はディスク上の永続状態を表す別軸
// である。そのため `status` だけを見て判定すると、「ディスクにモデルは
// 既に存在するが現在予約されていない」状態を誤って `downloadable` 側へ
// 倒してしまい、ユーザーに不要な再ダウンロード同意を求めることになる。
//
// 本実装は次の優先順位で判定する:
//   1. OSバージョンが26未満 → `unavailable`(#34、呼び出し元で
//      `if #available` により判定。本ファイルの型・関数自体も
//      `@available(macOS 26.0, iOS 26.0, *)` でゲートし、26未満でも
//      パッケージ全体のコンパイルが通るようにしている)
//   2. `SpeechTranscriber.isAvailable == false` → `unavailable`
//      (iOSシミュレータ等、機能自体が無効な環境。
//      spikes/darwin/RESULTS.md「iOSシミュレータでの実行」参照)
//   3. `supportedLocale(equivalentTo:)` が `nil` → `unavailable`
//      (supportedLocales外のロケール。`ModelState`には「対応ロケール外」
//      専用の値が無いため、「端末・OS・ブラウザが対応しておらず利用でき
//      ない状態」という`ModelState.unavailable`の定義〈platform_interface
//      `lib/src/model_state.dart`〉に従いここへ寄せる)
//   4. `status == .downloading` → `downloading`
//   5. `status == .installed` → `available`(予約済みで即座に利用可能)
//   6. `status == .supported` かつ `installedLocales` に解決済みロケール
//      が含まれる → `available`
//      (ディスク上にアセットは既に存在し、予約は文字起こし実行時に暗黙的
//      に行われる。spikes/darwin/RESULTS.mdの
//      「assetInstallationRequest → downloadAndInstall() の呼び出しは、
//      暗黙的に対象ロケールを予約状態にする副作用を持つ」という実測、
//      および同ファイルの「transcribeサブコマンドを実際に実行した直後に
//      再照会するとstatusが.installedへ変化していた」という実測から、
//      既存アセットの再利用(=同じ`assetInstallationRequest`経路を通る)
//      でも同様に暗黙予約されると判断した)
//   7. それ以外(`status == .supported` かつ未インストール、または
//      `status == .unsupported`) → `.supported`のみ`downloadable`、
//      それ以外(`.unsupported`)は`unavailable`
//
// 未知の将来値(`@unknown default`)は`unavailable`へ倒す。これは
// 「フォールバック処理は絶対禁止」というプロジェクト方針が指すもの
// (設定値が取得できない場合に無言でデフォルト値へ逃げること)とは異なり、
// SDKが将来追加するかもしれない列挙値に対して安全側(=利用不可・要確認)
// に倒す一般的なSwiftの前方互換パターンである。

import Foundation
import Speech

@available(macOS 26.0, iOS 26.0, *)
enum ModelAvailability {
  /// requirements.md FR-1。`OfflineSttApiImpl.checkModel` から
  /// `Task` 経由で(スレッドをブロックせず)呼ばれる。
  static func checkModel(localeIdentifier: String) async -> ModelState {
    guard SpeechTranscriber.isAvailable else {
      return .unavailable
    }
    guard let resolved = await resolveLocale(localeIdentifier) else {
      return .unavailable
    }
    let transcriber = SpeechTranscriber(locale: resolved, preset: TranscriptionPreset.selected)
    let status = await AssetInventory.status(forModules: [transcriber])
    switch status {
    case .downloading:
      return .downloading
    case .installed:
      return .available
    case .supported:
      let installed = await SpeechTranscriber.installedLocales
      let installedBcp47 = Set(installed.map { $0.identifier(.bcp47) })
      return installedBcp47.contains(resolved.identifier(.bcp47)) ? .available : .downloadable
    case .unsupported:
      return .unavailable
    @unknown default:
      return .unavailable
    }
  }

  /// `localeIdentifier`(BCP-47)を`SpeechTranscriber.supportedLocales`の
  /// いずれかへ解決する。解決できなければ`nil`(=LocaleUnsupported相当)。
  static func resolveLocale(_ localeIdentifier: String) async -> Locale? {
    await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier))
  }
}

@available(macOS 26.0, iOS 26.0, *)
enum TranscriptionPreset {
  /// 採用: `.progressiveTranscription`。
  ///
  /// 採用理由(design.md §4.2「Presetの選定は精度に大きく影響する」への
  /// 回答):
  /// design.md §2.2の`TranscriptSegment.isFinal`はpartial(暫定)結果を
  /// 表現できる設計であり、Web実装(design.md §4.1)も`interimResults`で
  /// 暫定結果をリアルタイムに配信する。`SpeechTranscriber.Preset`のうち
  /// `.progressiveTranscription`系のみがvolatile(`isFinal == false`)
  /// 結果を発行することをspikes/darwin/RESULTS.md(Issue #9)の実測
  /// (finalSegmentCount/partialSegmentCountの計測)で確認済みである。
  ///
  /// 一方でRESULTS.mdのキーワード包含率比較(「プリセット比較」節)では、
  /// 非progressiveの`.transcription`が一部クリップ(enUS_10s: 80.0%→
  /// 100.0%)で明確に上回る一方、別のクリップ(jaJP_3m.wav)ではかえって
  /// 悪化しており(39.3%→32.1%)、結果は一貫していない。`.transcription`
  /// はvolatile結果を一切発行しないこともRESULTS.mdで確認済みであり、
  /// design.mdのisFinal設計(partial結果を許容する設計、requirements.md
  /// FR-3)と両立しない。
  ///
  /// 精度が一貫して優位というわけではない`.transcription`に切り替える
  /// 根拠は薄く、design.mdが定めるAPI契約(partial結果を許容する)を
  /// 満たせないというデメリットの方が明確であるため、`.progressiveTranscription`
  /// を採用する。
  static let selected: SpeechTranscriber.Preset = .progressiveTranscription
}
