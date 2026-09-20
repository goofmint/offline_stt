# RESULTS.md — M0 Darwinスパイク実測結果

対応 Issue: #7 / #8 / #9 / #10。対応する設計: design.md §4.2 Darwin、§5 エラーマッピング、§7 テスト戦略・評価基準、§8 未決事項3。

## 検証環境

- macOS 26.5.1 (build 25F80)
- Xcode 26.6 (Build version 17F113)
- Swift 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- アーキテクチャ: arm64 (Apple Silicon)
- 実行日時: 2026-09-20 JST
- 実行コマンド: `swift run darwin-stt-spike all --json`(macOS実機、`spikes/darwin`配下)

## Issue #7: ロケール・アセット照会

初回照会(本スパイクによる一連の操作を行う前の初期状態):

| 項目 | 値 |
|---|---|
| `SpeechTranscriber.isAvailable` | `true` |
| `supportedLocales`(30件) | `de-AT, de-CH, de-DE, en-AU, en-CA, en-GB, en-IE, en-IN, en-NZ, en-SG, en-US, en-ZA, es-CL, es-ES, es-MX, es-US, fr-BE, fr-CA, fr-CH, fr-FR, it-CH, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, yue-CN, zh-CN, zh-HK, zh-TW` |
| `installedLocales`(初期) | `["ja-JP"]` |
| `jaLocales`(言語コードが`ja`のエントリ) | `["ja-JP"]` |
| `supportedLocale(equivalentTo: Locale("ja-JP"))` | `ja-JP` |
| `AssetInventory.status([SpeechTranscriber(locale: ja-JP, preset: .transcription)])`(初期) | `.supported`(**`.installed`ではない**) |
| `AssetInventory.maximumReservedLocales` | `5` |
| `AssetInventory.reservedLocales`(初期) | `[]` |

上記は本スパイク実装前に既に実機確認済みの値と完全に一致した(`darwin-stt-spike locales --json`の初回実行で再現)。

### `.supported` と `installedLocales` の不整合に関する考察(重要な追加発見)

本スパイクでは、上記の不整合(`installedLocales`にja-JPが含まれるのに`status`が`.installed`でなく`.supported`を返す)について、**その原因を実測で特定できた**。手順は以下のとおり:

1. 初期状態: `installedLocales=["ja-JP"]`、`status(ja-JP)=.supported`、`reservedLocales=[]`
2. `darwin-stt-spike transcribe jaJP_10s`(実際に`SpeechAnalyzer`+`SpeechTranscriber`でja-JPの文字起こしを1回実行)を行った直後に再照会すると、`status(ja-JP)=.installed`に変化し、`reservedLocales`に`ja-JP`が自動的に追加されていた(こちらから`AssetInventory.reserve(locale:)`を明示的に呼んでいないにもかかわらず)。
3. `darwin-stt-spike model --locale ja-JP`で明示的に`AssetInventory.release(reservedLocale: ja-JP)`相当を実行してja-JPの予約を解除すると、`status(ja-JP)`は再び`.supported`に**戻った**。この間、`installedLocales`にja-JPが含まれ続けている点は変化しなかった。
4. 同様の現象はde-DE(元々未使用のロケール)でも確認した: `model --locale de-DE`実行(`assetInstallationRequest`→`downloadAndInstall()`、所要0.339秒程度)により`status`が`.supported→.installed`に変化すると同時に、明示的な`reserve()`呼び出し前から`reservedLocales`に`de-DE`が追加されていた。

以上から、以下の解釈が実測により裏付けられた:

- **`installedLocales` はアセット(モデルの実体データ)がディスク上に存在するかどうかを表す永続的な状態**である。
- **`AssetInventory.status(forModules:)` の `.installed` は、当該ロケールが現在「予約(reserve)」されている、すなわちアクティブに利用可能な状態として確保されているかどうかに連動する一時的な状態**であるとみられる。予約が外れると、ディスク上にアセットが存在していても `.supported` に戻る。
- `assetInstallationRequest(supporting:)` → `downloadAndInstall()` の呼び出しは、暗黙的に対象ロケールを予約状態にする副作用を持つ。
- `AssetInventory.reserve(locale:)` はロケールが既に予約済みの場合 `false` を返す(エラーにはならない)。`release(reservedLocale:)` はその予約を明示的に解除でき、実際に成功する(`true`が返り`reservedLocales`から除去される)ことを確認した。

**FR-1の状態写像への示唆**: `checkModel(locale)` を `AssetInventory.status` のみに単純追従させて実装すると、「ディスクにモデルは存在するが現在予約されていない」状態を`downloadable`相当に誤判定し、ユーザーに不要な再ダウンロードを促す可能性がある。`installedLocales`(永続状態)と`status`(予約に連動する一時状態)を併用し、`installedLocales`に含まれていれば`available`寄りに倒す、あるいは`status != .installed`でも`installedLocales`に含まれていれば内部で`reserve()`を自動実行してから`.installed`相当として扱う、といった実装方針の検討が必要である。design.md §8 未決事項3(ja-JP対応可否)は「対応可否」自体はYESで確定できるが、この状態写像の細部は新たな未決事項として追加すべきである。

### 追加観測: `installedLocales` は地域変種をまたいで共有される場合がある

en-US・de-DEを使用した後に`installedLocales`を再照会すると、`de-AT, de-CH, de-DE, en-AU, en-CA, en-GB, en-IE, en-IN, en-NZ, en-SG, en-US, en-ZA, ja-JP` の13件に増加していた。en-USやde-DEを1つ使っただけで、使っていないはずの同系統の地域変種(en-AU、en-CA、de-AT、de-CH等)まで`installedLocales`に含まれるようになった。これは基盤の音声モデルが言語単位(ベースランゲージ)で共有され、地域変種(ロケール)単位では独立してダウンロードされない可能性を示唆する。FR-1のロケール単位の状態確認を実装する際、この共有関係を前提に含めるべきかは追加調査が必要(新規の未決事項候補)。

## モデル取得の結果と所要時間

| ロケール | statusBefore | requestObtained | downloadAndInstall所要時間 | statusAfter |
|---|---|---|---|---|
| ja-JP(2回目、release後の再取得) | `.supported` | `true` | **0.339秒** | `.installed` |
| de-DE(初回) | `.supported` | `true` | (未計測、詳細ログ省略。1秒未満で完了) | `.installed` |

いずれも所要時間はごく短く(1秒未満)、ネットワーク経由のダウンロードというよりは「既にディスク上にあるアセットのアクティブ化」に近い挙動だった。これは、本検証機のmacOSで事前にDictationやSiri等を通じて該当言語の音声モデル一式が既にOSレベルでダウンロード済みだったためと考えられる(`say -v Kyoko`等のTTS音声が利用可能な環境であることからも、日本語・英語の言語資産は元々インストール済みだった可能性が高い)。**真にモデル未取得のクリーンな環境でのダウンロード所要時間は本検証では実測できていない**(既知の制約としてここに明記する)。

`reserve(locale:)` / `release(reservedLocale:)` の挙動:

- `reserve(locale:)`: 既に予約済みのロケールに対しては `false` を返す(失敗ではなく「既に予約済みで変化なし」の意味と解釈できる)。エラーはスローされなかった。
- `release(reservedLocale:)`: 予約済みロケールに対して呼ぶと `true` を返し、実際に`reservedLocales`から除去されることを確認した(呼び出し元が`reserve()`で予約した場合でも、他の経路(モデル取得の副作用)で予約された場合でも、同様に解除できた)。
- `maximumReservedLocales=5` に対し、本セッション中に ja-JP / en-US / de-DE の3ロケールを同時に予約した状態を作れた(上限超過は未検証)。

## Issue #8: クリップ別の書き起こしテキストとエラー有無

全8ファイル(ja-JP / en-US × 10秒 / 3分 × wav / m4a)を `all` サブコマンドで実行し、**エラーは一切発生しなかった**(全クリップが最後まで完走)。使用プリセットは既定の `.progressiveTranscription`。

### ja-JP

**jaJP_10s.wav / .m4a**(認識結果はwav/m4aでわずかに異なる):

> wav: 東京都渋谷区で 2024年 11月 3日午後 3時株式会社モーギフトが新製品を発表しました。来場者は 102十 8名でした。
> m4a: 東京都渋谷区で 2024年 11月 3日午後 3時株式会社モギフトが新製品を発表しました。来場者は 102十 8名でした。

「モーンギフト」が「モーギフト/モギフト」に、「128名」が「102十8名」のように誤認識されている。

**jaJP_3m.wav / .m4a**(抜粋、全文はJSON出力参照): 冒頭部分は10秒版とほぼ同じ精度だが、後半(3分の2以降)にかけて欠落・誤認識が明確に増加する傾向が見られた(例: 「セキュリティ」→「キュリティ」、「山田健太氏」は正しく認識される一方「田中健一」は「田中健」「田中健一氏」など揺れがあり、「鈴木一郎」は「鈴木氏」等に短縮される)。

### en-US

**enUS_10s.wav / .m4a**(両形式で同一テキスト):

> In San Francisco on November 3rd, 2024, at 3 p.m., Moon Gifting Corporated announced its new product. Attendance reached 128 people, filling the venue completely.

`Moongift Incorporated` が `Moon Gifting Corporated` と誤認識されている以外はほぼ正確。

**enUS_3m.wav / .m4a**(抜粋): 固有名詞(`Kenichi Tanaka`→`Kenichi Chinaka`、`Misaki Sato`→`Misaki Sado`、`Ichiro Suzuki`→`Hiro Suzuki`/`Ichero Suzuki`)や数値の読み(`ninety eight point one percent`→`98.one%`、`forty five seconds`の脱落等)で誤認識が目立つ。全文はJSON出力(`swift run darwin-stt-spike all --json`)に記録済み。

### エラーパス個別確認(design.md §5 Darwin列との対応)

`all`実行では上記のとおりエラーは発生しなかったが、エラー分類ロジック自体は個別に強制発火させて動作を確認した。

| design.md §5 分類 | 発火方法 | 実測結果 |
|---|---|---|
| DecodeFailed(AVAudioFileエラー) | テキストファイルを`.wav`として読ませる | `[エラー] DecodeFailed(AVAudioFileエラー: ... Error Domain=com.apple.coreaudio.avfaudio Code=1954115647 ...)` を確認 |
| LocaleUnsupported(supportedLocales外) | `model --locale xx-XX` | `[エラー] LocaleUnsupported(supportedLocales外: xx-XX)` を確認 |
| (スパイク独自)Timeout | `all --timeout 0.01` | `[エラー] Timeout(0.01秒超過。スパイク独自分類)` を確認(1クリップあたり最大処理時間の制約を担保する仕組みとして機能) |
| ModelUnavailable / DeviceUnsupported / Cancelled | 未発火 | 本検証機はja-JP/en-US双方が取得可能な環境のため`ModelUnavailable`は発火せず、macOS 26上で実行しているため`DeviceUnsupported`(OSバージョンゲート)も未発火。`Cancelled`はTask cancel時の分岐をコードに実装したが、本検証では意図的なキャンセル操作を行っていないため未発火(コードレビューでの確認に留まる) |

## Issue #9: RTF計測(ウォームアップ1回 + 計測3回、中央値)

既定プリセット `.progressiveTranscription` での計測結果。

| クリップ | 形式 | 音声長(秒) | ウォームアップ(秒) | 計測1(秒) | 計測2(秒) | 計測3(秒) | RTF1 | RTF2 | RTF3 | **中央値RTF** |
|---|---|---|---|---|---|---|---|---|---|---|
| jaJP_10s | wav | 9.56 | 0.12 | 0.11 | 0.10 | 0.10 | 0.011 | 0.011 | 0.011 | **0.011** |
| jaJP_10s | m4a | 9.56 | 0.11 | 0.11 | 0.11 | 0.11 | 0.012 | 0.012 | 0.012 | **0.012** |
| jaJP_3m  | wav | 175.24 | 1.20 | 1.42 | 3.24 | 2.44 | 0.008 | 0.018 | 0.014 | **0.014** |
| jaJP_3m  | m4a | 175.24 | 2.06 | 1.96 | 1.97 | 2.03 | 0.011 | 0.011 | 0.012 | **0.011** |
| enUS_10s | wav | 11.90 | 0.36 | 0.31 | 0.28 | 0.25 | 0.026 | 0.023 | 0.021 | **0.023** |
| enUS_10s | m4a | 11.90 | 0.24 | 0.25 | 0.24 | 0.25 | 0.021 | 0.020 | 0.021 | **0.021** |
| enUS_3m  | wav | 176.33 | 4.52 | 4.33 | 3.79 | 3.70 | 0.025 | 0.022 | 0.021 | **0.022** |
| enUS_3m  | m4a | 176.33 | 4.09 | 4.52 | 4.47 | 4.32 | 0.026 | 0.025 | 0.025 | **0.025** |

**NFR-1(ファイル処理速度)への回答**: すべてのクリップでRTFは0.008〜0.026の範囲、すなわち**実時間の約38倍〜125倍高速**にファイル入力の文字起こしが完了した。design.mdの「要実測: ファイル入力時の処理速度(実時間より速いか)」に対し、macOS 26上では明確に「実時間よりはるかに速い」という結果が得られた。`analyzeSequence(from:)`の戻り値(`CMTime?`)は全クリップで音声長とほぼ一致し(例: jaJP_10s→9.562秒、jaJP_3m→175.236秒)、ファイル全体が正しく解析されたことも確認できた。

partial(volatile)結果の観測件数(finalSegmentCount/partialSegmentCount、`.progressiveTranscription`使用時): jaJP_10s final=1/partial=55、jaJP_3m final=3/partial=681〜824、enUS_10s final=2/partial=44、enUS_3m final=16〜17/partial=692〜697。`.progressiveTranscription`が実際にpartial結果を多数発行することを確認した(design.md未決事項4のWeb版と対照的に、Darwinでは`isFinal=false`のvolatile結果が安定して得られる)。

## キーワード包含率(design.md §7、Issue #6相当)

既定プリセット `.progressiveTranscription` での結果。しきい値は design.md §7 準拠(README.md参照): ja-JP 95%以上合格/90〜94%条件付き合格/90%未満不成立、en-US 95%以上合格。

| クリップ | 一致数/総数 | 包含率 | 判定 | 不一致キーワード |
|---|---|---|---|---|
| jaJP_10s (wav/m4a共通) | 4/6 | 66.7% | **不成立** | 株式会社モーンギフト、128名 |
| jaJP_3m.wav | 11/28 | 39.3% | **不成立** | 渋谷ヒカリエ、モジトルCore、32万人、45秒、96.4パーセント、98.1パーセント、12言語、20言語、月間5000件、2025年2月15日、サンフランシスコ、3億円、ベルリン、ISO27001、月額4980円、鈴木一郎、18名 |
| jaJP_3m.m4a | 8/28 | 28.6% | **不成立** | 上記に加え田中健一、佐藤美咲、名古屋市も不一致(計20件) |
| enUS_10s (wav/m4a共通) | 4/5 | 80.0% | **不成立** | Moongift Incorporated |
| enUS_3m (wav/m4a共通) | 11/25 | 44.0% | **不成立** | Kenichi Tanaka、three hundred and twenty thousand、Misaki Sato、forty five seconds、ninety six point four percent、ninety eight point one percent、twelve languages、twenty languages、five thousand、three million dollars、Kenta Yamada、Ichiro Suzuki、eighteen、forty two engineers |

**8ファイル中8ファイルすべてが不成立**という結果になった。

### プリセット比較(`.transcription`との比較、参考値)

partial観測のため既定は`.progressiveTranscription`としたが、progressive系プリセットが精度に影響する可能性を検証するため、非progressiveの`.transcription`プリセットでも同一クリップを実行した(RTF計測は行わず単発実行のみ)。

| クリップ | `.progressiveTranscription` | `.transcription`(standard) | 差分 |
|---|---|---|---|
| jaJP_10s | 66.7%(不成立) | 83.3%(不成立、ただし「株式会社モーンギフト」は一致するようになった) | +16.6pt |
| jaJP_3m.wav | 39.3%(不成立) | 32.1%(不成立) | **-7.2pt(悪化)** |
| enUS_10s | 80.0%(不成立) | **100.0%(合格)** | +20.0pt |

結果は一貫しておらず、`.transcription`が常に優位というわけではない(jaJP_3mではむしろ悪化)。ただしenUS_10sのように明確な改善が得られるケースもあり、ファイル入力用途(ストリーミング不要)では`.transcription`系プリセットの採用も選択肢として残すべきである。partial(volatile)結果は`.transcription`使用時は0件だった(想定どおり、非progressiveプリセットではvolatile結果が発行されない)。

## Issue #10: macOSでの総合判定

- **パイプラインの技術的成立性**: 成立。design.md §4.2どおり `AVAudioFile(forReading:)` → `SpeechTranscriber(locale:preset:)` → `SpeechAnalyzer(modules:)` → `analyzeSequence(from:)` → `finalizeAndFinishThroughEndOfInput()` の一気通貫パイプラインが、wav・m4a両形式、10秒・3分両尺、ja-JP・en-US両ロケールの全8ファイルでエラーなく完走した。
- **ファイル処理速度(NFR-1)**: 成立。RTF 0.008〜0.026、実時間の38〜125倍高速。
- **partial結果の観測(design.mdのisFinal設計との整合)**: 成立。`.progressiveTranscription`使用時にvolatile結果が安定して多数観測できた。
- **エラーマッピング(design.md §5)**: 成立。DecodeFailed・LocaleUnsupportedの実発火を確認した(ModelUnavailable/DeviceUnsupported/Cancelledはこの検証機の環境上未発火だが、コード上の分岐は実装済み)。
- **キーワード包含率(design.md §7)**: **不成立**。既定プリセットで8ファイル中8ファイルが不成立。`.transcription`プリセットに切り替えても改善は一部に留まった。

## iOSシミュレータでの実行

`iPhone 17 Pro Simulator (26.5)`(UDID `F047D4FA-3E8D-4F3B-99A3-38DF6D3900B0`)に対して以下を実施した。

```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)   # iPhoneSimulator26.5.sdk
swift build --sdk "$SDK" --triple arm64-apple-ios26.0-simulator   # ビルド成功(sysroot警告1件のみ)
xcrun simctl boot F047D4FA-3E8D-4F3B-99A3-38DF6D3900B0
xcrun simctl spawn F047D4FA-3E8D-4F3B-99A3-38DF6D3900B0 \
  .build/arm64-apple-ios-simulator/debug/darwin-stt-spike locales
```

**実施でき、クラッシュなく完走した**(app bundle化なしで`simctl spawn`により裸の実行ファイルを直接起動できた)。結果:

```
isAvailable: false
supportedLocales (0件):
installedLocales:
AssetInventory.status(ja-JP): unsupported
```

macOS実機では`isAvailable=true`・`supportedLocales=30件`だったのに対し、iOSシミュレータでは`isAvailable=false`・`supportedLocales=0件`・`status=unsupported`となった。原因は特定できていない(以下のいずれか、または両方の可能性がある。追加調査が必要):

1. iOSシミュレータ自体がオンデバイスSpeechモデルの実行(Neural Engine相当の処理)に対応していない
2. app bundle化されていない裸の実行ファイルとして`simctl spawn`で起動したため、`NSSpeechRecognitionUsageDescription`等のInfo.plistエントリや適切なコード署名・entitlementが欠如しており、機能が有効化されない

`transcribe`サブコマンドも実行を試みたが、`simctl spawn`下ではカレントディレクトリがホスト側の実行時ディレクトリと異なり、相対パスでの`test-assets/baseline-audio`探索が失敗した(`--baseline-dir`に絶対パスを明示すれば解決できる可能性があるが、`isAvailable=false`である以上いずれにせよ文字起こし自体は成立しないと判断し、これ以上の追跡は行わなかった)。

**結論**: iOSシミュレータでの実行そのものは可能だが、Speech機能自体がシミュレータ上では利用不可(`unavailable`)という結果になった。これはiOS実機での検証が別途必須であることを示す実測結果であり、design.md未決事項3「iOS 26実機でのja対応可否」は本スパイクでは確定できていない。

## iOS実機について

**未実施**。理由: iOS 26実機が本検証環境に接続されていないため。design.md §8 未決事項3(iOS 26実機でのSpeechTranscriber ja対応可否)は、macOS 26実機での確認(`ja-JP`はsupportedLocales・installedLocalesの両方に含まれ、実際の文字起こしも動作する)をもって**同一フレームワークである以上iOSでも技術的には同様に動作する可能性が高いと推測できる**が、iOSシミュレータでの`isAvailable=false`という結果(上記)がある以上、**iOS実機での確認なしに確定的な結論を出すことはできない**。tasks.mdのDarwinセクション1行目(「iOS 26実機で〜確認(設計未決事項3)」)は本スパイクでは未達成のまま残る。

## Darwin総合判定(成立 / 不成立)と根拠

**不成立(技術統合は成立するが、design.md §7 の精度基準を満たさない。不成立の原因は未確定)。**

根拠:

1. **技術統合は明確に成立**: design.md §4.2で設計されたパイプライン(AVAudioFile→SpeechAnalyzer+SpeechTranscriber)がmacOS 26上で全8基準音声ファイルに対してエラーなく完走し、design.md §5のエラー分類(DecodeFailed、LocaleUnsupported)も実装どおりに機能することを確認した。ファイル処理速度は実時間の38〜125倍と、NFR-1に対して極めて良好な結果が得られた。
2. **精度(design.md §7しきい値)は本基準音声セットでは不成立**: 8クリップ全てで不成立(ja-JP: 28.6〜66.7%、en-US: 44.0〜80.0%)。しきい値(ja-JP 95%/90%、en-US 95%)に対して明確に不足している。
3. **不成立の原因は未確定**: 本スパイクには対照条件がないため、以下の要因を互いに分離できていない。いずれが支配的かを示す根拠は得られていない。
   - 基準音声がTTS合成音声(`say`コマンド、`spikes/web`と共用の同一アセット)であること。人間の自然発話に対する精度は未検証である
   - `SpeechTranscriber.Preset` の選択(下記4のとおり、クリップによって影響の向きが逆になる)
   - 認識モデル自体の精度
   - キーワードの選定と design.md §7 の正規化規則。例えば jaJP_10s の不一致2件は「株式会社モーンギフト」→「モーギフト」(架空の固有名詞)と「128名」→「102十8名」(数値の表記形式)であり、認識内容そのものの誤りと、キーワード比較が表記差を吸収できていないことの切り分けができていない
   
   原因を特定するには、自然発話の対照音声、プリセット固定、キーワード正規化の変更、をそれぞれ独立に振った再測定が必要である。
4. **プリセット選択の影響も無視できない**: 既定の`.progressiveTranscription`から`.transcription`への変更で一部クリップ(enUS_10s)は合格ラインに達した一方、別のクリップ(jaJP_3m)ではかえって悪化した。M2実装時にはプリセット選定を再検討する余地がある。

以上を踏まえ、tasks.md の「M0 出口判定」に対しては次のとおり扱う。

- design.md §7 のしきい値に照らすと、精度判定は**不成立**である。8ファイルすべてが基準未達であり、この事実は変わらない。
- したがって **M0 を条件付き成立として M1 へ進めてはならない**。tasks.md の「M0 出口判定」は不成立項目について対象外化または構成変更を求めており、この判断を経ずに先へ進むことはできない。
- ただし、不成立の原因が上記3のいずれであるかは未確定である。Darwin を対象外化すべきかどうかは、原因の切り分けを行ったうえで M0 出口判定で決める。
- **M0 出口判定で決めるべき事項**: (a) 精度判定そのものの合否、(b) 基準音声セットの読み上げスクリプトとキーワード選定を見直すか、(c) design.md §7 のしきい値・正規化規則を見直すか、(d) プリセットを判定条件に含めるか。

自然発話による再検証は原因切り分けの手段のひとつであり、それ自体が M0 を成立させるものではない。

## design.md / requirements.md との齟齬

1. **design.md §7の合格しきい値の記述と備考の不整合**: design.md §7の表は「クリーン基準音声 / ja-JP / 90%以上」を合格しきい値として記載しているが、直後の備考に「90〜94%は条件付き合格」とあり、90%以上をそのまま単純合格とすると備考と矛盾する。本スパイクでは実施依頼で明示された「95%以上合格/90〜94%条件付き合格/90%未満不成立」の解釈を採用した(`KeywordScoring.swift`の`ScoringThresholds`にコメントで明記)。design.md本体の表記を「95%以上」に修正することを提案する。
2. **`AssetInventory.status`が`.installed`であることの意味**: design.md §4.2は「モデル管理: AssetInventoryでlocaleのアセット状態を照会・取得要求。FR-1/FR-2に写像」とのみ記載しているが、本スパイクの実測により`.installed`は「ディスク上のアセット存在」ではなく「現在の予約(reserve)状態」に連動することが判明した。design.md §8への新規未決事項追加、またはdesign.md §4.2本文への追記を提案する(詳細は本ファイル「Issue #7」節参照)。
3. **`installedLocales`がロケール単位でなく言語(ベースランゲージ)単位で共有されうる**: design.mdはFR-1をロケール単位の状態(`available`/`downloadable`/`downloading`/`unavailable`)として設計しているが、実測では1つの地域変種(例: en-US)を使うと未使用の同系統変種(en-AU、en-CA等)も`installedLocales`に含まれるようになった。ロケール単位の状態管理という設計前提の一部見直しが必要になる可能性がある。
4. **Preset選定は design.md に明記されていない**: design.md §4.2は「SpeechAnalyzer + SpeechTranscriber(locale指定)」とのみ記載し、`SpeechTranscriber.Preset`の選定基準には触れていない。本スパイクの実測(プリセットによって包含率が最大20ポイント以上変動)を踏まえ、design.md §4.2にpreset選定の指針(またはM2での要検討事項として明記)を追加することを提案する。
5. **タイムアウト分類(`DarwinSpikeError.timeout`)はdesign.md §5に存在しない**: 本スパイク独自の追加分類であり、design.md §5表への反映が必要かはM2実装判断による(3分クリップの実測RTFが0.01〜0.03と極めて高速だったため、実運用でタイムアウトが問題になる可能性は低いと考えられる)。
