// ProbeApp.swift
// Issue #7: iOS 26 実機で SpeechTranscriber の supportedLocales に ja が含まれるかを確認する。
//
// macOS 版 CLI (darwin-stt-spike locales) と同一の DarwinSTTSpikeCore.LocaleAssetInquiry を
// 呼ぶ。両者で差異が出た場合、それはプラットフォーム側の差異であってコードの差異ではない。
//
// 結果は画面に表示すると同時に標準出力へも出す。後者は
// `xcrun devicectl device process launch --console` で回収する。

import SwiftUI
import Speech

@main
struct DarwinSTTProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
        }
    }
}

struct ProbeView: View {
    @State private var output: String = "照会を実行していない。"
    @State private var running = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(output)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Issue #7 ロケール照会")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("再実行") { Task { await run() } }
                        .disabled(running)
                }
            }
        }
        .task { await run() }
    }

    @MainActor
    private func run() async {
        running = true
        defer { running = false }
        let text = await Self.probe()
        output = text
        // devicectl --console で回収するため標準出力にも必ず出す。
        print("===DARWIN_STT_PROBE_BEGIN===")
        print(text)
        print("===DARWIN_STT_PROBE_END===")
    }

    /// OSバージョンゲート。design.md §4.2 のとおり iOS 26 未満は unavailable 相当とする。
    private static func probe() async -> String {
        guard #available(iOS 26.0, *) else {
            return """
            iOS 26 未満のため SpeechAnalyzer / SpeechTranscriber は利用できない。
            design.md §4.2 の OSバージョンゲートにより unavailable 相当として扱う。
            実行中の iOS: \(UIDevice.current.systemVersion)
            """
        }

        let result = await LocaleAssetInquiry.run()
        var lines: [String] = []
        lines.append("device: \(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)")
        lines.append("isAvailable: \(result.isAvailable)")
        lines.append("supportedLocales (\(result.supportedLocaleCount)件):")
        lines.append(result.supportedLocales.isEmpty ? "  (なし)" : "  " + result.supportedLocales.joined(separator: ", "))
        lines.append("installedLocales:")
        lines.append(result.installedLocales.isEmpty ? "  (なし)" : "  " + result.installedLocales.joined(separator: ", "))
        lines.append("jaLocales: \(result.jaLocales.isEmpty ? "(なし)" : result.jaLocales.joined(separator: ", "))")
        lines.append("supportedLocale(equivalentTo: ja-JP): \(result.equivalentToJaJP ?? "nil")")
        lines.append("AssetInventory.status(ja-JP): \(result.assetStatusForJaJP)")
        lines.append("maximumReservedLocales: \(result.maximumReservedLocales)")
        lines.append("reservedLocales: \(result.reservedLocales.isEmpty ? "(なし)" : result.reservedLocales.joined(separator: ", "))")
        if let warning = result.statusInstalledMismatchWarning {
            lines.append("")
            lines.append("[警告] \(warning)")
        }

        // RESULTS.md への転記用に JSON も出す。
        if let data = try? JSONEncoder().encode(result),
           let json = String(data: data, encoding: .utf8) {
            lines.append("")
            lines.append("--- JSON ---")
            lines.append(json)
        }
        return lines.joined(separator: "\n")
    }
}
