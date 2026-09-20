# M0 検証スパイク: Darwin(SpeechAnalyzer / SpeechTranscriber)

対応 Issue: #7(ロケール・アセット照会)/ #8(ファイル入力文字起こし)/ #9(RTF計測)/ #10(iOS/macOS共用スパイクとしての統合)。
対応する設計: design.md §4.2 Darwin、§5 エラーマッピング、§7 テスト戦略・評価基準(キーワード包含率)、§8 未決事項3。
対応するタスク: tasks.md「M0 検証スパイク」> Darwin セクション。

このディレクトリは、Flutterライブラリの実装(M2)に入る前に「macOS/iOS上でSpeechフレームワークの
`SpeechAnalyzer` + `SpeechTranscriber` によるファイル入力オフライン文字起こしが実際に動くか」を確認するための、
Flutter外の単体SwiftPMパッケージである。`spikes/web/`(Chrome Web Speech APIスパイク)とディレクトリ構成・文書の
粒度を揃えている。

## 前提

- **macOS 26 以上 / iOS 26 以上、Xcode 26 以上**。本スパイクの実測は macOS 26.5.1 (build 25F80) / Xcode 26.6 /
  Swift 6.3.3 / arm64 で行った。
- `Package.swift` の `platforms` は `.macOS(.v26)`, `.iOS(.v26)`(swift-tools-version 6.2 以上が必要)。
- Speech フレームワークの26系APIは `@available(macOS 26.0, iOS 26.0, *)` でゲートされているため、本パッケージの
  コードも `if #available(macOS 26.0, iOS 26.0, *)` で分岐し、26未満相当では `unavailable` を出力して終了する
  構造にしている(design.md §4.2 準拠)。ただし `Package.swift` 自体の最低デプロイメントターゲットを26としている
  ため、このスパイク単体では分岐は実質常に真になる。M2で本ソースを実パッケージ(より低いデプロイメントターゲット)
  へ移植する際に、このコード構造がそのまま意味を持つ。

## ディレクトリ構成

```
spikes/darwin/
├── Package.swift
├── README.md                              … 本ファイル
├── RESULTS.md                             … 実測結果
└── Sources/
    ├── DarwinSTTSpikeCore/                … 共用ロジック(iOSスパイク・M2実装からも参照可能なライブラリターゲット)
    │   ├── Support.swift                  … 共通エラー分類・BCP-47変換・タイムアウト・基準音声パス解決
    │   ├── LocaleAssetInquiry.swift        … Issue #7: ロケール・アセット照会
    │   ├── ModelAcquisition.swift          … モデル取得(AssetInstallationRequest)・reserve/release
    │   ├── Transcription.swift             … Issue #8: AVAudioFile → SpeechAnalyzer + SpeechTranscriber
    │   ├── RTFMeasurement.swift            … Issue #9: RTF計測(ウォームアップ1回+計測3回+中央値)
    │   ├── KeywordScoring.swift             … design.md §7 準拠のキーワード包含率スコアリング
    │   └── CLIReport.swift                 … CLI出力用の集計型・JSONエンコード
    └── DarwinSTTSpikeCLI/                  … 実行可能ターゲット
        ├── CLI.swift                       … サブコマンド実装
        └── main.swift                      … エントリポイント
```

## ビルド・実行方法

```bash
cd spikes/darwin
swift build
```

実行例(いずれもリポジトリルートまたは `spikes/darwin` から実行可能。`test-assets/baseline-audio` を自動探索する):

```bash
# ロケール・アセット照会のみ(Issue #7)
swift run darwin-stt-spike locales --json

# モデル取得(AssetInventory.status → assetInstallationRequest → downloadAndInstall)
swift run darwin-stt-spike model --locale ja-JP

# 1クリップの文字起こし(Issue #8)
swift run darwin-stt-spike transcribe jaJP_10s --format wav

# 全クリップ実行(test-assets/baseline-audio の8ファイル。Issue #8/#9/キーワード包含率をまとめて実行)
swift run darwin-stt-spike all --json
```

## サブコマンド

| サブコマンド | 内容 |
|---|---|
| `locales [--json]` | `SpeechTranscriber.isAvailable` / `supportedLocales` / `installedLocales` / `ja`言語のエントリ / `supportedLocale(equivalentTo:)` / `AssetInventory.status` / `maximumReservedLocales` / `reservedLocales` を照会・出力する。`.supported` と `installedLocales` の不整合を検出した場合は警告を出す。 |
| `model [--locale <bcp47>] [--json]` | 指定ロケールについて `AssetInventory.status` が `.installed` でなければ `assetInstallationRequest(supporting:)` → `downloadAndInstall()` を実行し所要時間を計測する。あわせて `reserve(locale:)` / `release(reservedLocale:)` の挙動も記録する。 |
| `transcribe <clipId> [--format wav\|m4a] [--preset progressive\|standard] [--baseline-dir <path>] [--json]` | 1クリップを `AVAudioFile` → `SpeechAnalyzer` + `SpeechTranscriber` で文字起こしし、RTF・partial/final件数・キーワード包含率を出力する。`--preset standard` で非progressiveの `.transcription` プリセットとの精度比較ができる(既定は `.progressiveTranscription`)。 |
| `all [--baseline-dir <path>] [--timeout <seconds>] [--json]` | `test-assets/baseline-audio` の ja-JP / en-US × 10秒 / 3分 × wav / m4a の計8ファイルについて、ロケール照会・モデル取得・RTF計測(ウォームアップ1回+計測3回)・キーワード包含率スコアリングを一括実行する。1クリップの処理は既定600秒(`--timeout`で変更可)でタイムアウトし、超過分は結果にタイムアウトとして記録される。 |

`--json` を付けると、人間可読テキストに加えて機械可読JSON(`RESULTS.md`への転記に使用)を追加出力する。

## preset選択について

`Transcription.swift` は既定で `SpeechTranscriber.Preset.progressiveTranscription` を使う。design.mdの
`TranscriptSegment` は `isFinal` で partial/final を区別する設計であり、本スパイクでもpartial(volatile)結果が
実際に観測できるかを確認する必要があったため、名称上 "progressive" を含む(＝逐次結果の提供を意図した)プリセットを
選んだ。Speech.swiftinterfaceで確認できる`SpeechTranscriber.Preset`は次の5種のみである。

```
.transcription
.transcriptionWithAlternatives
.timeIndexedTranscriptionWithAlternatives
.progressiveTranscription
.timeIndexedProgressiveTranscription
```

実測では `.progressiveTranscription` でpartial件数が clip あたり数十〜数百件観測でき、partialが実際に得られる
ことを確認した(RESULTS.md参照)。一方で、`.transcription`(非progressive)との精度比較を `transcribe --preset standard`
で行ったところ、クリップによって `.transcription` の方がキーワード包含率が明確に高いケースがあった(特に
`enUS_10s` は progressive 80.0% → standard 100.0%)。ファイル入力(ストリーミング不要)というユースケースでは、
M2実装時に `.transcription` 系プリセットの採用を再検討する価値がある。詳細はRESULTS.mdを参照。

## design.md §7 のしきい値(キーワード包含率)

`KeywordScoring.swift` の `ScoringThresholds` にまとめている。design.md §7由来。

- ja-JP: 95%以上で合格、90〜94%で条件付き合格、90%未満で不成立
- en-US: 95%以上で合格、95%未満で不成立

正規化ルール(NFKC正規化 → 小文字化 → 句読点・記号除去 → 空白除去、ja-JPはさらにひらがな→カタカナ畳み込み)も
design.md §7に厳密に従っている。詳細は `KeywordScoring.swift` のコメントを参照。

## iOSシミュレータでの実行について

SwiftPMの実行可能ターゲットはiOSシミュレータ向けにクロスビルドできる(`swift build --sdk <iphonesimulator SDK> --triple arm64-apple-ios26.0-simulator`)。生成されたバイナリは `xcrun simctl spawn <UDID> <binary> <args>` でシミュレータ上のプロセスとして直接起動できることを確認した(app bundle化は不要)。実測結果はRESULTS.md参照。

```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
swift build --sdk "$SDK" --triple arm64-apple-ios26.0-simulator
xcrun simctl boot F047D4FA-3E8D-4F3B-99A3-38DF6D3900B0   # 既に起動済みなら不要
xcrun simctl spawn F047D4FA-3E8D-4F3B-99A3-38DF6D3900B0 \
  .build/arm64-apple-ios-simulator/debug/darwin-stt-spike locales
```

## M1以降のE2E検証での再利用について

このハーネスは `spikes/web/` 同様、tasks.md M1「E2E手動チェックリスト作成」やM2 Darwin実装のE2E検証の雛形を兼ねる。
`DarwinSTTSpikeCore` は実行可能ターゲットと分離したライブラリターゲットとして構成しているため、M2の
`<name>_darwin` パッケージ実装時や、将来のiOS実機検証用アプリからロジックを移植・参照する際の出発点として
利用できる。基準音声セット(`test-assets/baseline-audio/`)・キーワード包含率の算出式・しきい値は
`spikes/web/` と共通であり、四半期回帰(tasks.md「継続タスク」)でも同一の判定基準を再利用する。
