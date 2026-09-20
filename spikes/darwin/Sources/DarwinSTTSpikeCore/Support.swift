// Support.swift
// 共有の基礎的な型・エラー分類・ユーティリティ。
// Issue #7〜#10 の全モジュールから参照される。

import Foundation

/// design.md §5 エラーマッピング表の Darwin 列に対応する分類。
/// - ModelUnavailable      … アセット取得不可
/// - LocaleUnsupported     … supportedLocales 外
/// - DecodeFailed          … AVAudioFile エラー
/// - DeviceUnsupported     … OS 26 未満
/// - Cancelled             … Task cancel
/// - Timeout               … 本スパイク独自(1クリップ最大10分の実行時間制約。design.mdの表には無いが、
///                            M0検証の実施可否判定のためにこのスパイクで追加した分類)
/// - Underlying            … 上記以外(Speechフレームワークからのその他のエラーをそのまま保持)
public enum DarwinSpikeError: Error, CustomStringConvertible, Sendable {
    case osVersionUnsupported
    case localeUnsupported(String)
    case assetUnavailable(String)
    case decodeFailed(String)
    case cancelled
    case timeout(afterSeconds: Double)
    case underlying(String)

    public var description: String {
        switch self {
        case .osVersionUnsupported:
            return "DeviceUnsupported(OS 26未満、または #available ゲート不成立)"
        case .localeUnsupported(let locale):
            return "LocaleUnsupported(supportedLocales外: \(locale))"
        case .assetUnavailable(let detail):
            return "ModelUnavailable(アセット取得不可: \(detail))"
        case .decodeFailed(let detail):
            return "DecodeFailed(AVAudioFileエラー: \(detail))"
        case .cancelled:
            return "Cancelled(Task cancel)"
        case .timeout(let seconds):
            return "Timeout(\(seconds)秒超過。スパイク独自分類)"
        case .underlying(let detail):
            return "Underlying(\(detail))"
        }
    }
}

/// `Locale` を BCP-47 表記の文字列へ変換する共通ヘルパー。
public func bcp47(_ locale: Locale) -> String {
    locale.identifier(.bcp47)
}

extension Duration {
    /// 秒(Double)への変換。RTF計測・所要時間記録で使用する。
    public var asSeconds: Double {
        let c = self.components
        return Double(c.seconds) + Double(c.attoseconds) / 1_000_000_000_000_000_000.0
    }
}

/// `operation` を `seconds` 秒でタイムアウトさせる。
/// 3分クリップの認識に時間がかかる可能性がある(タスク指示上限: 1クリップあたり最大10分)ため、
/// `all` サブコマンドの各クリップ処理をこれで包む。
public func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DarwinSpikeError.timeout(afterSeconds: seconds)
        }
        guard let result = try await group.next() else {
            throw DarwinSpikeError.timeout(afterSeconds: seconds)
        }
        group.cancelAll()
        return result
    }
}

/// `test-assets/baseline-audio` ディレクトリを解決する。
/// 実行時のカレントディレクトリが `spikes/darwin` 直下・リポジトリルート直下いずれの場合でも
/// 動作するよう、候補パスを順に探索する。
public enum BaselineAudioLocator {
    public static func resolve(explicit: String?) -> URL? {
        let fm = FileManager.default
        if let explicit {
            let url = URL(fileURLWithPath: explicit)
            if fm.fileExists(atPath: url.path) { return url }
            return nil
        }
        let candidates = [
            "test-assets/baseline-audio",
            "../../test-assets/baseline-audio",
            "../test-assets/baseline-audio",
            "../../../test-assets/baseline-audio"
        ]
        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate)
            if fm.fileExists(atPath: url.path) {
                return url.standardizedFileURL
            }
        }
        return nil
    }
}

/// 基準音声セット中のクリップ識別子(ファイル名プレフィックス)。
public struct BaselineClipRef: Sendable {
    public let id: String          // 例: "jaJP_10s"
    public let localeIdentifier: String // 例: "ja-JP"

    public init(id: String, localeIdentifier: String) {
        self.id = id
        self.localeIdentifier = localeIdentifier
    }

    /// M0スコープの全8ファイル(ja-JP/en-US × 10s/3m × wav/m4a)のうち、
    /// クリップ単位(拡張子違いを除く)の一覧。
    public static let all: [BaselineClipRef] = [
        BaselineClipRef(id: "jaJP_10s", localeIdentifier: "ja-JP"),
        BaselineClipRef(id: "jaJP_3m", localeIdentifier: "ja-JP"),
        BaselineClipRef(id: "enUS_10s", localeIdentifier: "en-US"),
        BaselineClipRef(id: "enUS_3m", localeIdentifier: "en-US")
    ]

    public static let formats = ["wav", "m4a"]
}
