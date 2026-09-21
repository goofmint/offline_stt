# offline_stt_darwin 実機E2E 実行結果

対応 Issue: #40([M2] iOS実機 + macOS実機で基準音声E2E)。
手順書は [E2E_CHECKLIST.md](E2E_CHECKLIST.md)、包含率の算出規則は
[リポジトリルートの E2E_CHECKLIST.md](../../E2E_CHECKLIST.md) および
design.md §7。

**本書は `packages/offline_stt_darwin/`(本番実装)を iOS 実機と macOS 実機で
動かした初めての記録である。** `spikes/darwin/RESULTS.md` は M0 スパイク
(`spikes/` 配下の独立した検証コード)の記録であり、別物である。M0 以降に
本番実装へ入った修正(ダウンロード進捗の `sendEndOfStream`、EventChannel
ごとのキャンセル分離、`downloadModel` の catch-all、
`startedNativeTranscription`)は、本実行まで一度も実機上で走っていない。

**本書には実測値のみを書く。実行していない項目は「未実施」と書き、理由を
添える。**

## 結論

**手順1〜6のすべてが期待どおりに動作した。本番実装のバグは発見されな
かった。** Android(Pixel 6)で見つかった B-1〜B-4 に相当する事象は
Darwin では一つも再現しなかった。

キーワード包含率(手順7)は **8ファイル全てがしきい値未達** であり、
M0 スパイクで macOS 上に記録された値と一致した。すなわち **本番実装への
移植による精度の劣化は無く、同時に M0 時点の未達も解消していない。**

> **2026-09-21 追記**: その後、基準音声セットの `keywords` が design.md §7 の
> 「許容表記を列挙する」規定に従っていなかった(表記差を不一致として数えて
> いた)ことが分かったため、**同じ確定テキストを是正後のキーワードセットで
> 採点し直した**。`enUS_3m` は 44.0% → **80.0%**、`jaJP_3m` は 39.3% →
> **42.9%** / 28.6% → **32.1%** となった。**認識結果は1文字も変わっておらず、
> 再測定もしていない**(採点側の不備の是正である)。**是正後も8ファイルすべて
> しきい値未達であり、結論は変わらない。** 詳細は「手順7: キーワード包含率」。

手順6のうち `DeviceUnsupportedException` は未実施である(OS 26 未満の実機が
無い)。`LocaleUnsupportedException` と `CancelledException` は、**実装の
構造上 Dart 側から観測できないことが実測で確定した**(後述 F-1 / F-2)。

## Issue #40 の達成状況

Issue #40 は「iOS実機 + macOS実機」を要求している。両方を実施した。

| 対象 | 状況 |
|---|---|
| macOS 実機 | 実施済み(macOS 26.5.1、Apple Silicon) |
| iOS 実機 | 実施済み(iPad Pro 11-inch (M4) / iOS 26.6.2) |

iOS 実機は **requirements.md NFR-4 が定める対応下限である iOS 26 系**の
端末を選んだ。手元にはもう1台 iOS 27.0 の iPhone 17 があるが、
「1プラットフォーム1台で足りる」という方針に従い、下限側のみを実施した。
**したがって iOS 27 実機での本番実装E2Eは未実施である。**

## 実行環境

| 項目 | 値 |
|---|---|
| 実行日 | 2026-09-21 |
| macOS 機 | macOS 26.5.1(Build 25F80)/ darwin-arm64。`flutter devices` の `macOS (desktop) • macos` |
| iOS 機 | 中津川篤司のiPad (4) = iPad Pro 11-inch (M4)。iOS 26.6.2(Build 23G90)、UDID `00008132-001C51C60E45001C` |
| Flutter | 3.41.9 stable(Dart 3.11.5) |
| Podfile の下限 | `platform :ios, '26.0'` / `platform :osx, '26.0'` |
| 被検体 | `packages/offline_stt_darwin/`(Dart + Swift)+ `packages/offline_stt_platform_interface/` |
| ドライバ | `apps/example/integration_test/darwin_baseline_e2e_test.dart` |
| プリセット | `SpeechTranscriber.Preset.progressiveTranscription`(`TranscriptionPreset.selected`) |
| 権限 | マイク等の実行時権限は一切付与していない(ファイル入力のみのため不要) |

**iOSシミュレータは使っていない。** `SpeechTranscriber.isAvailable` が
`false` になることが M0 で実測済みである(spikes/darwin/RESULTS.md)。

## 実行方法(再現手順)

E2E_CHECKLIST.md が想定する「example app の UI を人手で操作する」方式では
なく、**example app の integration_test から本番実装の API を直接呼ぶ**
方式を採った。理由は Android(`packages/offline_stt_android/E2E_RESULTS.md`)
と同じである。

1. 手順3・手順7は確定テキストを **正確な文字列として** 記録する必要がある。
   UI をスクリーンショットで読む方式では取りこぼす。
2. 手順4(キャンセル)・手順5(セッション排他)は `StreamSubscription` の
   操作そのものが検証対象であり、UI からは再現できない。
3. `darwin/` 側に XCTest を置く方式では Swift 層しか通らず、Dart 側の
   `TranscribeSessionGuard`・`startedNativeTranscription`・エラー写像
   (M0 以降に入った修正の多くがここにある)を検証できない。integration_test
   なら **Dart + Pigeon + Swift の本番経路をそのまま** 通せる。

```
# 1. 基準音声を example app のアセットへ複製する
apps/example/tool/stage_baseline_audio.sh

# 2. macOS
cd apps/example
flutter test integration_test/darwin_baseline_e2e_test.dart -d macos

# 3. iOS 実機(id は `flutter devices` で確認する)
flutter test integration_test/darwin_baseline_e2e_test.dart \
  -d 00008132-001C51C60E45001C
```

標準出力の `E2E|` 始まりの行が測定値である。包含率は確定テキストを
`test-assets/keyword_score.py` に渡して算出する(Dart には Unicode NFKC
正規化が標準で無いため、端末側では採点しない)。

### 基準音声の与え方(Android と異なる点)

Android は adb でアプリ専用外部ストレージへ push している。Darwin では
同じ方式を採れないため、**Flutter アセットとして .app へ焼き込み、起動時に
`rootBundle` から読み出してアプリのテンポラリディレクトリへ実ファイルとして
書き出す**方式にした。理由は次の2点である。

- **macOS**: example app は App Sandbox 有効
  (`macos/Runner/DebugProfile.entitlements` の
  `com.apple.security.app-sandbox` = true)である。テストプロセスはアプリ
  本体と同じサンドボックス内で動くため、リポジトリ配下の `test-assets/` を
  直接 open できない。エンタイトルメントを緩めるのは example app の構成を
  検証のために弱めることになるので採らなかった。
- **iOS 実機**: ホストのファイルシステムが見えない。
  `xcrun devicectl device copy to` でアプリのデータコンテナへ送る方式も
  あるが、`flutter test` は実行のたびにアプリを入れ直すためコンテナごと
  消える(Android で実測済み)。Android と同じ「インストールを待ってから
  送る」バックグラウンドスクリプトを書くこともできるが、USB 経由で 15MB を
  送る時間と競合の不確実さが増えるだけである。

実測した書き出し先は次のとおり。

- macOS: `/Users/<user>/Library/Containers/com.moongift.example/Data/Library/Caches/com.moongift.example/baseline-audio`
- iOS: `/var/mobile/Containers/Data/Application/<UUID>/Library/Caches/baseline-audio`

アセットの実体(約15MB)は `.gitignore` 済みであり、リポジトリには
`.gitkeep` しか入っていない。`apps/example/pubspec.yaml` がアセット
ディレクトリとして宣言しているため、**E2E を実行する前に必ず
`stage_baseline_audio.sh` を走らせること**。

### example app の UI 経路について

ファイルピッカー → モデル状態表示 → ダウンロード同意ダイアログ → 進行表示、
という example app の UI 経路は本実行では通っていない。**UI 経路の確認は
未実施である。**

## 手順1: 可用性チェック(checkModel)

`checkModel()` を20ロケールに対して実行した。macOS と iOS で結果が異なる
のは、端末にどのモデルが取得済みかが違うためである。

| ロケール | macOS 26.5.1 | iOS 26.6.2(初回) | iOS 26.6.2(最終) |
|---|---|---|---|
| ja-JP | available | available | available |
| ja | available | available | available |
| en-US | available | **downloadable** | available |
| en | available | downloadable | available |
| en-GB | available | downloadable | available |
| en-AU | available | downloadable | available |
| en-IN | available | downloadable | available |
| en-CA | available | downloadable | available |
| fr-FR | downloadable | downloadable | available |
| de-DE | available | downloadable | available |
| es-ES | downloadable | downloadable | downloadable |
| it-IT | downloadable | downloadable | downloadable |
| ko-KR | downloadable | downloadable | downloadable |
| zh-CN | downloadable | downloadable | downloadable |
| zh-TW | downloadable | downloadable | downloadable |
| pt-BR | downloadable | downloadable | downloadable |
| ru-RU | **unavailable** | unavailable | unavailable |
| hi-IN | **unavailable** | unavailable | unavailable |
| xx-XX | unavailable | unavailable | unavailable |
| zz-ZZ | unavailable | unavailable | unavailable |

- 「初回」は何もダウンロードしていない状態、「最終」は手順2の
  ダウンロードを実施した後である(`available` へ遷移したものは、この
  E2E の中でダウンロードしたロケールである)。
- **期待どおりの3値が返った。** 実在しないロケール(`xx-XX` / `zz-ZZ`)は
  `unavailable`、取得済みは `available`、未取得は `downloadable` である。
- ru-RU / hi-IN が `unavailable` なのは、`SpeechTranscriber.supportedLocales`
  に含まれていないためである(macOS 26.5.1 / iOS 26.6.2 はいずれも30件。
  spikes/darwin/RESULTS.md)。
- 応答時間は初回のみ 63〜88ms、2回目以降は 2〜4ms であった。

### 手順1の3.(`AssetInventory.status` と `installedLocales` の不整合)

**この integration_test からは直接観測できない。** 本番実装は
`supportedLocales` / `installedLocales` / `AssetInventory.status` の生の値を
Dart へ公開せず、公開APIは `ModelState` の4値だけだからである。

観測できたのは「その不整合下でも `checkModel('ja-JP')` が `available` を
返す」ことである。**不整合そのものは iOS 26.6.2 で M0 相当のプローブ
(`spikes/darwin/ios-probe`)により再現が確認済みであり**
(`installedLocales` に ja-JP があるのに `status` は `.supported`、
spikes/darwin/RESULTS.md)、その端末で本実行が `available` を返したという
ことは、`ModelAvailability.swift` の判定規則6が実機で効いているという
ことである。不要な再ダウンロードを促す誤判定は起きていない。

### 手順1-b(チェックリスト外の追加測定): checkModel の再現性

Android 実機E2Eで「連続呼び出し時に `checkModel` が偽の `unavailable` を
返す」事象(B-2)が出たため、Darwin でも同じ測定を行った。`ja-JP` を
待機なしで30回連続呼び出した結果:

- macOS 26.5.1: **30回すべて `available`**(2〜3ms)
- iOS 26.6.2: **30回すべて `available`**(2〜3ms)

**B-2 相当の事象は Darwin では再現しなかった。**

## 手順3: 文字起こし実行(transcribeFile)

基準音声8ファイルすべてで、partial が継続的に届き、`isFinal: true` の
セグメントで終わり、Stream が `done` で完了した。**エラーは1件も無く、
8ファイル×2プラットフォームの16回すべてが1回目で完走した。**

| clip | 音声長(s) | macOS ms | macOS RTF | macOS partial/final | iOS ms | iOS RTF | iOS partial/final |
|---|---|---|---|---|---|---|---|
| jaJP_10s.wav | 9.56 | 203 | 0.0212 | 55/1 | 323 | 0.0338 | 55/1 |
| jaJP_10s.m4a | 9.56 | 121 | 0.0127 | 55/1 | 489 | 0.0511 | 55/1 |
| enUS_10s.wav | 11.90 | 291 | 0.0245 | 44/2 | 397 | 0.0334 | 44/2 |
| enUS_10s.m4a | 11.90 | 224 | 0.0188 | 44/2 | 234 | 0.0197 | 44/2 |
| jaJP_3m.wav | 175.24 | 1338 | 0.0076 | 824/3 | 1258 | 0.0072 | 824/3 |
| jaJP_3m.m4a | 175.24 | 1167 | 0.0067 | 681/3 | 1035 | 0.0059 | 681/3 |
| enUS_3m.wav | 176.33 | 3083 | 0.0175 | 697/17 | 2907 | 0.0165 | 697/17 |
| enUS_3m.m4a | 176.33 | 3203 | 0.0182 | 692/16 | 2957 | 0.0168 | 692/16 |

- RTF は **0.0059〜0.0511**(実時間の約20〜170倍速)であった。M0 スパイクの
  0.008〜0.026 と同水準であり、**本番実装への移植による速度の劣化は無い**
  (NFR-1)。RTF が最も悪い 0.0511 は iPad の10秒クリップであり、絶対値では
  489ms である。
- partial 件数は M0 の実測(jaJP_10s 55件、jaJP_3m 681〜824件)と
  **完全に一致した。**
- **partial/final の件数は macOS と iOS で1件の差も無かった。**

### 手順3の3.(playbackRate が無視されること)

同一クリップ(jaJP_10s.wav)を `playbackRate` 1.0 / 2.0 / 0.5 で実行した。

| rate | macOS 所要 | iOS 所要 | 確定テキスト |
|---|---|---|---|
| 1.0 | 98ms | 176ms | 3件すべて同一 |
| 2.0 | 96ms | 99ms | 同上 |
| 0.5 | 98ms | 98ms | 同上 |

**所要時間にも確定テキストにも差が無く、Darwin では無視されることを実測で
確認した**(design.md §2.2)。`recognition_session.dart` が Pigeon の
`TranscribeRequest` へ `path` / `locale` しか渡さないため、そもそも
ネイティブへ届かない。

## 手順4: キャンセル

3分クリップ(jaJP_3m.wav)の実行中、最初のセグメントが届いた時点で
`StreamSubscription.cancel()` した。

| 項目 | macOS | iOS |
|---|---|---|
| セッション開始 | 成功(リトライ不要) | 成功(リトライ不要) |
| `cancel()` の Future 完了 | 0ms | 0ms |
| キャンセル後5秒間に届いたセグメント | **0件** | **0件** |
| 直後の別 `transcribeFile()` | 成功(`StateError` にならず、finals=1) | 成功(finals=1) |

**期待どおりに動作した。** M0 では未発火だったキャンセル経路が、本実行で
初めて実際に発火した。

ただし正直に書くと、**「ネイティブの Task が実際に早期停止したか」は Dart
側からは観測できていない。** 観測できたのは「キャンセル後にセグメントが
届かない」「次のセッションを直ちに開始できる」の2点である。

## 手順5: セッション排他

1本目(jaJP_3m.wav)を購読したまま2本目(jaJP_10s.wav)を購読した。
両プラットフォームで2本目が即座に `StateError` で終了した。メッセージは
逐語で次のとおり。

```
Bad state: 既に実行中のセッションが存在する。design.md §3のとおり、同時セッションはv1では1本に制限される。1本目のセッションが終了(done/error/cancelled)してから再度呼び出すこと。
```

**期待どおりである。**

## 手順6: エラーパス

| 例外 | 発火方法 | macOS | iOS |
|---|---|---|---|
| `DecodeFailedException` | テキストファイルを `.wav` として読ませる | **発火** | **発火** |
| `LocaleUnsupportedException` | `xx-XX` / `zz-ZZ` を指定する | 発火せず(F-1) | 発火せず(F-1) |
| `ModelUnavailableException` | 未取得(`downloadable`)のロケールで `transcribeFile()` | **発火**(ko-KR) | **発火**(ko-KR) |
| `DeviceUnsupportedException` | NFR-4 未満のOSで実行する | **未実施** | **未実施** |
| `CancelledException` | 手順4のキャンセル | 発火せず(F-2) | 発火せず(F-2) |

`DeviceUnsupportedException` が未実施なのは、**macOS 26 未満 / iOS 26 未満の
実機が手元に無い**ためである。`if #available` 分岐によるものであり、
実機のOSを下げる以外に発火させる方法が無い。

### F-1. `LocaleUnsupportedException` は Dart 側から到達できない

`xx-XX` / `zz-ZZ` を指定したときに Stream へ流れたのは
**`ModelUnavailableException`** であり、`LocaleUnsupportedException` では
なかった(macOS・iOS 双方)。

理由は実装の順序である。`recognition_session.dart` は `transcribeFile()` の
先頭で `checkModel()` を呼び、`available` 以外なら
`ModelUnavailableException` で終了する。`ModelAvailability.checkModel` は
`supportedLocale(equivalentTo:)` が `nil` のとき `unavailable` を返すため、
**supportedLocales 外のロケールは必ず `unavailable` になり、
`TranscriptionSession.run()` の `localeUnsupported` 判定へ到達しない。**

**これは Android の F-1 とまったく同じ構造である**
(`packages/offline_stt_android/E2E_RESULTS.md`)。Darwin 固有の問題では
なく、design.md §5 のエラーマッピング表と、`transcribeFile()` が
`checkModel()` を前置する設計(§3)との間の齟齬である。Swift 側の
`localeUnsupported` は `downloadModel()` 経由(`ModelAcquisition.run`)
でのみ到達しうるが、そちらも `runDownload` が先に `checkModel` を見て
`downloadable` 以外なら何もせず終了するため、やはり到達しない。

**本実行では修正していない。** design.md 側をどう直すかを含めて判断が
要るためである。

### F-2. `CancelledException` も Dart 側から到達できない

手順4でキャンセルすると、Swift 側は `DarwinTranscribeError.cancelled` を
segments EventChannel の `sendError` で送出する。しかし Dart 側は
`onCancel` の時点で `finished = true` とし `nativeSubscription.cancel()` を
済ませているため、**このエラーは購読者へ届かない**(実測: キャンセル後に
エラーもセグメントも一切届かなかった)。

これは仕様として自然でもある。購読をキャンセルした側へ Stream エラーを
配送する経路は Dart の Stream には無い。ただし **design.md §5 が Darwin列に
`Cancelled` を挙げている以上、「アプリから観測できる例外ではない」ことは
明記されるべきである。** 本実行では実装もドキュメントも変更していない。

## 追加項目(チェックリスト外): ダウンロードと文字起こしの同居

M0 以降に本番実装へ入った次の2つの修正は、**ダウンロードと文字起こしが
同時に走っている状態でしか効かない**ため、E2E_CHECKLIST.md の手順では
一度も踏めない。専用の項目を足した。

1. `recognition_session.dart` の `startedNativeTranscription`。
   `hostApi.cancel()` は文字起こしとダウンロードの**両方**を止めるため、
   ネイティブの文字起こしを開始する前に購読がキャンセルされたときに
   これを呼ぶと、無関係なダウンロードまで止まる。
2. `OfflineSttDarwinPlugin.swift` の EventChannel ごとのキャンセル分離。
   文字起こしが正常終了すると Dart 側が segments EventChannel の購読を
   解除するため、分離が無いとそこでダウンロードまで止まる。

ko-KR のダウンロード中に (a) ネイティブ開始前のキャンセル、(b) ja-JP の
文字起こしの完走、を続けて行った結果:

| 項目 | macOS | iOS |
|---|---|---|
| (a) 開始前キャンセル | 完了(このとき進捗イベント0件) | 完了(同左) |
| (b) 文字起こし完走 | finals=1、done=true、error=null | finals=1、done=true、error=null |
| ダウンロードの結末 | `completed: true` で正常終了、`checkModel` は `available` | 同左 |

**両方の修正が実機で意図どおり効いていることを確認した。** 分離が無ければ
(a) または (b) の時点でダウンロードが `CancelledException` で落ちるはず
だが、そうならなかった。

## 手順2: downloadModel

**この項目は integration_test の最後に置いている。** ダウンロードは
ネットワーク次第で数分かかりうるため、先に走らせると失敗時に手順3〜6の
測定がまとめて失われるためである。

`downloadable` のロケールを探して `downloadModel()` を実行した。実測値:

| 実行 | ロケール | 所要 | イベント数 | 終わり方 | 直後の checkModel |
|---|---|---|---|---|---|
| macOS 1回目 | fr-FR | 16.2秒 | 9 | `completed: true` → done | available |
| macOS 2回目 | ko-KR(追加項目) | 計測せず | 9 | `completed: true` → done | available |
| macOS 3回目 | es-ES | 10.3秒 | 8 | `completed: true` → done | available |
| iOS 1回目 | fr-FR | 13.8秒 | 4 | `completed: true` → done | available |
| iOS 2回目 | en-US | 12.1秒 | 4 | `completed: true` → done | available |
| iOS 3回目 | de-DE | 11.9秒 | 4 | `completed: true` → done | available |
| iOS 4回目 | ko-KR(追加項目) | 計測せず | 4 | `completed: true` → done | available |
| iOS 5回目 | es-ES | 11.2秒 | 4 | `completed: true` → done | available |

**8回すべてが成功し、`DownloadProgress` が emit され、最後に
`completed: true` で終わり、Stream が `done` で完了した。** 完了後の
`checkModel()` は全て `available` になった。Android の B-4(タイムアウトが
効かない・11分ハング)に相当する事象は起きていない。

なお、example app の同意ダイアログを経由していない(UI 経路は未実施)。
「ライブラリが暗黙にダウンロードを開始しないこと」は、手順6で
`downloadable` のロケールに対して `transcribeFile()` が
`ModelUnavailableException` で即座に失敗すること(=勝手に取得しない)に
よって確認できている。

### F-3. 進捗 `fraction` の粒度が iOS と macOS で大きく違う

逐語の進捗イベントは次のとおりであった。

macOS(fr-FR):

```
fraction=0.0 completed=false
fraction=0.1 completed=false
fraction=0.3 completed=false
fraction=0.45 completed=false
fraction=0.66 completed=false
fraction=0.81 completed=false
fraction=1.0 completed=false
fraction=1.0 completed=false
fraction=1.0 completed=true
```

iOS(fr-FR / en-US / de-DE / ko-KR / es-ES、**5回すべて同一**):

```
fraction=0.0 completed=false
fraction=1.0 completed=false
fraction=1.0 completed=false
fraction=1.0 completed=true
```

**iOS では中間の進捗が1件も来ない。** `ModelAcquisition.swift` は
`AssetInstallationRequest.progress` の `fractionCompleted` を KVO で観測して
いるが、iOS ではこのプロパティが 0.0 から 1.0 へ一足飛びに変化している
(その間、約12秒かかっている)。実装のバグではなく、`Foundation.Progress`
を Speech フレームワークがどう更新するかの差である。

**アプリ側への影響**: `DownloadProgress.fraction` を進捗バーに使うと、
iOS では12秒間 0% のまま止まって見える。`packages/offline_stt_darwin/README.md`
や example app の実装指針に、**iOS では不定進捗として扱うほうが安全である**
旨を書くべきである(本実行では変更していない)。

### F-4. `fraction=1.0, completed=false` が2回続けて emit される

上のログのとおり、両プラットフォームで `fraction=1.0, completed=false` が
2回出る。`ModelAcquisition.run()` が `downloadAndInstall()` の後に
`onProgress(1.0)` を明示的に呼ぶ一方、KVO 側も 1.0 を通知するためである。

契約違反ではない(`DownloadProgress` は単調増加や一意性を約束していない)
ため**バグとしては扱わない**が、冗長である。

## 手順7: キーワード包含率

正規化規則は design.md §7(ルートの E2E_CHECKLIST.md)のとおりであり、
`test-assets/keyword_score.py` に確定テキスト(`isFinal: true` のセグメントを
連結したもの)を渡して算出した。

### 集計

> **2026-09-21 追記: キーワードセット是正後の値に更新した。** 下表の
> 「是正後」は、**同じ確定テキストを、許容表記を列挙し直した
> `test-assets/baseline-audio/*.json` で採点し直した値**である。
> **認識は一切やり直していない**(端末での再測定はしていない)。値が動いた
> のは、`three hundred and twenty thousand` に対する `320,000` のような
> **単なる表記差を不一致として数えていた採点側の不備を直した**ためである。
> 経緯は design.md §7 および `test-assets/baseline-audio/README.md`
> 「許容表記の一覧と選定理由」を参照。是正前の値も比較のため残す。

| clip | 是正前 macOS / iOS | **是正後 macOS / iOS** | 判定(是正後) | M0 スパイク(macOS、是正前) |
|---|---|---|---|---|
| jaJP_10s.wav | 4/6 = 66.7% | **4/6 = 66.7%**(変化なし) | 不成立 | 66.7% |
| jaJP_10s.m4a | 4/6 = 66.7% | **4/6 = 66.7%**(変化なし) | 不成立 | 記録なし |
| enUS_10s.wav | 4/5 = 80.0% | **4/5 = 80.0%**(変化なし) | 不成立 | 80.0% |
| enUS_10s.m4a | 4/5 = 80.0% | **4/5 = 80.0%**(変化なし) | 不成立 | 記録なし |
| jaJP_3m.wav | 11/28 = 39.3% | **12/28 = 42.9%** | 不成立 | 39.3% |
| jaJP_3m.m4a | 8/28 = 28.6% | **9/28 = 32.1%** | 不成立 | 28.6% |
| enUS_3m.wav | 11/25 = 44.0% | **20/25 = 80.0%** | 不成立 | 44.0% |
| enUS_3m.m4a | 11/25 = 44.0% | **20/25 = 80.0%** | 不成立 | 44.0% |

分母(キーワードグループ数)は是正の前後で変えていない(6 / 5 / 28 / 25)。
是正で一致に変わったキーワードは次のとおりである。

| clip | 是正で HIT になったキーワード | 一致した許容表記 |
|---|---|---|
| jaJP_3m.wav / .m4a | `20言語` | `二十言語`(認識結果が漢数字表記) |
| enUS_3m.wav / .m4a | `three hundred and twenty thousand` | `320,000` |
| enUS_3m.wav / .m4a | `forty five seconds` | `45 seconds` |
| enUS_3m.wav / .m4a | `ninety six point four percent` | `96.4%` |
| enUS_3m.wav / .m4a | `twelve languages` | `12 languages` |
| enUS_3m.wav / .m4a | `twenty languages` | `20 languages` |
| enUS_3m.wav / .m4a | `five thousand` | `5,000` |
| enUS_3m.wav / .m4a | `three million dollars` | `$3 million` |
| enUS_3m.wav / .m4a | `eighteen` | `18 people` |
| enUS_3m.wav / .m4a | `forty two engineers` | `42 engineers` |

是正後も残る不一致は**表記差ではなく誤認識・脱落**である。enUS_3m の残り5件は
`Kenichi Tanaka`(→ `Kenichi Chinaka`)・`Misaki Sato`(→ `Misaki Sado`)・
`ninety eight point one percent`(→ `98.one%`)・`Kenta Yamada`(→ `Kento Yamada`)・
`Ichiro Suzuki`(→ `Hiro Suzuki` / `Ichero Suzuki`)である。

しきい値は ja-JP 95%以上で合格・90〜94%で条件付き・en-US 95%以上で合格
である。**是正後も8ファイルすべて不成立である。**

- **macOS と iOS の値は完全に一致した。** HIT/MISS の内訳も一致した。
- **M0 スパイク(macOS、`.progressiveTranscription`)の値とも一致した。**
  本番実装への移植で精度は変わっていない。
- 同じ音声の wav と m4a で **jaJP_3m だけ 39.3% → 28.6%(是正後 42.9% → 32.1%)と差が出た**。
  10秒クリップと enUS_3m では wav / m4a で差が無い。AAC 圧縮が長尺の
  日本語で効いている可能性はあるが、**原因は未調査である。**

### キーワード別 HIT/MISS

> 以下の内訳表は**キーワードセット是正前**の採点結果である(記録として残す)。
> 是正後に HIT へ変わるのは上表「是正で HIT になったキーワード」の各件のみで、
> それ以外の行は変わらない。

#### jaJP_10s.wav

- macOS 26.5.1: **4/6 = 66.7% → 不成立**
- iOS 26.6.2: **4/6 = 66.7% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| 東京都渋谷区 | HIT | HIT |
| 2024年11月3日 | HIT | HIT |
| 午後3時 | HIT | HIT |
| 株式会社モーンギフト | MISS | MISS |
| 新製品 | HIT | HIT |
| 128名 | MISS | MISS |

#### jaJP_10s.m4a

- macOS 26.5.1: **4/6 = 66.7% → 不成立**
- iOS 26.6.2: **4/6 = 66.7% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| 東京都渋谷区 | HIT | HIT |
| 2024年11月3日 | HIT | HIT |
| 午後3時 | HIT | HIT |
| 株式会社モーンギフト | MISS | MISS |
| 新製品 | HIT | HIT |
| 128名 | MISS | MISS |

#### enUS_10s.wav

- macOS 26.5.1: **4/5 = 80.0% → 不成立**
- iOS 26.6.2: **4/5 = 80.0% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| San Francisco | HIT | HIT |
| November 3rd, 2024 | HIT | HIT |
| 3 PM | HIT | HIT |
| Moongift Incorporated | MISS | MISS |
| 128 | HIT | HIT |

#### enUS_10s.m4a

- macOS 26.5.1: **4/5 = 80.0% → 不成立**
- iOS 26.6.2: **4/5 = 80.0% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| San Francisco | HIT | HIT |
| November 3rd, 2024 | HIT | HIT |
| 3 PM | HIT | HIT |
| Moongift Incorporated | MISS | MISS |
| 128 | HIT | HIT |

#### jaJP_3m.wav

- macOS 26.5.1: **11/28 = 39.3% → 不成立**
- iOS 26.6.2: **11/28 = 39.3% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| 東京都渋谷区 | HIT | HIT |
| 2024年11月3日 | HIT | HIT |
| 渋谷ヒカリエ | MISS | MISS |
| 128名 | HIT | HIT |
| モジトルCore | MISS | MISS |
| 月額980円 | HIT | HIT |
| 田中健一 | HIT | HIT |
| 2019年 | HIT | HIT |
| 32万人 | MISS | MISS |
| 佐藤美咲 | HIT | HIT |
| 10分間 | HIT | HIT |
| 45秒 | MISS | MISS |
| 96.4パーセント | MISS | MISS |
| 98.1パーセント | MISS | MISS |
| 12言語 | MISS | MISS |
| 20言語 | MISS | MISS |
| 大阪府 | HIT | HIT |
| 月間5000件 | MISS | MISS |
| 2025年2月15日 | MISS | MISS |
| 名古屋市 | HIT | HIT |
| サンフランシスコ | MISS | MISS |
| 3億円 | MISS | MISS |
| ベルリン | MISS | MISS |
| 山田健太 | HIT | HIT |
| ISO27001 | MISS | MISS |
| 月額4980円 | MISS | MISS |
| 鈴木一郎 | MISS | MISS |
| 18名 | MISS | MISS |

#### jaJP_3m.m4a

- macOS 26.5.1: **8/28 = 28.6% → 不成立**
- iOS 26.6.2: **8/28 = 28.6% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| 東京都渋谷区 | HIT | HIT |
| 2024年11月3日 | HIT | HIT |
| 渋谷ヒカリエ | MISS | MISS |
| 128名 | HIT | HIT |
| モジトルCore | MISS | MISS |
| 月額980円 | HIT | HIT |
| 田中健一 | MISS | MISS |
| 2019年 | HIT | HIT |
| 32万人 | MISS | MISS |
| 佐藤美咲 | MISS | MISS |
| 10分間 | HIT | HIT |
| 45秒 | MISS | MISS |
| 96.4パーセント | MISS | MISS |
| 98.1パーセント | MISS | MISS |
| 12言語 | MISS | MISS |
| 20言語 | MISS | MISS |
| 大阪府 | HIT | HIT |
| 月間5000件 | MISS | MISS |
| 2025年2月15日 | MISS | MISS |
| 名古屋市 | MISS | MISS |
| サンフランシスコ | MISS | MISS |
| 3億円 | MISS | MISS |
| ベルリン | MISS | MISS |
| 山田健太 | HIT | HIT |
| ISO27001 | MISS | MISS |
| 月額4980円 | MISS | MISS |
| 鈴木一郎 | MISS | MISS |
| 18名 | MISS | MISS |

#### enUS_3m.wav

- macOS 26.5.1: **11/25 = 44.0% → 不成立**
- iOS 26.6.2: **11/25 = 44.0% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| San Francisco | HIT | HIT |
| Salesforce Tower | HIT | HIT |
| November 3rd, 2024 | HIT | HIT |
| Kenichi Tanaka | MISS | MISS |
| 2019 | HIT | HIT |
| three hundred and twenty thousand | MISS | MISS |
| Misaki Sato | MISS | MISS |
| forty five seconds | MISS | MISS |
| ninety six point four percent | MISS | MISS |
| ninety eight point one percent | MISS | MISS |
| twelve languages | MISS | MISS |
| twenty languages | MISS | MISS |
| Chicago | HIT | HIT |
| five thousand | MISS | MISS |
| February 15th, 2025 | HIT | HIT |
| Austin, Texas | HIT | HIT |
| Berlin, Germany | HIT | HIT |
| three million dollars | MISS | MISS |
| Kenta Yamada | MISS | MISS |
| ISO 27001 | HIT | HIT |
| Ichiro Suzuki | MISS | MISS |
| eighteen | MISS | MISS |
| Montgomery Street | HIT | HIT |
| November 10th, 2024 | HIT | HIT |
| forty two engineers | MISS | MISS |

#### enUS_3m.m4a

- macOS 26.5.1: **11/25 = 44.0% → 不成立**
- iOS 26.6.2: **11/25 = 44.0% → 不成立**
- 両プラットフォームのHIT/MISS内訳は完全に一致した。

| キーワード | macOS | iOS |
|---|---|---|
| San Francisco | HIT | HIT |
| Salesforce Tower | HIT | HIT |
| November 3rd, 2024 | HIT | HIT |
| Kenichi Tanaka | MISS | MISS |
| 2019 | HIT | HIT |
| three hundred and twenty thousand | MISS | MISS |
| Misaki Sato | MISS | MISS |
| forty five seconds | MISS | MISS |
| ninety six point four percent | MISS | MISS |
| ninety eight point one percent | MISS | MISS |
| twelve languages | MISS | MISS |
| twenty languages | MISS | MISS |
| Chicago | HIT | HIT |
| five thousand | MISS | MISS |
| February 15th, 2025 | HIT | HIT |
| Austin, Texas | HIT | HIT |
| Berlin, Germany | HIT | HIT |
| three million dollars | MISS | MISS |
| Kenta Yamada | MISS | MISS |
| ISO 27001 | HIT | HIT |
| Ichiro Suzuki | MISS | MISS |
| eighteen | MISS | MISS |
| Montgomery Street | HIT | HIT |
| November 10th, 2024 | HIT | HIT |
| forty two engineers | MISS | MISS |

### 未達の原因について

**原因は本実行でも未確定である。** design.md §7 が挙げる候補((a)基準音声が
TTS合成であること、(b)プリセット等の設定、(c)認識モデル自体の精度、
(d)キーワード選定と正規化規則が表記差を吸収できていないこと)を分離する
対照実験は行っていない。

ただし確定テキストを読むと、(d)が相当な割合を占めていることは読み取れる。
実例:

- `128名` が MISS になった jaJP_10s の認識結果は
  `来場者は 102十 8名でした` である。「128」が `102十 8` と表記されて
  いるだけで、数を聞き取れていないわけではない。
- `株式会社モーンギフト` は `株式会社モーギフト`(macOS/iOS とも)で、
  長音1つの差である。
- en-US の `Moongift Incorporated` は `Moon Gifting Corporated` であり、
  これは表記差ではなく誤認識である。
- jaJP_3m の `96.4パーセント` `98.1パーセント` `45秒` は、認識結果では
  該当部分が丸ごと欠落している(`わずか秒は6は現在 12語で`)。これは
  表記差ではなく脱落である。

つまり **(d)表記差と (c)脱落・誤認識の両方が混在している。** 正規化規則の
改善だけでしきい値に届く見込みは無い。

**原因未調査のまま合格扱いにはしない**(design.md §7)。

### 確定テキスト(逐語)

#### jaJP_10s.wav

macOS 26.5.1:

```
東京都渋谷区で 2024年 11月 3日午後 3時株式会社モーギフトが新製品を発表しました。来場者は 102十 8名でした。
```

iOS 26.6.2: **macOS と1文字も違わなかった。**

#### jaJP_10s.m4a

macOS 26.5.1:

```
東京都渋谷区で 2024年 11月 3日午後 3時株式会社モギフトが新製品を発表しました。来場者は 102十 8名でした。
```

iOS 26.6.2: **macOS と1文字も違わなかった。**

#### enUS_10s.wav

macOS 26.5.1:

```
In San Francisco on November 3rd, 2024, at 3 p.m., Moon Gifting Corporated announced its new product. Attendance reached 128 people, filling the venue completely.
```

iOS 26.6.2: **macOS と1文字も違わなかった。**

#### enUS_10s.m4a

macOS 26.5.1:

```
In San Francisco on November 3rd, 2024, at 3 p.m., Moon Gifting Corporated announced its new product. Attendance reached 128 people, filling the venue completely.
```

iOS 26.6.2: **macOS と1文字も違わなかった。**

#### jaJP_3m.wav

macOS 26.5.1:

```
東京都渋谷区で 2024年 11月 3日午後 3時から株式会社モギフトの新製品発表会が開催されました。会場は渋谷光への 9界ホールで来場者は 128名でした。今回発表された新製品はオフライン製文字起こしアプリ文字取るです。バージョンは 1ビリオドリオド格は額 980円からとなっています発表会の冒頭では代表取締役の田中健一氏が拶しました。田中氏は 2019年の創業から 5年間で累計利用者数が 3200人を突破したことを紹介しました。続いて開発責任者の佐藤美咲氏が製品デモを実施しました。デモでは 10分間の会議音声をわずか秒は6は現在 12語で来年 3月までに二十言語への拡大を予定しています。質疑応答では大阪府から参加した中小企業の担当者から月間処理件数の上限について質問がありました。佐藤氏は上位プランであれば月間 500件まで処理可能であると回答しました発表会は午後 4時 30分に終了し加者にはベルとしてノート配されました。次回の発表会は 2025名古屋市で開催される予定です。ギフトは今後海外展開も加速させる方針です。 202年にはアメリカのサンフランシスに現地人を設立し、北米市場向けに英版の提供を強化します。年度の売上げ目標は円と発表されました。また欧州向けにはドツベリン点としてフランドイツ語への対応を2年中に完了させる計画です。セキュリティ面については情報セキュリティ責任者の山田健太氏が説明しました。全ての音声デーは端末で処理され外部へ送信は行わないと認証取得完了する見込みです。料金プランは個人向けのライトプランが月額 980円法人のビジ額 4980円エンタープライズプランは個別見積もりとなります。年間契約の場合は 2ヶ月分が割引になります。最後にカスタマーサポート窓口として平日午前 9時から午後時まで対応する専用チャットが新設が案内されました資料は公式サイトから2日以降に可能になる予定です。会場となったから徒歩ではもらず予定より 12名来まりましたスタッフは合計8名であたりました広報担当の鈴木氏は来年も同時期に開催予定であるとコメントしています。
```

iOS 26.6.2: **macOS と1文字も違わなかった。**

#### jaJP_3m.m4a

macOS 26.5.1:

```
東京都渋谷区で 2024年 11月 3日午後 3時から株式会社モギフトの新製品発表会が開催されました。会場は渋谷光への 9界ホールで来場者は 128名でした。今回発表された新製品はオフライン文字起こしアプリ文です。バージョンはオド格は 98からとなっています発表会の冒頭では代表取締役の田中健氏がしました。田中氏は 2019年の創業から年間で累計利用者数が2000人を突破したことを紹介しました。続いて開発責任者の佐藤美氏が製品デモを実施しました。デモでは 10分間の会議音声をわずかは現在語で来年 3月まで二十言語への拡大を予定しています。質疑応答では大阪府から参加した中小企業の担当者から月間処理件数の上限について質問がありました。佐藤氏は上位プランであれば間00件で処理可能であると回答した発表会は後に終了者には配回表会は2開催される予定。は今後海外展開も加速させる方針です。 202年にはアメリカのサンフランシスに現地を設立し、米市場向けに英版の提供を強化します。年度の売上目標は円と発表されましたまた欧州向けには点と完了させる計画です。キュリティ面については情報セキュリティ責任者の山田健太氏が説明しました。すべての音声データ端理外部取得完了する見込みで。料金プランは個人向けのライトプランが月額 980円法人のビジ額 4980円エンタープライズプランは個別見積もりとなります。年間契約の場合は 2ヶ月分が割引になります。最後にカスタマーサポート窓口として平日午前 9時から午後まで対応する専用ャットが案内した公式イト以降予定。会場となったから徒歩にもらず予定より 12集ましたスタッフ合計担当氏は来年も同時期に開催予定であるとコメントしています。
```

iOS 26.6.2: **macOS と1文字も違わなかった。**

#### enUS_3m.wav

macOS 26.5.1:

```
In San Francisco on November 3rd, 2024, at 3 p.m., Moon Gifting Corporated announced its new product. Attendance reached 128 people, filling the venue completely. The event was held on the ninth floor of the sales force tower, and the new product introduced was an offline speech transcription app called Moji Talcore, priced starting at $9.80 per month. The opening remarks were delivered by CEO Kenichi Chinaka, who explained that since the company's founding in 2019, cumulative users had surpassed 320,000 across five years, following his remarks. Chief Product Officer Misaki Sado demonstrated the product live on stage. During the demonstration, a 10 minute meeting recording was transcribed in just 45 seconds. Recognition accuracy reached 96.4% for Japanese and 98.one% for English. The product currently supports 12 languages, with plans to expand to 20 languages by next March, during the question and answer session, a representative from a small business in Chicago asked about the monthly processing limit. Soto replied that the higher tier plan allows up to 5000 files per month. The event concluded at 4.30 p.m. and attendees received a custom notebook as a souvenir. The next event is scheduled for February 15th, 2025, in Austin, Texas, looking ahead, Moon Gifting Corporated plans to accelerate its international expansion. In the fall of 2025, the company will establish a subsidiary in Berlin, Germany, to strengthen its offering for the European market, targeting 1st year revenue of $3 million. The pricing plans include a light plan at $9.80 per month for individuals, a business plan at $49.80 per month, and a custom quote for the Enterprise plan. Security lead Kento Yamada explained that all audio data is processed entirely on device. With no data ever transmitted to external servers. The company expects to complete its ISO 27,001 certification by the end of 2025. Public Relations Manager Hiro Suzuki confirmed that the next announcement event will take place at the same time next year, despite the rain, 12 more attendees than expected showed up, and a staff of 18 people managed the event smoothly. The venue is a 3 minute walk from Montgomery Street Station, making it easy for attendees to reach by public transit. Customer support will soon offer a dedicated chat channel available on weekdays from 9 AM to 6 PM presentation materials will be available for download from the official website starting November 10th. 2024. Engineering director Misaki Sado added that a beta version for macOS will ship in January, 2025. followed by a Windows release in March, 2025, and that the team currently numbers 42 engineers across 3 offices.
```

iOS 26.6.2(macOS と差異あり):

```
In San Francisco on November 3rd, 2024, at 3 p.m., Moon Gifting Corporated announced its new product. Attendance reached 128 people, filling the venue completely. The event was held on the ninth floor of the sales force tower, and the new product introduced was an offline speech transcription app called Moji Talcore, priced starting at $9.80 per month. The opening remarks were delivered by CEO Kenichi Chinaka, who explained that since the company's founding in 2019, cumulative users had surpassed 320,000 across 5 years, following his remarks. Chief Product Officer Misaki Sado demonstrated the product live on stage. During the demonstration, a 10 minute meeting recording was transcribed in just 45 seconds. Recognition accuracy reached 96.4% for Japanese and 98.one% for English. The product currently supports 12 languages, with plans to expand to 20 languages by next March, during the question and answer session, a representative from a small business in Chicago asked about the monthly processing limit. Soto replied that the higher tier plan allows up to 5000 files per month. The event concluded at 4.30 p.m. and attendees received a custom notebook as a souvenir. The next event is scheduled for February 15th, 2025, in Austin, Texas, looking ahead, Moon Gifting Corporated plans to accelerate its international expansion. In the fall of 2025, the company will establish a subsidiary in Berlin, Germany, to strengthen its offering for the European market, targeting 1st year revenue of $3 million. The pricing plans include a light plan at $9.80 per month for individuals, a business plan at $49.80 per month, and a custom quote for the Enterprise plan. Security lead Kento Yamada explained that all audio data is processed entirely on device. With no data ever transmitted to external servers. The company expects to complete its ISO 27,001 certification by the end of 2025. Public Relations Manager Hiro Suzuki confirmed that the next announcement event will take place at the same time next year, despite the rain, 12 more attendees than expected showed up, and a staff of 18 people managed the event smoothly. The venue is a 3 minute walk from Montgomery Street Station, making it easy for attendees to reach by public transit. Customer support will soon offer a dedicated chat channel available on weekdays from 9 AM to 6 PM presentation materials will be available for download from the official website starting November 10th. 2024. Engineering director Misaki Sado added that a beta version for macOS will ship in January, 2025. followed by a Windows release in March, 2025, and that the team currently numbers 42 engineers across 3 offices.
```

#### enUS_3m.m4a

macOS 26.5.1:

```
In San Francisco on November 3rd, 2024, at 3 p.m., Moon Gifting Corporated announced its new product. Attendance reached 128 people, filling the venue completely. The event was held on the ninth floor of the salesforce tower, and the new product introduced was an offline speech transcription app called Moji Talcore, priced starting at $9.80 per month. The opening remarks were delivered by CEO Kenichi Chinaka, who explained that since the company's founding in 2019, cumulative users had surpassed 320,000 across five years, following his remarks. Chief Product Officer Misaki Sado demonstrated the product live on stage. During the demonstration, a 10 minute meeting recording was transcribed in just 45 seconds. Recognition accuracy reached 96.4% for Japanese and 98.one% for English. The product currently supports 12 languages, with plans to expand to 20 languages by next March. During the question and answer session, a representative from a small business in Chicago asked about the monthly processing limit, Soto replied that the higher tier plan allows up to 5000 files per month. The event concluded at 4.30 p.m. and attendees received a custom notebook as a souvenir. The next event is scheduled for February 15th, 2025, in Austin, Texas, looking ahead, Moon Gifting Corporated plans to accelerate its international expansion. In the fall of 2025, the company will establish a subsidiary in Berlin, Germany, to strengthen its offering for the European market, targeting first year revenue of $3 million. The pricing plans include a light plan at $9.80 per month for individuals, a business plan at $49.80 per month, and a custom quote for the Enterprise plan. Security lead Kento Yamada explained that all audio data is processed entirely on device. With no data ever transmitted to external servers. The company expects to complete its ISO 27,001 certification by the end of 2025. Public Relations Manager Ichero Suzuki confirmed that the next announcement event will take place at the same time next year, despite the rain, 12 more attendees than expected showed up, and a staff of 18 people managed the event smoothly. The venue is a 3 minute walk from Montgomery Street Station, making it easy for attendees to reach by public transit. Customer support will soon offer a dedicated chat channel available on weekdays from 9 AM to 6 PM presentation materials will be available for download from the official website starting November 10th. 2024. Engineering director Misaki Sado added that a beta version for macOS will ship in January, 2025. followed by a Windows release in March, 2025, and that the team currently numbers 42 engineers across 3 offices.
```

iOS 26.6.2: **macOS と1文字も違わなかった。**

## 実行できなかった項目(未実施)

| 項目 | 理由 |
|---|---|
| `DeviceUnsupportedException` の発火 | macOS 26 未満 / iOS 26 未満の実機が無い。`if #available` 分岐であり、他に発火手段が無い |
| example app の UI 経路(ファイルピッカー → 同意ダイアログ → 進行表示) | integration_test は API を直接呼ぶため UI を通らない。人手での実行が別途必要である |
| iOS 27 実機での本番実装E2E | 1プラットフォーム1台という方針に従い、下限である iOS 26.6.2 を選んだ |
| 非 Apple Silicon(Intel Mac)での確認 | 該当機が無い |
| `ModelState.downloading` の観測 | `AssetInventory.status == .downloading` になる瞬間を Dart 側から狙って作る手段が無かった。ダウンロード中に `checkModel()` を並行して呼ぶ測定は本実行に入れていない |

## このE2Eで確認できないこと

- **人間の自然発話に対する精度。** 基準音声はすべて `say` によるTTS合成音声
  である。
- **実環境(ノイズあり)での精度。** 基準音声セットはクリーン音声のみ。
- **ネイティブ Task が実際に早期停止したか**(手順4)。Dart 側から観測
  できるのは「セグメントが届かない」ことまでである。
- **長時間連続稼働・メモリ挙動。** 1回の test 実行は40秒程度である。

## 本検証のために追加したもの

| ファイル | 内容 |
|---|---|
| `apps/example/integration_test/darwin_baseline_e2e_test.dart` | 本E2Eのドライバ |
| `apps/example/tool/stage_baseline_audio.sh` | 基準音声を example app のアセットへ複製する |
| `apps/example/assets/baseline-audio/.gitkeep` | アセットディレクトリの追跡用(実体は .gitignore) |
| `apps/example/pubspec.yaml` | `assets/baseline-audio/` の宣言を追加 |
| `.gitignore` | 複製された音声を除外 |

**`packages/offline_stt_darwin/` 配下のコードは1行も変更していない。**
バグが見つからなかったためである。

## 次にやるべきこと

1. **F-1(`LocaleUnsupportedException` 到達不能)を design.md 側で整理する。**
   Android と Darwin の両方で同じ構造であり、実装ではなく設計の問題である。
2. **F-2(`CancelledException` 到達不能)を design.md §5 に明記する。**
3. **F-3(iOS で進捗 fraction が 0→1 のみ)を README / example app の実装
   指針へ書く。**
4. **キーワード包含率の未達原因の分離。** 正規化規則の見直し(表記差)と
   脱落・誤認識の切り分けは別々に扱う必要がある。
5. **example app の UI 経路を人手で実行する。**
6. **iOS 27 実機での再実行**(供給範囲の確認)。
