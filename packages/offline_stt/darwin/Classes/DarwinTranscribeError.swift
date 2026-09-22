// DarwinTranscribeError.swift
// design.md §5 エラーマッピング表 Darwin列への分類(Issue #39)。
//
// spikes/darwin/Sources/DarwinSTTSpikeCore/Support.swift の `DarwinSpikeError`
// を参考にした本実装向けのエラー型。スパイクとの違いは、スパイクが
// `Timeout` / `Underlying` という独自分類を持っていたのに対し、本実装は
// design.md §5の表そのまま(ModelUnavailable/LocaleUnsupported/
// DecodeFailed/DeviceUnsupported/Cancelled/PlatformError)に対応させる
// 6値のみを持つ点である(Timeoutはスパイク独自の検証用分類であり本実装には
// 持ち込まない。design.md §8齟齬5参照)。
import Foundation

// iOS と macOS で Flutter のモジュール名が異なるため条件付きでimportする
// (`FlutterError` を直接参照するため)。
#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

enum DarwinTranscribeError: Error, Sendable {
  /// OS 26未満(design.md §4.2 OSバージョンゲート)、または
  /// `SpeechTranscriber.isAvailable == false`(iOSシミュレータ等、
  /// spikes/darwin/RESULTS.md「iOSシミュレータでの実行」参照)。
  case deviceUnsupported(String)

  /// アセット取得不可(ダウンロード失敗、または`checkModel()`が
  /// `available`以外の状態で`transcribeFile`が呼ばれた場合)。
  case modelUnavailable(String)

  /// `SpeechTranscriber.supportedLocale(equivalentTo:)`が`nil`を返した
  /// (supportedLocales外)。
  case localeUnsupported(String)

  /// `AVAudioFile(forReading:)`のデコードエラー。
  case decodeFailed(String)

  /// `Task.cancel()`によるキャンセル(`CancellationError`捕捉)。
  case cancelled

  /// 上記のいずれにも分類できないSpeechフレームワーク由来のエラー。
  case platformError(String)
}

extension DarwinTranscribeError {
  /// Pigeon生成の`TranscribeErrorCode`への対応(design.md §2.3)。
  var pigeonCode: TranscribeErrorCode {
    switch self {
    case .deviceUnsupported: return .deviceUnsupported
    case .modelUnavailable: return .modelUnavailable
    case .localeUnsupported: return .localeUnsupported
    case .decodeFailed: return .decodeFailed
    case .cancelled: return .cancelled
    case .platformError: return .platformError
    }
  }

  var detailMessage: String? {
    switch self {
    case .deviceUnsupported(let m), .modelUnavailable(let m), .localeUnsupported(let m),
      .decodeFailed(let m), .platformError(let m):
      return m
    case .cancelled:
      return nil
    }
  }
}

extension TranscribeErrorCode {
  /// EventChannelの`PigeonEventSink.error(code:)`、および同期HostApi
  /// メソッドが投げる`FlutterError.code`へ渡す文字列表現。
  ///
  /// この文字列はDart側(`lib/src/error_code_mapping.dart`)の
  /// `TranscribeErrorCode.name`(enum名の文字列表現)と完全一致させる
  /// ことで、Dart側が文字列比較のみで`TranscribeException`の具象型へ
  /// 写像できるようにしている。`lib/src/pigeon.g.dart`の
  /// `TranscribeErrorCode`定義とこの分岐の対応関係が崩れないよう、両方を
  /// 変更する場合は必ず同時に更新すること。
  var wireCode: String {
    switch self {
    case .modelUnavailable: return "modelUnavailable"
    case .localeUnsupported: return "localeUnsupported"
    case .decodeFailed: return "decodeFailed"
    case .deviceUnsupported: return "deviceUnsupported"
    case .cancelled: return "cancelled"
    case .platformError: return "platformError"
    }
  }
}

extension DarwinTranscribeError {
  /// 同期HostApiメソッド(`checkModel`等)がPigeonへ投げる`FlutterError`
  /// への変換。Pigeon生成の`wrapError(_:)`(Pigeon.g.swift)は`FlutterError`
  /// を優先的に`code`/`message`/`details`として展開するため、素のSwift
  /// エラーをそのまま投げるより意図が明確になる。
  var asFlutterError: FlutterError {
    FlutterError(code: pigeonCode.wireCode, message: detailMessage, details: nil)
  }
}

extension DarwinTranscribeError {
  /// `@async` なHostApiメソッド(`supportedLocales`)が
  /// `completion(.failure(_:))` へ渡すエラーへの変換。
  ///
  /// `asFlutterError` を使えない理由: `FlutterError` はObjective-Cのクラス
  /// (`FlutterError : NSObject`)であり Swift の `Error` に適合しないため、
  /// `Result<T, Error>.failure(_:)` へ渡せない。Pigeonが生成する
  /// `PigeonError`(Pigeon.g.swift)は `Error` に適合しており、
  /// `wrapError(_:)` が `FlutterError` と同じく `code`/`message`/`details`
  /// へ展開する。したがってDart側へ届く形は `asFlutterError` と同一である。
  var asPigeonError: PigeonError {
    PigeonError(code: pigeonCode.wireCode, message: detailMessage, details: nil)
  }
}
