// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DarwinSTTSpike",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // iOSスパイク(Issue #10)や将来のM2 darwinパッケージ実装からソースを共用できるよう、
        // CLI本体とは別にライブラリターゲットとして公開する。
        .library(name: "DarwinSTTSpikeCore", targets: ["DarwinSTTSpikeCore"]),
        .executable(name: "darwin-stt-spike", targets: ["DarwinSTTSpikeCLI"])
    ],
    targets: [
        .target(
            name: "DarwinSTTSpikeCore"
        ),
        .executableTarget(
            name: "DarwinSTTSpikeCLI",
            dependencies: ["DarwinSTTSpikeCore"]
        )
    ]
)
