# 将来拡張の設計レベル評価: タイムスタンプ / マイク入力 / 同時複数セッション

対応 Issue: #69。関連: design.md §2(公開API)・§3(状態遷移)・§4.1〜§4.4
(プラットフォーム別設計)、requirements.md §3「対象外」。

## この文書の位置づけ

tasks.md の継続タスクにある「将来拡張の検討: タイムスタンプ、マイク入力、
同時複数セッション」に対する**設計レベルの評価**である。3件のいずれについても
**実装はしていないし、実装することを決めてもいない。** 各プラットフォームの
APIが実際に何を提供しているか、入れるとしたら何を変えることになるか、そして
**今それを塞いでいるものは何か**を、判断できる材料の形にまとめたものである。

出典は次の3種類であり、本文中でどれに拠っているかを区別して書く。

1. **本リポジトリの実測** — `spikes/*/RESULTS.md`、design.md §4.x に記録された
   Pixel 6 / macOS 26.5.1 / iPhone 17 / Chrome 153 での測定。
2. **公式ドキュメントの記載** — 各APIリファレンス。URLを併記する。
3. **未確認** — どちらでも確かめられなかったもの。**推測で埋めない。**

### 3件に共通する前提(先に読むこと)

**どの拡張よりも先に解くべき問題が残っている。**

- **精度がどのプラットフォームでもしきい値に届いていない。** Darwin
  (macOS 26.5.1)・Web(Chrome 153)・Android(Pixel 6)の3つが、同一の
  基準音声 `jaJP_10s` でちょうど 66.7%(4/6)という同率である。design.md §7
  のしきい値は ja-JP 95%以上が合格・90〜94%が条件付き合格・90%未満が不成立、
  en-US は 95%以上が合格であり、**実測できた3プラットフォーム(Darwin /
  Web / Android)はいずれも不成立である。そしてその原因は未確定である。**
  (README.md「精度について」、E2E_CHECKLIST.md、design.md §7 の注記)
- **本番実装(`packages/` 配下)に対して実機E2Eを通して実行した実績が、
  どのプラットフォームにも無い。** 上記の実測値はすべてM0スパイク
  (`spikes/` 配下の独立した検証コード)のものである。
- 実機待ちのIssueが未処理のまま残っている: #7(iOS 26実機)、#11〜#13
  (AICore Android。バックエンド差し替え済みのため実質的に過去の記録)、
  #40(Darwin E2E)、#50(Android E2E)。
  #65(公開)は利用者の判断待ちである。

したがって本書の結論は3件とも「**今は着手しない**」である。以下は、
着手すると決めたときに読む材料である。

---

## 1. タイムスタンプ

「認識結果のどの語が音声のどの時刻に対応するか」を `TranscriptSegment` に
持たせる拡張。字幕生成・頭出し・話者区間の切り出しといった用途がこれを要求する。

### 1.1 各プラットフォームAPIが実際に提供しているもの

| プラットフォーム | 提供の有無 | 粒度 | 制約 |
|---|---|---|---|
| Android | **あり(API 34以上)** | 語単位の**開始オフセットのみ** | 終了時刻・長さのフィールドが無い。確定結果でしか取れない |
| iOS / macOS | **あり(OS 26)** | 語/ラン単位の**時間範囲**(開始+終了)。加えて結果単位の範囲が常に付く | 逐次(volatile)結果にも付くかは未確認 |
| Web | **無い** | — | 仕様のIDLに時刻を表すメンバーが1つも無い |

**Android**: `android.speech.RecognitionPart`(API 34)が
`getRawText()` / `getFormattedText()` / `getConfidenceLevel()` /
**`getTimestampMillis()`** を持つ。`getTimestampMillis()` は
「認識セッション開始からのこのパートの先頭までの非負オフセット(ミリ秒)。
`RecognizerIntent.EXTRA_REQUEST_WORD_TIMING` で要求した場合」と定義されて
いる(https://developer.android.com/reference/android/speech/RecognitionPart)。
**開始オフセットだけであり、終了時刻も長さも無い。**
受け取りは `SpeechRecognizer.RECOGNITION_PARTS`(API 34、値
`"recognition_parts"`)キーで `ArrayList<RecognitionPart>` として行い、
**渡されるのは `onResults()` と `onSegmentResults()` だけである**
(https://developer.android.com/reference/android/speech/SpeechRecognizer)。
`EXTRA_REQUEST_WORD_TIMING` 自体のドキュメントも
「**final recognition results** における各語のタイムスタンプ」と明記している。

**iOS / macOS**: `SpeechTranscriber.Result.text` は `AttributedString` であり、
`SpeechTranscriber.ResultAttributeOption.audioTimeRange`(OS 26.0)を指定
すると `AttributeScopes.SpeechAttributes.TimeRangeAttribute` の属性が付く
(https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange)。
取り出しには `AttributedString.rangeOfAudioTimeRangeAttributes(intersecting:)`
が用意されている。さらに、オプション指定が無くても
`SpeechModuleResult.range`(「この結果が対応する音声入力の範囲」)が常に
付いている(https://developer.apple.com/documentation/speech/speechmoduleresult/range)。
**3プラットフォームの中で最も素直にタイムスタンプが取れる。**

**Web**: 仕様(https://webaudio.github.io/web-speech-api/)の
`SpeechRecognitionAlternative` は `transcript` と `confidence` の2つのみ、
`SpeechRecognitionResult` は `length` / `item()` / `isFinal` のみである。
**時刻を表すメンバーは存在しない。** `processLocally` を立てても増えない。

### 1.2 入れるとしたら何を変えるか

- **公開API**: `TranscriptSegment`(design.md §2.2)は現在 `text` と
  `isFinal` の2フィールドである。ここに時間情報を足すことになる。
  `packages/offline_stt/lib/src/transcript_segment.dart` のデータ型、
  `pigeons/offline_stt_events.dart`、および Kotlin / Swift の2言語の
  生成物と受け口。
- **型の選び方が難しい。** 取れるものがプラットフォームごとに違いすぎる。
  - Android: 開始オフセットのみ(終了が無い)
  - Darwin: 開始+終了
  - Web: 何も無い
  「開始+終了」の型にすると Android では終了を埋められず、「開始のみ」の
  型にすると Darwin の情報を捨てることになる。**null 許容にする
  場合、Webでは常に null になる。** すなわちこの拡張は
  「全プラットフォームで同じ形の結果を返す」という本ライブラリの前提
  (requirements.md §7 共通API)を、初めて部分的に壊すことになる。
  フォールバックで埋めることはリポジトリの方針上できない。

### 1.3 今これを塞いでいるもの

- **Androidでは、語タイムスタンプが載る経路が現に壊れている。** 語
  タイムスタンプは `onResults()` / `onSegmentResults()` にしか渡らない。
  ところが本実装の前提は「**`onResults()` の `RESULTS_RECOGNITION` が
  `null` になり確定テキストが得られないため、直前の `onPartialResults()`
  の最上位候補を確定結果として採用する**」である(design.md §4.3。Pixel 6
  実機での2回の独立実行いずれでも再現)。`onPartialResults()` には
  `RECOGNITION_PARTS` は渡らない。**したがって現状の Android では、
  タイムスタンプを取る経路そのものが使えない。** この挙動が Pixel 6 固有
  なのか全端末共通なのかは未確定である(design.md §8 未決事項8)。
- **Androidでは API 34 以上が必要になる。** 現在の `minSdk` は 31、
  実際に動く下限は `checkRecognitionSupport()` の 33 である
  (design.md §4.3)。タイムスタンプを使う機能だけがさらに 34 を要求する。
- **Webでは原理的に提供できない。** APIに無いものは作れない。

### 1.4 評価

**Darwinだけなら安く入る。Web では原理的に不可能で、Android では現に
壊れている経路の先にある。**
「共通APIで3プラットフォームを揃える」という本ライブラリの性格からすると、
最も割に合わない拡張である。Darwin専用の追加APIとして切り出すなら成立する
が、それは requirements.md §7 の共通API方針からの逸脱になる。

---

## 2. マイク入力

ファイルではなくライブのマイク入力を認識する拡張。requirements.md §3
「対象外」が「**マイクからのリアルタイム認識(将来拡張候補。v1はファイル
入力専用)**」と明記しており、v1のスコープ外であることは当初から決まっている。

### 2.1 各プラットフォームAPIが実際に提供しているもの

| プラットフォーム | 入口 | 必要な権限・宣言 |
|---|---|---|
| Android | `EXTRA_AUDIO_SOURCE` を**設定しない**だけ | `RECORD_AUDIO` |
| iOS / macOS | `AnalyzerInput` の `AsyncSequence` を自前で作って渡す | `NSMicrophoneUsageDescription` |
| Web | `start()` を**引数なしで**呼ぶ | UA仲介のユーザー同意 |

**Android**: `EXTRA_AUDIO_SOURCE`(API 33)のドキュメントが
「このExtraが設定されていない場合、または認識器がこの機能をサポートしない
場合、**認識器は音声のためにマイクを開き、認識終了時に閉じる**」と書いて
いる(https://developer.android.com/reference/android/speech/RecognizerIntent)。
つまりマイク入力は「PFDパイプを渡すのをやめる」だけで得られる。

> **権限について、ドキュメントと本リポジトリの実測が食い違っている。**
> `SpeechRecognizer` のクラスドキュメントは「**このクラスを使うには
> アプリケーションが `Manifest.permission.RECORD_AUDIO` 権限を持っている
> 必要がある**」と無条件に書いており、`EXTRA_AUDIO_SOURCE` 使用時の
> 例外は文書化されていない。一方、本リポジトリのPixel 6実機での実測は
> 「`RECORD_AUDIO` を一切付与せずに実行したが
> `ERROR_INSUFFICIENT_PERMISSIONS` は発生せず、`onReadyForSpeech` →
> `onBeginningOfSpeech` → `onPartialResults` と正常に進行した」である
> (design.md §4.3、spikes/android/RESULTS.md)。**ファイル入力では
> 実測上不要だが、マイク入力にすれば必要になる**、というのが素直な解釈
> である。マイク入力を入れる場合、`RECORD_AUDIO` は避けられない。
> プラグインの `AndroidManifest.xml`
> (`packages/offline_stt/android/src/main/AndroidManifest.xml`)は現在空であり、
> パーミッションを一切追加していない。これを変えることになる。

また同クラスのドキュメントは「**このAPIは連続認識のために使うことを意図して
いない**」とも明記している。マイク入力の典型的な用途は連続認識であり、
この注意書きと正面から衝突する。

**iOS / macOS**: `SpeechAnalyzer` は時刻付き音声バッファの
`AsyncSequence<AnalyzerInput>` を `analyzeSequence(_:)` /
`start(inputSequence:)` に渡す設計であり、**アナライザ自身はフォーマット
変換をしない**(`bestAvailableAudioFormat(compatibleWith:)` と
`AnalyzerInputConverter` を使う)
(https://developer.apple.com/documentation/speech/speechanalyzer)。
マイク用の簡便な入口 `CaptureInputSequenceProvider` は存在するが、
**iOS/iPadOS 27.0 のAPIであり 26.0 には無い**
(https://developer.apple.com/documentation/speech/captureinputsequenceprovider)。
本ライブラリの下限は OS 26(requirements.md NFR-4)であるため、
**26 向けには入力シーケンスを自前で組む必要がある。** その具体的な配線
(AVAudioEngine のタップを使うのか等)は**APIリファレンスに書かれておらず
未確認である。**

権限については、Appleの「Asking Permission to Use Speech Recognition」が
`NSSpeechRecognitionUsageDescription` +
`SFSpeechRecognizer.requestAuthorization(_:)` のフローについて
「**これは `SFSpeechRecognizer` による音声認識にのみ適用される。
`SpeechAnalyzer` のトランスクライバモジュールはユーザーの音声データを
Appleのサーバーへ送らない**」と明記している
(https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)。
**すなわち音声認識の認可は不要である。** 一方、マイク取得には
`NSMicrophoneUsageDescription` が要る
(https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)。
iOSでの `AVAudioSession` のカテゴリ設定・アクティブ化の要否は
Speech framework のドキュメントに記載が無く**未確認である。**

**Web**: `start()` を引数なしで呼べばマイクになる
(「指定しない場合、サービスはユーザーのマイクからの音声を認識しようと
する」https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition/start)。
つまりマイク入力は**Webでは最も簡単である** —— 現在の実装が
`AudioBufferSourceNode` → `MediaStreamAudioDestinationNode` →
`start(audioTrack)` というパイプラインをわざわざ組んでいる(design.md §4.1)
のは、ファイル入力を実現するためだからである。

ただし `processLocally: true` との併用時に権限プロンプトがどうなるかは
**MDNにも仕様にも記載が無く未確認である。** また design.md §4.1 が記録
している終了検出の作法(`source.onended` で明示的に `recognition.stop()`
を呼ぶ)は、そもそも「再生が終わる」という概念があってこそ成り立つ。
**マイク入力には終わりが無いため、終了検出の設計を作り直すことになる。**

### 2.2 入れるとしたら何を変えるか

**公開API(design.md §2.1)の追加になる。** 現在の
`transcribeFile(TranscribeRequest)` は `path` を必須に取る。マイク入力には
パスが無いため、同じメソッドでは表せない。別メソッド(例:
`transcribeMicrophone(locale)`)を足すことになり、`pigeons/` の1本の
スキーマ・2言語の生成物・3実装すべてに波及する。

さらに、設計の前提のうち**ファイル入力であることに依存している部分が
そのまま使えなくなる**。

- **終了条件が無い。** design.md §3 のセッション遷移
  (`idle→decoding→recognizing→done`)は入力が尽きることで `done` へ行く。
  マイクには入力の終わりが無いため、`done` は明示的な停止操作でしか
  起こらない。「キャンセル」と「正常終了」が区別できなくなる。
- **Androidの実時間ポンプとデコード層が不要になる。** 現在のAndroid実装の
  中核は「MediaCodecでデコード → 16kHzへリサンプリング → PFDパイプへ
  毎秒約32KBで供給」である(design.md §4.3)。マイク入力では
  `EXTRA_AUDIO_SOURCE` を渡さないため、この層がまるごと使われなくなる。
  すなわち**Androidにおいてマイク入力とファイル入力は、ほぼ別の実装になる。**
- **`playbackRate` が意味を失う。** Web専用オプション(design.md §2.2)で
  あり、再生という概念があってこそ成り立つ。
- **権限取得はアプリ側の責務になる。** モデルダウンロードの同意UIを
  アプリ側の責務としている(requirements.md FR-2・§8)のと同じ整理に
  なるが、Android の `RECORD_AUDIO` はプラグインの
  `AndroidManifest.xml` に宣言を足す必要があり、**マイク入力を使わない
  アプリにも権限宣言が付いてしまう**。マージされる権限を増やすかどうかは
  ライブラリとしての判断になる。

### 2.3 今これを塞いでいるもの

- **requirements.md §3 が明示的に対象外としている。** 入れるなら要件の改定
  からになる。
- **Androidのクラスドキュメントが「連続認識のために使うことを意図して
  いない」と明記している。** マイク入力の主用途と衝突する。
- **Darwinでは OS 26 向けの入力シーケンス構築方法が未確認である。**
  簡便なAPI(`CaptureInputSequenceProvider`)は OS 27 のものであり、
  本ライブラリの下限では使えない。

### 2.4 評価

**Web では「むしろ素直な道」だが、Android と Darwin では
別実装に近い。** 特にAndroidは、現在の実装の中核であるデコード層・
リサンプリング層・実時間ポンプがまるごと出番を失う。ファイル入力と
マイク入力を1つのライブラリで持つこと自体は可能だが、**実質的に2つの
実装を保守することになる。** 精度の問題(共通前提)が未解決のまま
保守対象を倍にする判断は取れない。

---

## 3. 同時複数セッション

design.md §3 は「**同時セッションはv1では1本に制限(プラットフォーム側の
並行動作が未検証のため)。2本目の開始は `StateError`**」と定めている。
これを2本以上に緩める拡張。

**動機ははっきりしている**: **Androidは実時間方式であり、ファイル長と同等の
時間がかかる**(Pixel 6実機: 9.56秒の音声にポンプ9,564ms、実効31,993.7
バイト/秒。design.md §4.3)。Webも実時間である(Chrome 153で9.56秒の音声に
9,676ms)。**この2つでスループットを上げる手段は、同時に複数本走らせること
しかない。**(`playbackRate` による短縮はWeb専用であり、しかも精度が単調に
低下する: 1.0x 66.7% → 1.5x 50.0% → 2.0x 33.3%。design.md §4.1)

### 3.1 今どう1本に制限しているか

`packages/offline_stt/lib/src/session_guard.dart` の
`TranscribeSessionGuard` mixin である。各ネイティブ実装が個別に排他を書くと
重複と実装漏れが起きるため、共有層に1つだけ置いてある(Issue #23)。

- 状態は `bool _sessionActive` **1つだけ**である。セッションを識別する
  ID の概念が無い。
- **セッション開始は「`transcribeFile()` の呼び出し時点」ではなく
  「返り値のStreamが `listen` された時点」**である
  (`StreamController.onListen`)。購読前に破棄した場合にセッション枠を
  消費してしまうのを避けるためである(design.md §3 細則1)。
- 終了は done / error / cancel の3経路のいずれでもよく、解放処理は
  べき等にしてある。
- 2本目は**同期的に throw せず Streamエラーとして** `StateError` を通知
  する(design.md §3 細則2)。下層の認識セッションは一切開始しない。
- この mixin は各実装パッケージにミックスインされ、実装パッケージは
  `OfflineTranscriberPlatform.instance` として**プロセスに1つ**である。
  したがって実質「プロセスあたり1本」になっている。

### 3.2 各プラットフォームAPIが実際に何を言っているか

| プラットフォーム | 同時実行についての記載 |
|---|---|
| Android | **記載なし。** 1インスタンス内の順序規則のみ文書化されている |
| iOS / macOS | **部分的に記載あり。** 1アナライザ = 1入力シーケンス。ただし複数トランスクライバは想定されている |
| Web | **記載なし。** 1オブジェクトの再start禁止のみ |

**Android**: `stopListening()` のドキュメントが
「呼び出し後、クライアントは `RecognitionListener.onResults` または
`onError` が呼ばれるまで待ってから再度 `startListening` を呼ばなければ
ならない。さもなければ認識サービスに拒否される」と書いているのは
**同一インスタンス内の順序規則**である。2つの `SpeechRecognizer` インスタンス
を同時に listening させてよいかは**どこにも書かれていない。**
示唆的なエラーコードとして `ERROR_RECOGNIZER_BUSY`(「RecognitionService
busy」、API 8、値8)と `ERROR_TOO_MANY_REQUESTS`(「同一クライアントからの
リクエストが多すぎる」)が存在する
(https://developer.android.com/reference/android/speech/SpeechRecognizer)。
**これらの存在は、同時実行が無条件に許されるわけではないことを示唆するが、
許されないことの証明にもなっていない。** 実測するまで分からない。

**iOS / macOS**: `SpeechAnalyzer` は「**アナライザは一度に1つの入力
シーケンスしか解析できない**」「`start(inputSequence:)` は直前の入力
シーケンスの自律解析を停止する」と明記している
(https://developer.apple.com/documentation/speech/speechanalyzer)。
一方 `SpeechTranscriber` は「**複数のトランスクライバインスタンスは、
一定の点で同様に構成されている限り、同じバッキングエンジンとモデルを共有
できる**」と書いており、複数インスタンスの併存自体は想定されている
(https://developer.apple.com/documentation/speech/speechtranscriber)。
すなわち「1アナライザ1シーケンス」であって「1プロセス1アナライザ」では
ない。**ただしN個のアナライザを同時に走らせてよいかは記載が無い。**

なお `AssetInventory.maximumReservedLocales`(OS 26.0)は実在する制限
であり、「アプリに許される locale 予約の数。デバイスのストレージ容量に
よって値が変わりうる」と定義されている
(https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales)。
M0検証では macOS 26.5.1 で `maximumReservedLocales=5` を実測している
(spikes/darwin/RESULTS.md。上限超過時の挙動は未検証)。
**これはロケール資産の割り当て上限であって、セッション数の上限ではない。**
ただし「複数のロケールを同時に走らせる」という形の同時実行を考える場合は
この上限に当たる。

**Web**: 仕様の `start()` アルゴリズムは
「`[[started]]` が `true` で、かつ `error` / `end` イベントがまだ発火して
いなければ `InvalidStateError` を投げる」と定めている。**これは1オブジェクト
の再start禁止であり、複数の `SpeechRecognition` オブジェクトを同時に
start することへの制限は仕様に無い**
(https://webaudio.github.io/web-speech-api/)。

### 3.3 入れるとしたら何を変えるか

**(a) 共有ガード** — `TranscribeSessionGuard` の `bool _sessionActive` を、
セッションハンドルの集合へ置き換える。上限を設けるなら上限値の根拠が要る
(現在の「1」の根拠は design.md §3 の「プラットフォーム側の並行動作が
未検証のため」である)。design.md §3 の記述と、`packages/offline_stt/test/`
にある状態遷移・二重セッション拒否のユニットテストも書き換えになる。

**(b) ブリッジがセッションを識別できない。** これが最も重い。
`pigeons/offline_stt_events.dart` の `TranscriptSegment` は `text` と
`isFinal` の2フィールドだけであり、**セッションIDを持たない。**
結果は `@EventChannelApi` の `segments` という**単一のストリーム**で
流れてくる。2本同時に走らせると、どちらのセッションの結果かを区別する
手段が無い。したがって:
- `TranscriptSegment` かイベントチャネルのどちらかにセッションIDを導入する
- `pigeons/offline_stt_events.dart` を直す
- Kotlin / Swift の2言語の生成物と受け口を直す

**(c) ネイティブ側の資源が線形に増える。** 特にAndroidは、1セッションあたり
`MediaExtractor` + `MediaCodec` + リサンプラ + 実時間ポンプのコルーチンが
1組ずつ動く。design.md §4.3 は「デコード・リサンプリング・送出はチャンク
単位でストリーミング処理する。全量を materialize すると 48kHz・ステレオ・
16-bit・60分の入力でピーク約1.73 GB に達して OOM になる」と書いている。
**ストリーミングにより同時生存バッファは音声長に依存しなくなっているが、
セッション数には比例する。** さらに `SpeechRecognizer` はメインスレッドから
生成・操作する契約であり(design.md §6)、N本分の生成・操作・コールバックが
すべてメインスレッドに集中する。

**(d) スレッディング**(design.md §6)を全プラットフォームで見直す。
Android は Dispatchers.IO 上の1本のJob、Darwin は Task + main actor、
Web はシングルスレッド。いずれも「1本」を前提に書かれている。

**(e) エラー写像**(design.md §5)。Androidの `ERROR_RECOGNIZER_BUSY` /
`ERROR_TOO_MANY_REQUESTS` は現在どの共通例外にも個別分類されておらず
`PlatformError` に倒れている。同時実行を許すなら、これらは
「同時実行数の上限に当たった」という**利用者が対処できる状態**を表す
ようになるため、専用の分類が要る。なお design.md §5 の注記が明記している
とおり、**`ERROR_*` 定数の対応表はそもそも暫定であり、実機でエラーを実発火
させた確認を行っていない**(Issue #50 で確定させる予定)。

### 3.4 今これを塞いでいるもの

- **design.md §3 が挙げた「プラットフォーム側の並行動作が未検証」という
  理由が、いまだに解消していない。** 上の 3.2 のとおり、3プラットフォーム中
  2つはドキュメントが沈黙しており、Darwin だけが「1アナライザ1シーケンス」
  という部分的な記述を持つ。**沈黙は許可ではない。** 実測するしかないが、
  その実測が可能な状態にない(下記)。
- **実測する土台が無い。** Androidは Pixel 6 単一機種でしか測っておらず、しかも `onResults()` が
  `null` になる挙動が全端末共通かどうかも未確定である(design.md §8
  未決事項8)。**1本ですら安定していないものを2本にする段階ではない。**
- **Androidには機種依存の壁がある。** `SpeechRecognizer.isOnDeviceRecognitionAvailable()`
  が `true` を返すか、対象ロケールが `supportedOnDeviceLanguages` に含まれる
  かは端末依存であり、含まれない端末が存在しうる
  (`packages/offline_stt/README.md`「既知の制約(採用前に読むこと)」)。
  同時実行可否も同様に端末依存である可能性が高く、
  **1機種で成功しても一般化できない。**

### 3.5 評価

**3件の中で、需要という点では最も筋が通っている**(Android / Web の実時間
制約を回避する唯一の手段であるため)。しかし**着手の前提条件が最も重い**。
公開APIの形は変えずに済む可能性があるが(セッションIDをブリッジ内部に閉じ
込められれば)、ブリッジ・スレッディング・エラー写像の全面的な見直しを伴う。
そして何より、**ドキュメントが沈黙している以上、実機で測るしかない。**
実機E2E(#40 / #50)は2026-09-21 に Darwin(macOS 26.5.1 + iPad Pro /
iOS 26.6.2)と Android(Pixel 6)で実行済みだが、**この拡張が必要とする
「同時に複数セッション」の実測は1本も取っていない**(両者とも同時1本の
制約下での測定である)。したがって現状では着手できない。

---

## 4. まとめ

| 拡張 | 各APIの提供状況 | 主なコスト | 今塞いでいるもの | 現時点の結論 |
|---|---|---|---|---|
| タイムスタンプ | Darwin ◎ / Android △(API 34、開始のみ)/ **Web ✕(存在しない)** | `TranscriptSegment` と Pigeonスキーマ・2言語の生成物。**プラットフォーム間で取れるものが揃わず共通APIの前提が崩れる** | Androidは語タイムスタンプが載る `onResults()` 経路が現に壊れている。Webは原理的に不可能 | **着手しない。** 共通APIで揃えられない |
| マイク入力 | Web ◎(`start()` 引数なし)/ Android ○(`EXTRA_AUDIO_SOURCE` を外すだけ。`RECORD_AUDIO` が要る)/ Darwin △(OS 26 では入力シーケンスを自前構築。方法は未確認) | 公開APIの追加。Androidではデコード層・実時間ポンプがまるごと不要になり**ほぼ別実装**になる。終了条件の設計をやり直す | requirements.md §3 が対象外と明記。Androidのドキュメントが「連続認識向けではない」と明記 | **着手しない。** 要件の改定からになる |
| 同時複数セッション | **3つ中2つはドキュメントが沈黙。** Darwin のみ「1アナライザ1シーケンス」と記載 | ブリッジにセッションIDが無いのが最大の壁。スレッディングとエラー写像も全面見直し | 「並行動作が未検証」という v1 での制限理由が未解消。**実機E2Eが1本分すら未実施**(#40 / #50) | **着手しない。** ただし需要は最も明確であり、実機E2E完了後に再評価する価値がある |

**3件に共通する結論**: どれも、まず **(1) 精度不成立の原因究明**(全
プラットフォームで `jaJP_10s` 66.7%、原因未確定)と **(2) 本番実装での
実機E2E**(#40 / #50、いずれも未実施)が先である。1本のファイル
入力が期待どおり動くことをまだ確認できていない段階で、拡張に着手する
理由は無い。
