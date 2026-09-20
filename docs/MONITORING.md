# 依存プラットフォームの変更監視手順

対応 Issue: #67。関連: [E2E_CHECKLIST.md](../E2E_CHECKLIST.md)、
[VERSION_POLICY.md](./VERSION_POLICY.md)(Issue #68)。

## この文書の位置づけ

`offline_stt` は**モデルを一切同梱せず、OS / ブラウザが持つ認識エンジンだけ
を使う**(requirements.md §2 / NFR-3)。この設計上、本ライブラリの動作は
**自分たちが管理していない4つの外部実装の挙動にそのまま依存する**。依存先が
変われば、こちらのコードを1行も変えていなくても動作が変わる。

したがって「リリースしたら終わり」にはできず、依存先の変更を定期的に見に
行き、必要なら基準音声E2Eを再実行する運用が要る。**本書はその手順書である。**

**本書は手順書であって、実行記録ではない。** リポジトリ自身が定期的に外部
サイトを見に行くことはできないため、実行するのは人間(またはリポジトリ外の
仕組み)である。後述の「実行記録」節のとおり、**四半期ごとの定期実行は
これまで一度も行われていない。**

## 1. 何を監視するか

### 1.1 Android — `android.speech.SpeechRecognizer` + Google Play services

> **ML Kit GenAI / AICore は監視対象ではない。** 初期設計はML Kit GenAI
> Speech Recognition(AICore)を前提としていたが、M0検証でPixel 6実機の
> `com.google.android.aicore` が実体の無いstub版であり、Google Play ストア
> 自身が同端末を非対応と表示することが判明したため、**この方針は破棄済み
> である**(design.md §4.3 冒頭、spikes/android/RESULTS.md)。現在の
> バックエンドは Android 標準の `android.speech.SpeechRecognizer`
> (`createOnDeviceSpeechRecognizer`)である。リポジトリ内や過去のIssueに
> AICore前提の記述が残っていても、それは古い記述である。

| 見るもの | 場所 |
|---|---|
| `android.speech.SpeechRecognizer` / `RecognitionSupport` / `RecognizerIntent` のAPIリファレンス差分 | https://developer.android.com/reference/android/speech/SpeechRecognizer |
| Android のプラットフォームリリースノート・Behavior changes(新OSでのオンデバイス認識の扱い) | https://developer.android.com/about/versions |
| Google Play services のリリースノート(オンデバイス言語パックの提供主体) | https://developers.google.com/android/guides/releases |

**特に注視する点**(いずれも実測で判明した挙動であり、OS / Play services 側の
更新で変わりうる):

- `onResults()` の `RESULTS_RECOGNITION` が `null` になり、確定テキストが
  得られない挙動(design.md §4.3)。本実装は直前の `onPartialResults()` の
  最上位候補を確定結果として採用することで成立している。**この挙動が直れば
  採用ロジックを見直す必要があり、悪化すれば文字起こしが空になる。**
- `triggerModelDownload()` の `ModelDownloadListener` が完了を通知しない
  挙動(design.md §4.3、`packages/offline_stt_android/README.md` §4 制約2)。
  本実装は `checkRecognitionSupport()` の再照会で完了判定している。
- `EXTRA_AUDIO_SOURCE` + 3つの付随Extra(`..._CHANNEL_COUNT` /
  `..._ENCODING` / `..._SAMPLING_RATE`)によるファイル入力の受理。
- `checkRecognitionSupport()` が API 33 以上でしか無いこと(API 31/32 が
  `unavailable` に倒れる根拠。design.md §4.3)。

### 1.2 Web — Chrome のオンデバイス Web Speech API

| 見るもの | 場所 |
|---|---|
| `SpeechRecognition.available()` / `install()` / `start(audioTrack)` / `processLocally` の仕様変更 | https://wicg.github.io/speech-api/ および https://developer.mozilla.org/en-US/docs/Web/API/Web_Speech_API |
| Chrome の機能ステータス(オンデバイスWeb Speech) | https://chromestatus.com/ |
| Chrome 安定版のリリース情報 | https://developer.chrome.com/release-notes |

**特に注視する点**:

- 動作下限として文書化している **Chrome 142**(オンデバイスWeb Speechの
  リグレッションが修正されたバージョン。requirements.md NFR-4)。
  実機検証は Chrome 153 でのみ行っている。
- `install()` が進捗イベントを持たず `Promise<boolean>` を返すだけである
  こと(`DownloadProgress(fraction: null)` の不定進捗に写像している根拠。
  design.md §4.1)。進捗APIが追加されたら不定進捗をやめられる。
- `continuous = true` のとき、再生終了後も `MediaStreamTrack` が `live` の
  まま無音を流し続けるため、`source.onended` で明示的に `recognition.stop()`
  を呼ばないと `onend` が発火しないこと(design.md §4.1・§8 未決事項4)。
- 確定結果が形態素単位で空白区切りされること(`東京 都 渋谷 で ...`)。
- `on-device-speech-recognition` Permissions Policy の既定値が `'self'` で
  あること(`localhost` / `https` 配信が必要な根拠)。

### 1.3 Windows — WinAppSDK / Windows AI APIs

| 見るもの | 場所 |
|---|---|
| Windows AI APIs Speech Recognition のドキュメント(最終更新日が動いたら差分を読む) | https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition |
| `Microsoft.Windows.AI.Speech` 名前空間のAPIリファレンス | https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech |
| WinAppSDK のリリースノート(1.7 系サービシング / 2.0) | https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels |
| winapp CLI の Flutter 向け手順 | https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/guides/flutter |

**特に注視する点**:

- `AIFeatureReadyState` の値の増減。WinAppSDK 2.0 で `CapabilityMissing` /
  `NotCompatibleWithSystemHardware` / `OSUpdateNeeded` の3値が増えている
  (design.md §4.4)。実装(`model_availability.cpp`)は全バージョンに存在
  する値のみを明示列挙し残りを `default` で `unavailable` に倒しているため
  値が増えても壊れないが、**新しい値が `downloadable` に写像すべきもので
  あった場合は正しい状態を返せない。**
- 公式ドキュメントの「Recommended UX pattern」が挙げる `EnsureNeeded` が
  実際のenumに存在しない、というドキュメント間の不一致(design.md §4.4)。
  これが解消されたかどうか。
- `BatchRecognition.RecognizeFromFile()` の対応フォーマットに関する記述が
  追加されたかどうか(design.md §8 未決事項1 は**未確定のまま**であり、
  M4は「常に Media Foundation で 16kHz・モノラル・16-bit PCM の wav へ
  変換する」という処置で回避している。記述が追加されれば変換の要否と
  出力形式の推定を確定できる)。
- ロケール指定APIが追加されたかどうか(design.md §8 未決事項2。現在は
  1件も存在せず、`locale` 引数がWindowsでは無視される根拠になっている)。
- `MaxVersionTested` の要求値(現在 `10.0.26226.0` 以降)。
- winapp CLI の手順変更(`.winapp/include` の展開先が変わると
  `packages/offline_stt_windows/windows/CMakeLists.txt` の自動検出が外れる)。

> **前提として、Windowsは一度も動かしていない。** 本リポジトリにWindows実機
> は存在せず、ビルドもMSIX化も認識も一度も行っていない(Issue #58)。
> したがってWindowsについては「変更を監視する」以前に**初回の検証が未了
> である**。この状態で監視だけを続けても、変更が壊したのか元から動かないのか
> を区別できない。

### 1.4 Darwin(iOS / macOS)— Speech framework

| 見るもの | 場所 |
|---|---|
| `SpeechAnalyzer` / `SpeechTranscriber` / `AssetInventory` のAPIリファレンス差分 | https://developer.apple.com/documentation/speech |
| iOS / macOS のリリースノート・ベータ | https://developer.apple.com/documentation/ios-ipados-release-notes/ および https://developer.apple.com/documentation/macos-release-notes/ |

**特に注視する点**:

- `supportedLocales` の件数・内容。**OSバージョンによって異なることが実測
  で判明している**(macOS 26.5.1: 30件、iOS 27.0: 45件)。静的リストを持たず
  実行時照会にしているのはこのためである(design.md §4.2)。
- `AssetInventory.status(forModules:)` の `.installed` が「予約(reserve)」
  に連動する一時状態であり、`installedLocales` とは別軸であること
  (design.md §4.2)。FR-1の4値への写像がこの性質に依存している。
- `SpeechTranscriber.Preset` の追加・既定値変更。**プリセット違いだけで
  キーワード包含率が最大20ポイント以上動く**実測がある(design.md §7)。
- iOSシミュレータで `SpeechTranscriber.isAvailable` が `false` になる制約
  (E2EがCIに載せられない根拠)。

### 1.5 OSベータ・ツールチェーン

四半期の確認では、次のベータ・プレビューに**本ライブラリが依存するAPIの変更
が含まれていないか**も見る。含まれていた場合は正式版を待たずに追従の検討を
始める(判断基準は [VERSION_POLICY.md](./VERSION_POLICY.md))。

| 対象 | 場所 |
|---|---|
| Android Developer Preview / Beta | https://developer.android.com/about/versions |
| iOS / macOS ベータ(および WWDC のセッション) | https://developer.apple.com/news/releases/ |
| Windows Insider Preview ビルド | https://blogs.windows.com/windows-insider/ |
| Chrome Beta / Canary | https://developer.chrome.com/release-notes |
| Flutter stable のリリース | https://docs.flutter.dev/release/release-notes |

ツールチェーン側(Flutter / Dart SDK / Pigeon / melos / AGP / Kotlin /
Gradle / WinAppSDK)の固定値そのものの扱いは本書の対象外であり、
[VERSION_POLICY.md](./VERSION_POLICY.md) が扱う。

## 2. いつ確認するか

### 2.1 定期(四半期ごと)

**3か月に1回**、上記1.1〜1.5をひととおり確認する。四半期という間隔にした
のは、監視対象の4実装のうちOSプラットフォーム3つがおおむね年1回のメジャー
更新 + 随時のマイナー更新という周期で動いており、メジャー更新を確実に1回の
確認サイクル内で捕まえられる粒度がこの程度だからである。

### 2.2 随時(イベント駆動)

定期確認を待たずに確認する。いずれも「動作が変わりうる」ことが分かっている
タイミングである。

- Android / iOS / macOS / Windows のメジャーバージョンが公開されたとき
- Chrome の安定版メジャーバージョンが上がったとき(オンデバイスWeb Speech
  に関する変更が release notes / chromestatus にあるとき)
- WinAppSDK の新しいリリース(特に 1.7 系サービシングと 2.0)
- Flutter stable の更新(`FLUTTER_VERSION` の追従判断)
- CIが、こちらのコードを変えていないのに落ちたとき

## 3. 何を再実行するか

確認の結果「依存先が変わった可能性がある」と判断したら、**基準音声による
E2Eを再実行する**。手順は既存のチェックリストをそのまま使い、本書では
重複させない。

| 範囲 | チェックリスト |
|---|---|
| 入口(なぜCIに載せないのか・基準音声・包含率の算出・しきい値) | [E2E_CHECKLIST.md](../E2E_CHECKLIST.md) |
| Android | [packages/offline_stt_android/E2E_CHECKLIST.md](../packages/offline_stt_android/E2E_CHECKLIST.md) |
| iOS / macOS | [packages/offline_stt_darwin/E2E_CHECKLIST.md](../packages/offline_stt_darwin/E2E_CHECKLIST.md) |
| Windows | [packages/offline_stt_windows/E2E_CHECKLIST.md](../packages/offline_stt_windows/E2E_CHECKLIST.md) |
| Web | [packages/offline_stt_web/E2E_CHECKLIST.md](../packages/offline_stt_web/E2E_CHECKLIST.md) |

再実行の範囲は次のように決める。

- **変更が特定のプラットフォームに閉じている場合**: そのプラットフォームの
  チェックリストのみ。
- **どのプラットフォームに影響するか分からない場合**: 実機が用意できる
  全プラットフォーム。
- **最低限**: 基準音声 `jaJP_10s` のキーワード包含率。3プラットフォーム
  (Darwin / Web / Android)がいずれも 66.7%(4/6)という同じ値を出しており
  (E2E_CHECKLIST.md「精度に関する既知の事実」)、**この値からの変動は依存先
  の変化を検出する指標として使える。**

**包含率は合否ゲートではなく記録項目である。** design.md §7 のしきい値
(ja-JP 95%以上が合格、90〜94% は条件付き合格 / 要確認、90%未満は不成立。
en-US は 95%以上が合格)に対して、**実測できたプラットフォームはいずれも
達していない。不成立の原因は未確定である**(E2E_CHECKLIST.md および
design.md §7 の注記)。原因が未確定のまま合格扱いにしてはならない。

CI(`.github/workflows/ci.yml`)が検証するのは静的解析・ユニットテスト・
フォーマット・`dart doc` と、`apps/example` の各プラットフォーム向け
コンパイルだけである。**認識E2EはCIでは一切検証されない。**

## 4. 結果をどこへ記録するか

E2E_CHECKLIST.md「結果の記録」節の表に従い、実行日・検証環境(OS・端末・
ブラウザ・SDKの各バージョン)・項目ごとの結果を、対応するIssue
(Darwin #40 / Android #50 / Windows #58。Webは**専用Issueが無いため新規に
立てる**)へ記録する。**未実施の項目は「合格」ではなく「未実施」と書く。**

依存先の変更を実際に見つけた場合は、記録先が別になる。

- APIの挙動・制約が変わった → design.md の該当節(§4.1〜§4.4、§5、§8)
- 固定しているバージョンを動かす必要が出た → [VERSION_POLICY.md](./VERSION_POLICY.md)(Issue #68)
- 監視対象そのものが変わった(APIの廃止・差し替え) → 本書の1節

## 5. 実行記録

| 実施日 | 範囲 | 確認したもの | 再実行したE2E | 結果 |
|---|---|---|---|---|
| — | — | — | — | **四半期ごとの定期実行は一度も行われていない。** |

**この表が空であることは、この運用がまだ一度も回っていないことを意味する。**
本書(Issue #67)が用意したのは手順であって実行実績ではない。Windows に
ついてはそもそも初回の検証すら未了である(Issue #58)ことは 1.3 節に
書いたとおりである。
