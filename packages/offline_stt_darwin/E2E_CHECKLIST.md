# offline_stt_darwin E2E 手動チェックリスト(iOS / macOS)

対応 Issue: #66(収録)、#40(実機E2Eの実施)、#7(iOS 26実機での確認)。
対応する設計: design.md §7「テスト戦略」、§4.2 Darwin、§5 エラーマッピング表
Darwin列。共通の前提・包含率の算出方法・しきい値は
[リポジトリルートの E2E_CHECKLIST.md](../../E2E_CHECKLIST.md) を参照。

**リリース前に人手で実行する手順書である。** 土台は M0 スパイク
(`spikes/darwin/README.md` / `RESULTS.md`)である。

**2026-09-21 に本チェックリストを本番実装(本パッケージ)へ通して実行した。
結果は [E2E_RESULTS.md](E2E_RESULTS.md) にある**(macOS 26.5.1 と
iPad Pro 11-inch (M4) / iOS 26.6.2)。そのときは example app の UI を人手で
操作する代わりに `apps/example/integration_test/darwin_baseline_e2e_test.dart`
から本番実装の API を直接呼んでいる。**UI 経路(ファイルピッカー → 同意
ダイアログ → 進行表示)の確認は依然として未実施であり、本手順書を人手で
実行する意義はそこに残っている。**

## なぜCIで検証できないのか

**iOSシミュレータでは SpeechAnalyzer が利用できないことが実測で確定して
いる。** M0検証では `SpeechTranscriber.isAvailable` が `false`、
`supportedLocales` が0件、`AssetInventory.status` が `unsupported` を返した。
`simctl spawn` による裸の実行ファイルと、正しく署名された .app バンドルの
両方で同じ結果になったため、原因は起動方法(entitlement・コード署名・
Info.plist宣言の欠如)ではなく、**シミュレータ自体にオンデバイス音声モデルが
無いこと**である(spikes/darwin/RESULTS.md)。

macOSランナーでの認識実行は原理的には可能だが、GitHub Hosted Runner に
ja-JP / en-US のオンデバイスモデルが取得済みである保証は無く、毎回の取得は
時間・ネットワークコストが不安定になる。

## 前提

- **OS**: macOS 26 以上 / iOS 26 以上(requirements.md NFR-4)。
  `supportedLocales` の件数・内容はOSバージョンで変動することが実測されて
  いる(macOS 26.5.1: 30件、iOS 26.6.2: 30件、iOS 27.0: 45件)。
  **対応下限である iOS 26 実機での確認は済んでいる**(iPad Pro 11-inch (M4)
  / iOS 26.6.2。spikes/darwin/RESULTS.md と E2E_RESULTS.md)。
- **iOSは実機であること。** シミュレータでは上記のとおり実行できない。
- 基準音声: `test-assets/baseline-audio/`。
- 実行対象: `apps/example`(`flutter run -d macos` / 実機を指定して
  `flutter run`)。

## 手順

### 1. 可用性チェック(checkModel)

1. example app を起動し、`ja-JP` と `en-US` について `checkModel(locale)` を
   実行する。
2. 期待される戻り値:
   - モデル取得済み: `available`
   - 未取得: `downloadable`
   - `supportedLocales` に含まれないロケール(`xx-XX` 等): `unavailable`
3. **`AssetInventory.status` と `installedLocales` の不整合を確認する。**
   M0検証では、`installedLocales` に ja-JP が含まれるにもかかわらず
   `AssetInventory.status(forModules:)` が `.supported` を返す状態が
   macOS・iOS実機の双方で再現した(SpeechAnalyzer APIの仕様であると確定)。
   この状態で `checkModel()` が **`available` を返す**ことを確認する
   (`ModelAvailability.swift` の判定規則6: `status == .supported` かつ
   `installedLocales` に解決済みロケールが含まれる → `available`)。
   ここで `downloadable` が返るなら、取得済みモデルに対して不要な再
   ダウンロードを促すことになるため不合格である。

### 2. downloadModel

1. `checkModel()` が `downloadable` を返したロケールについて、example app の
   **同意ダイアログで明示的に同意したうえで** `downloadModel(locale)` を
   実行する(requirements.md FR-2。ライブラリが暗黙にダウンロードを開始
   しないことの確認を兼ねる)。
2. `DownloadProgress` が emit され、最後に `completed: true` で終わることを
   確認する。
3. 完了後に `checkModel()` を再実行し `available` になることを確認する。

### 3. 文字起こし実行(transcribeFile)

基準音声8ファイル(ja-JP / en-US × 10秒 / 3分 × wav / m4a)すべてについて
実行する。

1. 各ファイルについて、以下を確認する:
   - partial(`isFinal: false`)のセグメントが実行中に継続的に届くこと。
     M0検証では既定プリセット `.progressiveTranscription` で jaJP_10s に
     partial 55件、jaJP_3m に 681〜824件が観測された
   - 最終的に `isFinal: true` のセグメントが届き、Stream が `done` で完了
     すること
   - エラーなく完走すること(M0検証では8ファイル全てで完走した)
2. **処理時間を記録する。** M0検証の RTF(処理時間 ÷ 音声長)は 0.008〜0.026、
   すなわち実時間の約38〜125倍高速であった(NFR-1)。本番実装でも同水準で
   あるか、著しく遅くなっていないかを確認する。
3. **`TranscribeRequest.playbackRate` はDarwinでは無視される**(Web専用
   オプション、design.md §2.2)。1.0以外を指定しても処理時間が変わらない
   ことを確認する。

### 4. キャンセル

1. 3分クリップの文字起こし実行中に購読(`StreamSubscription`)を
   `cancel()` する。
2. 以下を確認する:
   - それ以降 `TranscriptSegment` が届かないこと
   - 直後に別の `transcribeFile()` を開始でき、`StateError`(セッション
     排他違反)にならないこと
   - **M0スパイクではキャンセル経路は未発火であり、コードレビューでの確認に
     留まっていた。** 実際に発火させるのは本チェックリストが初めてになる。

### 5. セッション排他(design.md §3)

1. `transcribeFile()` の Stream を購読したまま、2本目の `transcribeFile()` を
   購読する。
2. 2本目が Stream エラー(`StateError`)で即座に終了することを確認する。

### 6. エラーパス(design.md §5 Darwin列)

| 例外 | 発火方法 | M0での実測 |
|---|---|---|
| `DecodeFailedException` | テキストファイルを `.wav` として読ませる | 発火を確認済み |
| `LocaleUnsupportedException` | `supportedLocales` に無いロケール(`xx-XX`)を指定する | 発火を確認済み |
| `ModelUnavailableException` | モデル未取得のロケールで `transcribeFile()` を呼ぶ | **未発火**(検証機が ja-JP / en-US 双方取得済みだったため) |
| `DeviceUnsupportedException` | requirements.md NFR-4 未満のOSで実行する | **未発火**(macOS 26上で実行したため) |
| `CancelledException` | 手順4のキャンセル | **未発火**(M0では意図的なキャンセルを行っていない) |

M0で未発火だった3件は、本チェックリストで実際に発火させて確認すること。
**ただし 2026-09-21 の実行で、`LocaleUnsupportedException` と
`CancelledException` は実装の構造上 Dart 側から観測できないことが実測で
確定した**(E2E_RESULTS.md の F-1 / F-2)。上表の「発火方法」はこの2件に
ついては現状の実装では成立しない。

### 7. キーワード包含率の記録

1. 各ファイルの確定テキストと `.json` の `keywords` を、ルートの
   E2E_CHECKLIST.md の正規化ルールに従って突き合わせる。
2. **しきい値未達は既知である。** M0検証では8ファイル全てが不成立で
   あった(ja-JP 28.6〜66.7%、en-US 44.0〜80.0%)。本番実装での値を記録し、
   M0の値から著しく劣化していないかを確認する。
3. **`SpeechTranscriber.Preset` による差が大きいことが実測されている。**
   M0では `.transcription`(非progressive)に切り替えると jaJP_10s が
   66.7%→83.3%、enUS_10s が 80.0%→100.0% に改善した一方、jaJP_3m は
   39.3%→32.1% と悪化した。**一貫した優劣は無い。** 本実装が採用している
   プリセットを記録したうえで判定すること。なお非progressiveプリセットでは
   partial 結果が発行されない(M0実測で0件)ため、手順3のpartial確認とは
   両立しない。

## 合否基準

- 手順1〜6は**すべて期待どおりに動作すること**。バグがあれば不合格。
- 手順7(包含率)は記録項目である。しきい値未達そのものは自動的に不合格を
  意味しないが、**原因未調査のまま合格扱いにしてはならない**
  (design.md §7)。

## このチェックリストで確認できないこと

- **iOS 27 実機での動作。** 2026-09-21 の実行は対応下限である iOS 26.6.2 の
  iPad Pro で行った。iOS 27.0 の `supportedLocales` は 45件であり 26系の
  30件と異なることが実測されているため、供給範囲は同一ではない。
- **人間の自然発話に対する精度。** 基準音声はTTS合成音声である。
- **実環境(ノイズあり)での精度。** 基準音声セットはクリーン音声のみで
  ある。
