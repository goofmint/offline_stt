# offline_stt_android 実機E2E 実行結果

対応 Issue: #50([M3] Pixel系 + 非Pixel系の2機種で基準音声E2E)。
手順書は [E2E_CHECKLIST.md](E2E_CHECKLIST.md)、包含率の算出規則は
[リポジトリルートの E2E_CHECKLIST.md](../../E2E_CHECKLIST.md) および
design.md §7。

**本書は `packages/offline_stt_android/`(本番実装)を実機で動かした
初めての記録である。** `spikes/android/RESULTS.md` は M0 スパイク
(`spikes/` 配下の独立した検証コード)の記録であり、別物である。M0 以降に
本番実装へ入った修正(ストリーミングデコード・リサンプリング、Executor の
後始末、API 33/34 の `triggerModelDownload` overload 分岐、
`SpeechRecognizer` の破棄、メインスレッド契約、`startedNativeTranscription`)
は、本実行まで一度も実機上で走っていない。

**本書には実測値のみを書く。実行していない項目は「未実施」と書き、理由を
添える。**

## Issue #50 の達成状況

Issue #50 は **Pixel系 + 非Pixel系の2機種** を要求している。本実行で用意
できたのは Pixel 6 の1台のみであり、**非Pixel機での検証は未実施である。**
したがって #50 はこの実行では閉じない。

## 実行環境

| 項目 | 値 |
|---|---|
| 実行日 | 2026-09-21 |
| 端末 | Google Pixel 6(`oriole`、adb serial `19101FDF600ENB`) |
| Android | 17(`ro.build.version.release`)/ API 37(`ro.build.version.sdk`)/ ビルド `CP2A.260705.006` |
| Flutter | 3.41.9 stable(Dart 3.11.5) |
| JDK | OpenJDK 17(`/opt/homebrew/opt/openjdk@17/...`)。既定JDKは 26.0.1 で、Kotlin コンパイラがバージョン文字列を解釈できずビルドが失敗する |
| 被検体 | `packages/offline_stt_android/`(Dart + Kotlin)+ `packages/offline_stt_platform_interface/` |
| ドライバ | `apps/example/integration_test/android_baseline_e2e_test.dart` |
| 権限 | `RECORD_AUDIO` も含め実行時権限は一切付与していない |

## 実行方法(再現手順)

E2E_CHECKLIST.md が想定する「example app の UI を人手で操作する」方式では
なく、**example app の integration_test から本番実装の API を直接呼ぶ**
方式を採った。理由は次の3点である。

1. 手順3・手順8は確定テキストを **正確な文字列として** 記録する必要がある。
   UI をスクリーンショットで読む方式では取りこぼす。
2. 手順4(キャンセル)・手順5(セッション排他)は `StreamSubscription` の
   操作そのものが検証対象であり、UI からは再現できない。
3. `packages/offline_stt_android/android/src/androidTest/` に instrumented
   test を置く方式も検討したが、それでは Kotlin 層しか通らず、Dart 側の
   `TranscribeSessionGuard` ・ `startedNativeTranscription` ・エラー写像
   (M0 以降に入った修正の多くがここにある)を検証できない。integration_test
   なら **Dart + Pigeon + Kotlin の本番経路をそのまま** 通せる。

```
# 1. 端末を1台だけ接続する
~/Library/Android/sdk/platform-tools/adb devices

# 2. 音声配置スクリプトをバックグラウンドで起動しておく
#    (flutter test がアプリを入れ直すため、事前 push では消える)
cd apps/example
./tool/stage_baseline_audio.sh

# 3. テスト実行
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  flutter test integration_test/android_baseline_e2e_test.dart -d <device-id>
```

`--plain-name '手順3'` のように手順単位で絞り込める。標準出力の `E2E|`
始まりの行が測定値である。キーワード包含率の採点は
`test-assets/keyword_score.py`(design.md §7 の正規化をそのまま実装した
もの。`spikes/*/KeywordScoring.*` と同一ロジック)へ確定テキストを渡す。

### example app の UI 経路について

**UI 経路(ファイルピッカー → モデル状態表示 → 同意ダイアログ → 進行表示)は
本実行では通していない。未実施である。** integration_test は
`OfflineTranscriberPlatform.instance` を直接叩くため、`home_page.dart` /
`download_consent_dialog.dart` のコードは実行されない。

## 手順1: 可用性チェック(checkModel)

1秒間隔をあけて1ロケールずつ `checkModel()` を呼んだ実測値である
(間隔をあける理由は「手順1-b」を参照)。

| ロケール | ModelState | 所要 |
|---|---|---|
| ja-JP | available | 160ms |
| ja | unavailable | 92ms |
| en-US | available | 105ms |
| en | unavailable | 113ms |
| en-GB | downloadable | 58ms |
| en-AU | downloadable | 120ms |
| en-IN | downloadable | 110ms |
| en-CA | downloadable | 130ms |
| fr-FR | downloadable | 115ms |
| de-DE | downloadable | 118ms |
| es-ES | downloadable | 102ms |
| it-IT | downloadable | 133ms |
| ko-KR | downloadable | 112ms |
| zh-CN | unavailable | 116ms |
| zh-TW | downloadable | 98ms |
| pt-BR | downloadable | 106ms |
| ru-RU | downloadable | 103ms |
| hi-IN | downloadable | 112ms |
| zz-ZZ(実在しないロケール) | unavailable | 106ms |

- ja-JP が `available` なのは、M0検証(spikes/android/RESULTS.md)で言語
  パックを取得済みだからである。en-US は工場出荷時から導入されている。
- 言語のみの指定(`ja` / `en`)は `unavailable` になる。
  `checkRecognitionSupport()` の各リストは地域付きタグで返るため、完全一致
  で突き合わせる本実装の写像(`ModelAvailability.checkModel`)の帰結である。
- **`checkRecognitionSupport()` が返す4リストそのものは記録できていない。**
  本番実装はこれをログへ出さず、`ModelState` へ畳んだ結果しか外へ出さない
  ためである(E2E_CHECKLIST.md 手順1の3.は「4リストの内容を記録する」と
  求めているが、**本番実装にはそれを取り出す手段が無い**)。上表は
  「ロケールごとに本実装が何を返したか」であって4リストの写しではない。

### 手順1-b(チェックリスト外の追加測定): checkModel の再現性

手順1の途中で、**同一ロケール・同一端末でも呼び出しのたびに結果が変わる**
事象を観測したため、追加で測定した。`ja-JP` に対する `checkModel()` を
連続30回、続いて1秒間隔で20回呼んだ結果である。

| 条件 | 結果 |
|---|---|
| 連続30回(間隔なし) 1回目 | `unavailable` が 5回(index 5, 11, 13, 27, 29) |
| 連続30回(間隔なし) 2回目 | `unavailable` が 6回(index 3, 5, 8, 10, 12, 21) |
| 連続30回(間隔なし) 3回目 | `unavailable` が 6回(index 1, 7, 11, 18, 22, 26) |
| 1秒間隔で20回 | `unavailable` は **0回** |

偽の `unavailable` は所要時間が 6〜22ms と短く、成功時(44〜88ms)と
明確に分かれる。すなわち `checkRecognitionSupport()` の応答を待たずに
返っている。また最初の広ロケール測定(間隔なし)では `en-US` / `fr-FR` /
`ru-RU` が `unavailable` になったが、1秒間隔での再測定ではそれぞれ
`available` / `downloadable` / `downloadable` だった。**間隔なしの測定値は
信用できない。**

## 発見したバグ(最重要)

### B-1. `checkModel()` 直後に `transcribeFile()` のセッションを張ると `ERROR_SERVER_DISCONNECTED(11)` で失敗する

**症状。** `transcribeFile()` が、音声を1バイトも流さないうちに
`PlatformException_(code: platformError, message: ERROR_SERVER_DISCONNECTED(11))`
で終了する。発生は 60〜300ms 以内であり、`partials=0` / `finals=0`。
`ERROR_RECOGNIZER_BUSY(8)` になることもある。

**再現性。** 高い。下記「手順3」のとおり、基準音声10ファイルに対する
2回の通し実行(計20回の `transcribeFile()`)のうち成功したのはごく一部で
ある。クリップの長さ・形式・ロケールとは無関係であり、同じファイルが成功
したり失敗したりする。

**logcat(1回目の実行、jaJP_10s.wav の1本目。verbatim)**

```
09-21 07:00:59.902  1981  4653 I SpeechRecognitionManagerServiceImpl: Client 10358 has opened 1 sessions
09-21 07:00:59.917 27402 27402 I AiAiSpeechRecognition: #onCheckRecognitionSupport
09-21 07:01:00.032  1981  4653 I SpeechRecognitionManagerServiceImpl: Client 10358 has opened 2 sessions
09-21 07:01:00.042 27402 27402 I AiAi    : AiAiSpeechRecognitionService#onStartListening
09-21 07:01:00.064 27402 27402 I AiAiSpeechRecognition: Create input stream from external audio PFD
09-21 07:01:00.154  1981  1981 I RemoteSpeechRecognitionService: Connection to speech recognition service lost, but no #startListening has been invoked yet.
09-21 07:01:00.160  1981  4653 I SpeechRecognitionManagerServiceImpl: Client 10358 has opened 1 sessions
```

Dart 側が受け取ったエラーの時刻は `elapsedMs=262`、すなわち
07:01:00.16 前後であり、上の「Connection to speech recognition service lost」
「has opened 1 sessions」と一致する。

**読み取れること(ここまでは実測)。**

1. `transcribeFile()` は内部で必ず `checkModel()` を先に呼ぶ
   (`lib/src/recognition_session.dart`、design.md §3「available 以外なら
   即座に ModelUnavailableException」)。この `checkModel()` が
   `SpeechRecognizer` を1個生成する(07:00:59.902 の "1 sessions")。
2. その直後に認識セッション用の `SpeechRecognizer` が生成され、この時点で
   **同一クライアントが2セッションを開いた状態になる**(07:01:00.032 の
   "2 sessions")。
3. `startListening()` は一度受理される(07:01:00.042 / .064)。
4. 遅れて `checkModel()` 側の `SpeechRecognizer` が破棄され
   (07:01:00.154 の "no #startListening has been invoked yet" は
   `startListening()` を呼んでいない方、すなわち `checkModel()` 側を指す)、
   **その破棄と同時に認識セッション側が `ERROR_SERVER_DISCONNECTED` を
   受け取る。**

**推定(ここからは推論であり未確定)。** `ModelAvailability.querySupport()`
の `destroyOnce()` は `mainExecutor.execute { target.destroy() }` と
**非同期に post** する。一方 `onSupportResult()` はその直後に
`continuation.resumeWith(...)` でコルーチンを再開する。再開側は
`Dispatchers.Main.immediate` であるため、post された `destroy()` が走る前に
Dart への応答 →`hostApi.transcribeFile()` →新しい `SpeechRecognizer` の生成
まで進みうる。結果として2セッションが重なり、後から走る `destroy()` が
共有のサービス接続を落としている、という筋である。**ただしこれは logcat の
時系列からの推論であって、コード変更による対照実験は行っていない。**

**影響。** `transcribeFile()` が実機でほぼ使えない。E2E_CHECKLIST.md の
合否基準に照らして **不合格** である。

**本実行では修正していない。** 検証タスクの範囲は測定であり、原因の確定と
修正は別途行う必要がある。

### B-2. `checkModel()` が偽の `unavailable` を返す

上記「手順1-b」のとおり、`ja-JP` の言語パックが導入済みの端末で
`checkModel('ja-JP')` が 17〜20% の確率で `unavailable` を返す(連続呼び出し
時)。`ModelAvailability.querySupport()` は `RecognitionSupportCallback`
の `onError()` も同期例外も区別せず `null` を返し、呼び出し元がそれを
`ModelState.UNAVAILABLE` に畳む。**失敗の理由がどこにも残らないため、
利用者からは「本当に未対応」と区別できない。** B-1 と根が同じである
可能性が高いが、これも対照実験は行っていない。

### B-3. 長尺音声で確定テキストが最後の認識セグメントだけになる

**症状。** 3分クリップ(`jaJP_3m.wav`)では partial が正しく伸びる一方、
オンデバイス認識エンジン(SODA)は途中で仮説をリセットして新しい
セグメントを開始する。本実装は `onPartialResults()` の最上位候補を
そのまま `TranscriptSegment` として流し、`onResults()`(または直前の
partial)を確定テキストとするため、**確定テキストには最後のセグメントしか
残らない。**

**実測(jaJP_3m.wav、1,335件の partial)。** 仮説のリセットは2回起きた。

| セグメント | リセット直前の partial の長さ | 冒頭 |
|---|---|---|
| 1 | 341文字 | 「東京都渋谷で2024年11月3日午後3時から株式会社モンギフトの…」 |
| 2 | 370文字 | 「質疑応答では大阪府から参加した…」 |
| 3(= 確定テキスト) | 343文字 | 「です ISO 2万70001の認証取得も…」 |

確定テキスト(`isFinal: true` として届いたもの)はセグメント3だけであり、
音声の最初の2/3は失われている。キーワード包含率への影響は「手順8」を
参照(確定テキストのみ 17.9% に対し、3セグメントを連結すると 82.1%)。

**設計との関係。** `RecognitionSession.kt` のコメントは「`onResults()` の
texts が null になり得る。その場合は直前の `onPartialResults()` の最上位
候補を確定結果として採用する」を **design.md が明記する正規の仕様** と
書いている。しかし「途中でリセットされた仮説を連結する」ことは
どこにも書かれておらず、長尺音声では仕様として成立していない。
**10秒程度の短いクリップでは顕在化しない。**

## 手順3: 文字起こし実行(transcribeFile)

基準音声8ファイル + リサンプリング確認用2ファイルの計10ファイルを、
同一条件で2回通した。2回目は各実行の前に10秒の待機を入れている
(1回目の失敗が「前のセッションの後始末と重なったせい」かを切り分けるため。
**結果は変わらなかった**)。

### 1回目(待機なし)

| クリップ | 所要 | partial | final | 結果 |
|---|---|---|---|---|
| jaJP_10s.wav | 262ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| jaJP_10s.m4a | 547ms | 0 | 0 | `ERROR_RECOGNIZER_BUSY(8)` |
| enUS_10s.wav | 2,010ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| enUS_10s.m4a | 74ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| **jaJP_3m.wav** | **177,084ms** | **1,335** | **1** | **成功** |
| jaJP_3m.m4a | 100ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| enUS_3m.wav | 73ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| enUS_3m.m4a | 74ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| jaJP_10s_48k_stereo.m4a | 533ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| enUS_10s_44k1_stereo.m4a | 62ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |

### 2回目(各実行前に10秒待機)

| クリップ | 所要 | partial | final | 結果 |
|---|---|---|---|---|
| jaJP_10s.wav | 291ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| jaJP_10s.m4a | 138ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| enUS_10s.wav | 119ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| enUS_10s.m4a | 177ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| jaJP_3m.wav | 145ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| **jaJP_3m.m4a** | **176,405ms** | **1,339** | **1** | **成功** |
| **enUS_3m.wav** | **180,365ms** | **1,152** | **1** | **成功** |
| enUS_3m.m4a | 114ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| jaJP_10s_48k_stereo.m4a | 182ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |
| enUS_10s_44k1_stereo.m4a | 162ms | 0 | 0 | `ERROR_SERVER_DISCONNECTED(11)` |

**合計 20回中 3回しか成功していない(15%)。** 成否とクリップの長さ・
形式・ロケールの間に対応は見られない(`jaJP_3m.wav` は1回目で成功し2回目で
失敗、`jaJP_3m.m4a` はその逆)。B-1 を参照。

### 成功した実行から分かったこと(実測)

- **確定テキスト(`isFinal: true`)は `null` にならなかった。** M0 検証で
  未解決だった「`onResults()` の `RESULTS_RECOGNITION` が `null` になる」
  現象は、成功した3回すべてで起きていない。E2E_CHECKLIST.md 手順3の2.
  (最優先確認項目)については、**少なくとも本実行では再現しなかった。**
- **partial は音声の進行に追従して伸びた。** ただし途中で仮説がリセット
  される(B-3)。
- **実時間ポンプは設計どおりに動いた。** 180秒の音声に対する所要時間は
  177,084ms / 176,405ms / 180,365ms。design.md §4.3 の「音声長と同程度の
  時間がかかる」と一致する。
- **`.m4a` のデコード経路も動く**(`jaJP_3m.m4a` が成功している)。

### リサンプリング(手順3の3.)

48kHz ステレオ / 44.1kHz ステレオへ変換した10秒クリップ
(`tool/stage_baseline_audio.sh` が ffmpeg で生成)を用意したが、**2回の実行
とも B-1 で即時失敗したため、リサンプリング経路が正しく動くかは確認できて
いない。未実施である。**

## 手順8: キーワード包含率

算出は `test-assets/keyword_score.py`(design.md §7 の正規化規則をそのまま
実装。`spikes/*/KeywordScoring.*` と同一ロジック)による。**期待キーワードと
認識結果の両方へ同一の正規化を適用している。**

スクリプトの妥当性確認として、M0 の実測テキスト相当を入力すると
`jaJP_10s` で 66.7%(4/6、不一致は「東京都渋谷区」「株式会社モーンギフト」)
となり、spikes/android/RESULTS.md の値を再現する。

### 3分クリップ(成功した3回)

確定テキストは B-3 により最後の認識セグメントだけである。参考値として、
partial として流れた全テキストを連結したもの(= 認識過程のどこかに
キーワードが現れたか)も併記する。

| クリップ | 確定テキストでの包含率 | 判定 | partial全体での包含率(参考) |
|---|---|---|---|
| jaJP_3m.wav | **5/28 = 17.9%** | 不成立 | 23/28 = 82.1% |
| jaJP_3m.m4a | **5/28 = 17.9%** | 不成立 | 22/28 = 78.6% |
| enUS_3m.wav | **1/25 = 4.0%** | 不成立 | 11/25 = 44.0% |

`jaJP_3m.wav` 確定テキストの内訳:

| キーワード | 判定 |
|---|---|
| 東京都渋谷区 | MISS |
| 2024年11月3日 | MISS |
| 渋谷ヒカリエ | HIT |
| 128名 | MISS |
| モジトルCore | MISS |
| 月額980円 | HIT |
| 田中健一 | MISS |
| 2019年 | MISS |
| 32万人 | MISS |
| 佐藤美咲 | MISS |
| 10分間 | MISS |
| 45秒 | MISS |
| 96.4パーセント | MISS |
| 98.1パーセント | MISS |
| 12言語 | MISS |
| 20言語 | MISS |
| 大阪府 | MISS |
| 月間5000件 | MISS |
| 2025年2月15日 | MISS |
| 名古屋市 | MISS |
| サンフランシスコ | MISS |
| 3億円 | MISS |
| ベルリン | MISS |
| 山田健太 | MISS |
| ISO27001 | MISS |
| 月額4980円 | HIT |
| 鈴木一郎 | HIT |
| 18名 | HIT |

`jaJP_3m.wav` の確定テキスト(verbatim):

```
です ISO 2万70001の認証取得も2025年内に完了する見込みです料金プランは個人向けのライトプランが月額980円法人向けのビジネスプランが月額4980円エンタープライズプランは個別見積もりとなります年間契約の場合は2ヶ月分が割引になります最後にカスタマーサポート窓口として平日午前9時から午後6時まで対応する専用チャットが新設されることが案内されました発表資料は公式サイトから2024年11月10日以降にダウンロード可能になる予定です会場となった渋谷ヒカリエは JR 渋谷駅から徒歩3分でアクセス可能です当日は雨天にも関わらず予定より12名多い来場者が集まりました運営スタッフは合計18名で対応にあたりました広報担当の鈴木一郎氏は来年も同時期に開催予定であるとコメントしています
```

`enUS_3m.wav` の確定テキスト(verbatim):

```
 From 9 A.M to 6 p.m. presentation materials will be available for download from the official website starting November 10 2024 engineering director misaki Sato added that a beta version for Mac OS will ship in January 2025 followed by a Windows release in March 2025 and that the team currently numbers 42 engineers across three offices
```

**この低い値の主因は認識精度ではなく B-3(確定テキストが最後のセグメント
だけになる)である。** partial 全体で見れば ja-JP は 78.6〜82.1% まで上がる。
したがって「認識モデルの実力が低い」と結論してはならない。一方で
partial 全体でもしきい値(95%)には届いておらず、ja-JP で一貫して落ちる
のは「東京都渋谷区」(「渋谷で」と認識)・「モジトルCore」・
「96.4パーセント」「98.1パーセント」(`96.4%` と数字記号で認識)・
`ISO27001`(`ISO 2万70001` と認識)である。「東京都渋谷区」は M0 でも
同じく落ちている。

## 実行できなかった項目(未実施)

| 項目 | 状態 | 理由 |
|---|---|---|
| **非Pixel機での全項目** | 未実施 | 端末が無い。Issue #50 の半分は達成できていない |
| 手順1の「4リストの内容の記録」 | 未実施 | 本番実装が `checkRecognitionSupport()` の4リストをログにも API にも出さない。取り出す手段が無い |
| 手順3の3.(リサンプリング経路) | **実施済み(手順3-b で確認)** | 通し実行では B-1 で失敗したが、リトライ付きの実行で 48kHz / 44.1kHz ステレオとも正しく認識できた |
| 手順7(オフライン確認 / 機内モード) | 未実施 | B-1 により通常状態ですら `transcribeFile()` が安定して成功しないため、機内モードとの差を測っても意味を持たない。通信が発生していないことのパケットキャプチャによる確認も行っていない(M0 と同じ状態) |
| 手順2(downloadModel の完了確認) | 未完了 | B-2 / B-4。詳細は「手順2」の節 |
| example app の UI 経路 | 未実施 | integration_test は `OfflineTranscriberPlatform.instance` を直接叩く。同意ダイアログ・進行表示・ファイルピッカーのコードは通っていない |
| `DeviceUnsupportedException` | 未実施 | `isOnDeviceRecognitionAvailable()` が `false` の端末が手元に無い |
| 10秒クリップの包含率(M0 との直接比較) | 下記「手順3-b」参照 | |

## このE2Eで確認できないこと

- **Pixel 6 以外の機種・他のOSバージョンでの挙動。** 単一機種の実測である。
- **人間の自然発話に対する精度。** 基準音声はTTS合成音声である。
- **B-1 / B-2 の原因の確定。** logcat の時系列からの推論までであり、
  コードを変えて挙動が変わることを確かめる対照実験は行っていない。

## 手順3-b(チェックリスト外の追加測定): 失敗時リトライ付きの10秒クリップ

B-1 により10秒クリップは手順3の2回の通し実行では一度も成功しなかった。
成功時の確定テキストを得るため、**成功するまで最大15回リトライ**する実行を
追加した(テスト側の緩和であり、本番実装はリトライしない)。

| クリップ | 成功までの試行回数 | 所要(成功時) | partial | 確定テキスト |
|---|---|---|---|---|
| jaJP_10s.wav | 15回すべて失敗(1回目)/ 7回目で成功(2回目) | 10,2xx ms | 61 | 下記 |
| jaJP_10s.m4a | 7回目で成功 | 10,199ms | 61 | 下記 |
| enUS_10s.wav | 9回目で成功 | 13,504ms | 71 | 下記 |
| enUS_10s.m4a | 12回目で成功 | 13,549ms | 73 | 下記 |
| jaJP_10s_48k_stereo.m4a | 5回目で成功 | 10,238ms | 62 | 下記 |
| enUS_10s_44k1_stereo.m4a | 3回目で成功 | 13,486ms | 69 | 下記 |

失敗はすべて `ERROR_SERVER_DISCONNECTED(11)` である。

**同じリトライ付き実行をもう一度行った結果**(成功までの試行回数は毎回
変わる。B-1 が時間依存であることの裏付けでもある):

| クリップ | 成功までの試行回数 |
|---|---|
| jaJP_10s.wav | 7回目で成功 |
| jaJP_10s.m4a | 1回目で成功 |
| enUS_10s.wav | 6回目で成功 |
| enUS_10s.m4a | 3回目で成功 |
| jaJP_10s_48k_stereo.m4a | 15回すべて失敗 |
| enUS_10s_44k1_stereo.m4a | 3回目で成功 |

確定テキストは1回目の実行と同一だった(`enUS_10s_44k1_stereo.m4a` のみ
`at 3 P.M` が `at 3pm` になったが、正規化後は同一であり包含率も変わらない)。

確定テキスト(verbatim):

```
jaJP_10s.m4a             : 東京都渋谷で2024年11月3日午後3時株式会社モンギフトが新製品を発表しました来場者は128名でした
jaJP_10s_48k_stereo.m4a  : 東京都渋谷で2024年11月3日午後3時株式会社モンギフトが新製品を発表しました来場者は128名でした
enUS_10s.wav             : In San Francisco on November 3rd 2024 at 3 P.M Moon gift Incorporated announced its new product attendance reached 128 people filling the venue completely
enUS_10s.m4a             : (enUS_10s.wav と同一)
enUS_10s_44k1_stereo.m4a : (enUS_10s.wav と同一)
```

### リサンプリング経路は動く(手順3の3.、上の追記)

`jaJP_10s_48k_stereo.m4a`(48kHz・ステレオ・AAC)と
`enUS_10s_44k1_stereo.m4a`(44.1kHz・ステレオ・AAC)のいずれも、16kHz
モノラル版とまったく同じ確定テキストを返した。**`Resampler` /
`AudioDecoder` のリサンプリング経路は実機で正しく動作している。**
(手順3の表で「未実施」としたのは待機付き通し実行の話であり、本項で
確認できた。)

### 10秒クリップのキーワード包含率

| クリップ | 包含率 | 判定 | 不一致キーワード |
|---|---|---|---|
| jaJP_10s.m4a | **4/6 = 66.7%** | 不成立 | 東京都渋谷区、株式会社モーンギフト |
| jaJP_10s_48k_stereo.m4a | 4/6 = 66.7% | 不成立 | 同上 |
| enUS_10s.wav | **5/5 = 100.0%** | **合格** | (なし) |
| enUS_10s.m4a | 5/5 = 100.0% | 合格 | (なし) |
| enUS_10s_44k1_stereo.m4a | 5/5 = 100.0% | 合格 | (なし) |
| jaJP_10s.wav | 4/6 = 66.7% | 不成立 | 東京都渋谷区、株式会社モーンギフト(m4a と同一の確定テキスト) |

`jaJP_10s` の内訳:

| キーワード | 判定 | 認識結果 |
|---|---|---|
| 東京都渋谷区 | MISS | 「東京都渋谷で」(「区」が脱落) |
| 2024年11月3日 | HIT | |
| 午後3時 | HIT | |
| 株式会社モーンギフト | MISS | 「株式会社モンギフト」(長音が脱落) |
| 新製品 | HIT | |
| 128名 | HIT | |

**M0(spikes/android/RESULTS.md)の 66.7%(4/6)と値も不一致キーワードも
完全に一致した。** M0 は確定テキストが得られず最終 partial で代用した値で
あったが、本実装では確定テキストから同じ値が出ている。すなわち
**本番実装の認識精度は M0 から劣化していない。**

`enUS_10s` は **design.md §7 のしきい値(95%以上)を満たす**。本リポジトリで
しきい値を満たした実測はこれが初めてである(ルートの E2E_CHECKLIST.md
「精度に関する既知の事実」の表は ja-JP 10秒のみを比較しており、en-US の
値は載っていない)。

## 手順4: キャンセル

`jaJP_3m.wav` の文字起こし中に `await subscription.cancel()` した。
B-1 により開始自体に3回かかっている(1回目・2回目は
`ERROR_SERVER_DISCONNECTED(11)`)。

```
E2E|CANCEL|startAttempt=1|error=PlatformException_(code: platformError, message: ERROR_SERVER_DISCONNECTED(11))
E2E|CANCEL|startAttempt=2|error=PlatformException_(code: platformError, message: ERROR_SERVER_DISCONNECTED(11))
E2E|CANCEL|startedAfterAttempts=3
E2E|CANCEL|cancelFutureMs=15
E2E|CANCEL|segmentsAfterCancel=0
E2E|CANCEL|nextRun|finals=0|error=PlatformException_(code: platformError, message: ERROR_SERVER_DISCONNECTED(11))
```

- **キャンセル Future は 15ms で完了した。**
- **キャンセル後に `TranscriptSegment` は1件も届かなかった**(3秒待って
  確認、`segmentsAfterCancel=0`)。
- **logcat に `ERROR_CLIENT`(5番)は残らなかった。**
- キャンセル Future 完了後の次の `transcribeFile()` は `StateError`
  (セッション排他違反)にはならなかった。すなわちセッション枠は正しく
  解放されている。ただしその実行自体は B-1 で失敗しており、
  **「キャンセル後に次の文字起こしが成立する」ところまでは確認できて
  いない。**
- ポンプスレッドのリークについては、同一プロセス内で `transcribeFile()` を
  15回以上連続実行しても挙動が悪化しなかった(手順3-b)。ただし
  **スレッド数を実測したわけではない。**

**キャンセル経路は M0 検証の範囲外であり、本実行が初の検証である。**
上記の範囲では期待どおりに動作した。

## 手順5: セッション排他

1本目(`jaJP_3m.wav`)は B-1 により11回目でようやく開始できた。その状態で
2本目(`jaJP_10s.wav`)を購読した結果:

```
E2E|EXCLUSIVE|firstStartedAfterAttempts=11
E2E|EXCLUSIVE|secondError=StateError|Bad state: 既に実行中のセッションが存在する。design.md §3のとおり、同時セッションはv1では1本に制限される。1本目のセッションが終了(done/error/cancelled)してから再度呼び出すこと。
```

**期待どおり `StateError` で即座に終了した。合格。**

## 手順6: エラーパス

```
E2E|ERRORPATH|locale=fr-FR|checkModel=downloadable|error=ModelUnavailableException
E2E|ERRORPATH|locale=zz-ZZ|checkModel=unavailable|error=ModelUnavailableException
E2E|ERRORPATH|not_audio.wav|attempt=1|error=PlatformException_|PlatformException_(code: platformError, message: ERROR_SERVER_DISCONNECTED(11))
E2E|ERRORPATH|not_audio.wav|attempt=2|error=DecodeFailedException|DecodeFailedException
```

| 例外 | 発火方法 | 結果 |
|---|---|---|
| `ModelUnavailableException` | 未取得(downloadable)の `fr-FR` で `transcribeFile()` | **送出された。** 暗黙のダウンロードも始まっていない |
| `LocaleUnsupportedException` | `supportedOnDeviceLanguages` に無い `zz-ZZ` を指定 | **送出されなかった。** 代わりに `ModelUnavailableException` になる(下記) |
| `DecodeFailedException` | テキストファイルを `.wav` として渡す | **送出された**(1回目は B-1 に潰されたが、2回目で到達) |
| `DeviceUnsupportedException` | 該当端末で実行 | **未実施。** `isOnDeviceRecognitionAvailable()` が `false` の端末が無い |
| `CancelledException` | 手順4のキャンセル | 手順4を参照。キャンセル自体は成立している |
| `PlatformException_` | 上記以外 | **送出された。** `code` は `platformError` で保持され、`message` に `ERROR_SERVER_DISCONNECTED(11)` と**ERROR定数名と番号がそのまま残っている**(`ErrorMapping.errorName()` の意図どおり) |

### F-1. `LocaleUnsupportedException` は Dart 側から到達できない

E2E_CHECKLIST.md 手順6は「`supportedOnDeviceLanguages` に無いロケールを
指定する」と `LocaleUnsupportedException` が出ることを期待しているが、
**実際には `ModelUnavailableException` になる。**

理由は実装の構造にある。`lib/src/recognition_session.dart` は
`transcribeFile()` の先頭で `checkModel()` を呼び、`available` 以外なら
その場で `ModelUnavailableException` を投げて終わる(design.md §3)。
未対応ロケールは `checkModel()` が `unavailable` を返すため、**認識セッション
自体が始まらず、`ERROR_LANGUAGE_NOT_SUPPORTED` を受け取る機会が無い。**

`ErrorMapping.kt` の `ERROR_LANGUAGE_NOT_SUPPORTED → LocaleUnsupported`
の写像は死んでいるわけではない(認識中に発火すれば通る)が、
**チェックリストが書いている発火方法では到達しない。** チェックリストと
実装のどちらを直すべきかは設計判断であり、本書では事実の記録に留める。

## 手順2: downloadModel

ja-JP は M0検証で取得済みで `available` のため、`downloadable` である
`fr-FR` を対象に実施した。**2回実行し、2回とも手順を完了できなかった。**

### 1回目: 何もせずに即座に完了した

```
E2E|DOWNLOAD|locale=fr-FR|before=downloadable
E2E|DOWNLOAD|elapsedMs=71|error=null
E2E|DOWNLOAD|after=downloadable
```

`downloadModel()` の Stream が **71ms で、`DownloadProgress` を1件も
emit せず、エラーも出さずに完了した。** 状態も `downloadable` のままである。

`OfflineSttApiImpl.runDownload` は最初に `ModelAvailability.checkModel()` を
呼び、`downloadable` 以外なら「状態を変化させず何もemitせず完了する」
(design.md §3細則3)。71ms という所要時間はこの早期リターン経路と整合
する。すなわち **B-2 の偽 `unavailable` を引いた結果、ダウンロードが
黙って何もせずに終わったと考えられる**(推論。Dart 側の `before` は
`downloadable` だったのに、その直後のネイティブ側の再照会で別の値が出た、
ということになる)。

利用者から見ると **「同意してダウンロードを押したのに、何の進捗も
エラーも出ずに終わり、状態も変わらない」** という挙動になる。

### 2回目: 11分以上ハングし、自前のタイムアウトも効かなかった

```
E2E|DOWNLOAD|attempt=1|locale=fr-FR|before=downloadable
(以降、11分以上なにも出力されず。手動で中断した)
```

logcat(verbatim、末尾)

```
09-21 07:21:48.229 27402 27402 I AiAiSpeechRecognition: #onCheckRecognitionSupport
09-21 07:21:50.315 27402 27402 I AiAiSpeechRecognition: #onCheckRecognitionSupport
09-21 07:21:52.405 27402 27402 I AiAiSpeechRecognition: #onCheckRecognitionSupport
09-21 07:21:54.510 27402 27402 I AiAiSpeechRecognition: #onCheckRecognitionSupport
09-21 07:21:54.595  1981  1981 I RemoteSpeechRecognitionService: Connection to speech recognition service lost, but no #startListening has been invoked yet.
```

`ModelAcquisition.run` の完了判定ポーリング(`POLL_INTERVAL_MS = 2,000`)は
2秒間隔で4回だけ走り、**07:21:54 を最後に止まった。** 以降 11 分以上、
`checkRecognitionSupport()` の照会も、Stream のイベントも、エラーも出て
いない。

### B-4. `ModelAcquisition.MAX_WAIT_MS` のタイムアウトが効かない

`ModelAcquisition.run` のループは

```kotlin
while (coroutineContext.isActive) {
    delay(POLL_INTERVAL_MS)
    val support = ModelAvailability.querySupport(context, locale)   // ← ここで止まる
    if (...) { ... return }
    if (System.currentTimeMillis() > deadline) { throw ... }        // ← 到達しない
}
```

という順序であり、**デッドライン判定は `querySupport()` が返ってきた後
にしかない。** `querySupport()` は `suspendCancellableCoroutine` で
`RecognitionSupportCallback` を待つだけで、**自前のタイムアウトを持たない。**
コールバックが来なければ永久に待つ。

`MAX_WAIT_MS` のコメントは「OS側のダウンロードが何らかの理由で永久に
完了しない場合にStreamが無期限にハングし続けることを避けるため」と
書いているが、**実測ではその意図が果たされていない。** 本実行で観測した
ハングは 11 分で、`MAX_WAIT_MS`(10分)を超えている。

同じ現象は手順1の最初の測定でも起きている(ロケールを間を置かず連続
照会した際、8件目の `en-CA` で `checkModel()` が返らず、600秒のタイムアウトを
テスト側で付けるまで進まなかった)。**`querySupport()` が返らないことが
あるのは `checkModel()` / `downloadModel()` 双方に効く共通の弱点である。**

### 手順2の評価

**未完了。** `DownloadProgress(completed: true)` の emit も、完了後の
`checkModel()` が `available` になることも、不定進捗インジケータの表示も、
**いずれも確認できていない。**
## 総括(合否)

E2E_CHECKLIST.md の合否基準は「手順1〜7がすべて期待どおりに動作すること。
バグがあれば不合格」である。

| 手順 | 結果 |
|---|---|
| 1. checkModel | **不合格**(B-2: 連続呼び出しで偽の `unavailable` を返す) |
| 2. downloadModel | **未完了**(1回目は何もemitせず即完了、2回目は11分ハング。B-4) |
| 3. transcribeFile | **不合格**(B-1: ほとんどの呼び出しが `ERROR_SERVER_DISCONNECTED(11)` で即時失敗。長尺では B-3 も) |
| 4. キャンセル | 合格(ただしセッションを開始できるまでのリトライを要した) |
| 5. セッション排他 | 合格 |
| 6. エラーパス | 一部不一致(F-1: `LocaleUnsupportedException` へ到達できない)。`DeviceUnsupportedException` は未実施 |
| 7. オフライン確認 | **未実施** |
| 8. 包含率(記録項目) | ja-JP 10秒 66.7%(M0 と同値)、en-US 10秒 100%(**しきい値を満たす**)、3分クリップは B-3 のため 4.0〜17.9% |

**総合判定: 不合格。**

ただし **M0 から劣化した箇所は見つかっていない。** 認識精度は M0 と同値で
あり、M0 で未解決だった「確定テキストが `null` になる」現象は再現しなかった。
発見した B-1 / B-2 / B-3 は、いずれも M0 スパイクには存在しなかった構造
(`transcribeFile()` 内での `checkModel()` 先行呼び出し、`SpeechRecognizer`
の `destroy()` の非同期化、長尺対応のストリーミング化)に由来しており、
**本番実装が初めて実機で走ったからこそ見えた問題である。**

## 次にやるべきこと

1. **B-1 の原因確定と修正。** これが直らないとライブラリとして使えない。
   `ModelAvailability.querySupport()` の `destroy()` を同期的に完了させてから
   コルーチンを再開する、あるいは `transcribeFile()` 内の `checkModel()` と
   認識セッションで `SpeechRecognizer` インスタンスを共有する、といった
   方向が考えられるが、**いずれも未検証の案である。**
2. B-2(偽の `unavailable`)。少なくとも `querySupport()` が失敗理由を
   捨てないようにすること。
3. **B-4(`querySupport()` が返らずハングする)。** `MAX_WAIT_MS` の判定を
   `querySupport()` の外側(`withTimeout` 等)へ移すか、`querySupport()`
   自体にタイムアウトを持たせること。現状は `checkModel()` も
   `downloadModel()` も無期限にハングしうる。
4. B-3(長尺での確定テキスト欠落)。仮説リセットをまたいだテキストの
   扱いを design.md で決めること。
5. F-1(`LocaleUnsupportedException` への到達経路)。チェックリストと実装の
   どちらを正とするか決めること。
6. **非Pixel機での再実行(Issue #50 の残り半分)。**
7. 手順7(機内モードでのオフライン確認)。B-1 修正後に実施すること。

## 本検証のために追加したもの

| パス | 内容 |
|---|---|
| `apps/example/integration_test/android_baseline_e2e_test.dart` | 本検証の実行本体。手順1〜6と追加測定 |
| `apps/example/tool/stage_baseline_audio.sh` | 基準音声・実環境相当音源・不正ファイルを `assets/baseline-audio/` へ複製する(APKへ焼き込まれ、`setUpAll` が端末上へ書き出す)。**以前の `push_baseline_audio.sh`(adb push 方式)は競合するため削除した** |
| `test-assets/keyword_score.py` | design.md §7 の正規化・判定をそのまま実装した採点スクリプト |
| `apps/example/pubspec.yaml` | `integration_test` と `path_provider` を dev_dependency に追加 |

**注意: `path_provider` の追加は `apps/example/windows/flutter/
generated_plugins.cmake` に `jni` を追加する副作用がある**(path_provider
の推移的依存)。`flutter pub get` が生成する差分であり、本検証で意図的に
入れたものではない。Windows ビルド(CI の `flutter build windows --debug`)
への影響は **未検証** である。`path_provider` を使っている理由は
`getExternalStorageDirectory()` が必要だからで、生パスに対する
`Directory.createSync()` は `Permission denied` になる(実測)。

---

# 追記: B-1 / B-3 / B-4 修正後の再実行(同一端末)

上記の初回実行で見つかった不具合のうち B-1 / B-3 / B-4 を修正し、**同じ
Pixel 6 で同じ手順を回し直した**。ここに書く数値はすべてその実測である。

実行日時は初回と同日、環境は上記「実行環境」と同一
(Pixel 6 / Android 17 / API 37 / ビルド `CP2A.260705.006`、Flutter 3.41.9、
JDK 17、`RECORD_AUDIO` 未付与)。

## 何を直したか

### B-1: `destroy()` を post していたことがサービス切断を起こしていた

`ModelAvailability.querySupport()` の後始末が
`mainExecutor.execute { destroy() }` と **post** していた。ところが
`checkRecognitionSupport()` のコールバックは、本関数が渡した同じ
`mainExecutor` 上で走る。**つまり既にメインスレッド上であり、post すると
「現在のメッセージ処理の後」に回る。**

その結果:

1. `onSupportResult()` が continuation を再開する
2. 呼び出し元が認識用の `SpeechRecognizer` を生成する(2 sessions)
3. **その後で**モデル確認用の `destroy()` が走る
4. 音声認識サービスの接続が切れ、直後の `startListening()` が
   `ERROR_SERVER_DISCONNECTED(11)` で失敗する

`Looper.myLooper() == Looper.getMainLooper()` のときは**その場で同期破棄する**
ようにした。メインスレッド以外(キャンセル経路)からの呼び出しは従来どおり
post する。

**この post は M3 のレビュー指摘「`SpeechRecognizer` はメインスレッドから
操作する契約であるため post せよ」への対応として入れたものである。**
契約自体は正しいが、既にメインスレッド上である経路にまで一律に post を
適用したことが原因だった。実機で走らせるまで気づけなかった。

### B-3: 仮説リセットで前半が失われていた

`onPartialResults()` の内容が「直前の仮説の続き」ではなく「新しい仮説の
先頭」になったことを検出し、確定済みセグメントを貯めて最後に連結する
ようにした。判定は `RecognitionSession.isHypothesisReset()`
(「長さが半分未満に縮み、かつ直前の接頭辞でもない」)。

連結時は `RecognitionSession.joinWithOverlap()` が、累積テキストの末尾と
次セグメントの先頭が一致する最長区間を取り除く。

**いずれも経験則であり、OSが公開している判定手段ではない。** 単体テスト
(`RecognitionSessionResetTest` 6件 / `RecognitionSessionJoinTest` 5件)は
判定規則が意図どおりに書けていることを確認するもので、**閾値の妥当性は
実機でしか確かめられない**。

### B-4: タイムアウトが機能していなかった

`ModelAcquisition.run` がデッドライン判定を `querySupport()` の**後**にしか
行っておらず、`querySupport()` 自体にも上限が無かった。デッドライン判定を
呼び出しの前にも置き、`withTimeoutOrNull(QUERY_TIMEOUT_MS = 15秒)` で
1回の再照会にも上限を設けた。

## 手順3 の再実行結果(8ファイル)

| クリップ | 所要 | partials | finals | done | error |
|---|---|---|---|---|---|
| jaJP_10s.wav | 10,353ms | 61 | 1 | true | null |
| jaJP_10s.m4a | 10,034ms | 61 | 1 | true | null |
| enUS_10s.wav | 13,458ms | 71 | 1 | true | null |
| enUS_10s.m4a | 13,473ms | 73 | 1 | true | null |
| jaJP_3m.wav | 176,499ms | 1,335 | 1 | true | null |
| jaJP_3m.m4a | 176,389ms | 1,342 | 1 | true | null |
| enUS_3m.wav | 180,317ms | 1,159 | 1 | true | null |
| enUS_3m.m4a | 179,114ms | 1,145 | 1 | true | null |

**8/8 が成功した。** 修正前は20回中3回(15%)しか成功しなかったので、
B-1 は解消したと判断してよい。ただし**これは2回の通し実行
(修正直後の1回と本再実行)での結果であり、長期的な再現性までは確かめて
いない。** `ERROR_SERVER_DISCONNECTED` は元々間欠的に出るものだったため、
非Pixel機での確認(Issue #50 の残り半分)と併せて追試すべきである。

## キーワード包含率の再測定

採点は `test-assets/keyword_score.py`(design.md §7 の正規化を厳密実装)。

| クリップ | 修正前 | 修正後 | 判定 | 確定テキスト長 / 期待 |
|---|---|---|---|---|
| jaJP_10s.wav | 66.7% | **66.7%** | 不成立 | 51 / 57 |
| jaJP_10s.m4a | 66.7% | **66.7%** | 不成立 | 51 / 57 |
| enUS_10s.wav | 100.0% | **100.0%** | **合格** | 154 / 159 |
| enUS_10s.m4a | 100.0% | **100.0%** | **合格** | 154 / 159 |
| jaJP_3m.wav | 17.9% | **82.1%** | 不成立 | 1,054 / 1,151 |
| jaJP_3m.m4a | 17.9%(注) | **78.6%** | 不成立 | 1,058 / 1,151 |
| enUS_3m.wav | 4.0% | **32.0%** | 不成立 | 3,779 / 2,888 |
| enUS_3m.m4a | 4.0%(注) | **32.0%** | 不成立 | 3,761 / 2,888 |

(注) 修正前は B-1 のため wav/m4a のどちらかしか成功しない実行があった。

**10秒クリップの値は修正前後で1文字も変わっていない。** B-1 / B-3 の修正が
認識結果そのものに影響していないことの裏付けになる。

**3分クリップは大幅に改善した。** jaJP_3m は 17.9% → 82.1% で、確定テキストも
343文字相当から1,054文字(期待1,151)になった。**ja-JP では重複は生じて
いない。**

## 残る問題: enUS_3m に約890文字の重複が残る

`enUS_3m` の確定テキストは **3,779文字** で、期待の 2,888文字を大きく
超えている。`joinWithOverlap()` を入れる前が3,800文字だったので、
**重複除去はほとんど効いていない。**

理由は実測から明らかで、**再認識のたびに細部が揺れるため完全一致の重なりが
成立しない**。同じ箇所が `Moji tall core` と `Mojit tall core`、
`9.80 per month` と `9.80 cents per month`、`ISO 2701` と `ISO 27001` の
ように違う文字列で出る。

対処として曖昧一致(編集距離等)による重複除去も考えられるが、**採らなかった**。
誤って本文を削る危険があり、欠落は復元できない一方で重複は読めば分かる
ためである。`joinWithOverlap()` は完全一致の重なりだけを取り除く。

**包含率への影響は無い**(重複は部分文字列の集合を増やしこそすれ減らさない)。
`enUS_3m` が 32.0% に留まるのは重複ではなく**キーワード設計側の問題**である。
未一致の大半は、期待キーワードが英単語綴りなのに認識結果が数字表記になる
ものである。

- `three hundred and twenty thousand` ⇔ 認識結果 `320 000`
- `ninety six point four percent` ⇔ 認識結果 `96.4`
- `forty five seconds` ⇔ 認識結果 `45 seconds`

design.md §7 は「表記が複数あり得るキーワードは `.json` の `keywords` に
**許容表記を列挙**し、いずれか1つに一致すれば一致とみなす」と定めている。
`enUS_3m.json` はこれに従っていない。**これはライブラリの不具合ではなく
基準音声セット側の不備である。** 修正は M0 出口判定(Issue #19 / #20 で
「基準音声セットの読み上げスクリプトとキーワード選定を見直すか」として
保留されている論点)に属するため、本E2Eでは事実の記録に留める。

## 単体テスト

`RecognitionSessionResetTest`(6件)と `RecognitionSessionJoinTest`(5件)を
追加した。Kotlin JVM テストは計31件全成功。

| テストクラス | 件数 |
|---|---|
| ErrorMappingTest | 5 |
| RealtimePumpTest | 7 |
| RecognitionSessionJoinTest | 5 |
| RecognitionSessionResetTest | 6 |
| ResamplerStreamingTest | 7 |
| ResamplerTest | 6 |

## この再実行で確認していないこと

- **B-2(`checkModel()` が偽の `unavailable` を返す)は未修正・未再測定である。**
  B-1 と同じ「サービス接続の churn」が原因である可能性はあるが、**確かめて
  いない**。手順1-b の再実行を行っていない
- **B-4 の修正は実機で発火させていない。** ダウンロード対象の未取得ロケールで
  実際にハングさせて上限が効くことを確認したわけではなく、コードパスの
  是正に留まる
- **F-1(`LocaleUnsupportedException` に到達できない)は未対処である。**
  チェックリストと実装のどちらを正とするかは設計判断であり、本E2Eの範囲外
- **非Pixel機での検証は未実施。Issue #50 はこれで閉じない**
- 手順2 / 手順7 / example app の UI 経路は初回実行と同じく未実施

---

# 追記2: 実行条件の確定と、修正後の最終実行

「B-1 修正後も不安定さが残る」と一度書いたが、**それは誤りだった。**
不安定に見えた原因は**すべて実行条件側**にあり、ライブラリの不具合ではない。
同じ罠にはまらないよう、判明した3つを先に書く。

## この手順を実行するときの必須条件

### 1. 端末の画面を起こし続ける

**3分クリップを含む通し実行は13分以上かかる。** その間に画面が消えると
Android の Doze がアプリを凍結し、音声認識サービスとの接続が切れる。

```
mWakefulness=Dozing
RemoteSpeechRecognitionService: Connection to speech recognition service lost
```

実測では、放置した実行が 68分・90分と停止したまま戻らなかった。実行前に
次を設定すること。

```
adb shell svc power stayon usb
adb shell input keyevent KEYCODE_WAKEUP
```

### 2. 音声は APK へ焼き込む(`adb push` しない)

`flutter test` は実行のたびにアプリをインストールし直すため、事前に
`adb push` したディレクトリは消える。番兵ファイルで待ち合わせる方式は
競合し、実測で2通りに壊れた。

- 全ファイルが `MISSING` のままテストが「成功」する(空振り)
- セットアップで停止したまま戻らない

`tool/stage_baseline_audio.sh` が `assets/baseline-audio/` へ複製し、
`setUpAll` が `rootBundle` からアプリのキャッシュディレクトリへ書き出す。
Darwin 側の `darwin_baseline_e2e_test.dart` と同じ経路である。

### 3. 直前に音声認識サービスを止める

テストを途中で中断すると、端末側の `SpeechRecognitionManagerServiceImpl` が
セッションを掴んだまま残ることがある。この状態では `transcribeFile()` が
`checkModel()` の段階から先へ進まず、**logcat にも認識サービスの活動が
1行も出ない**(通常出るはずの `#onCheckRecognitionSupport` すら出ない)。

```
adb shell am force-stop com.moongift.example
adb shell am force-stop com.google.android.as
```

## 最終実行の結果(8/8 成功)

上記3条件を満たして実行した結果である。

| クリップ | 所要 | partials | finals | done | error |
|---|---|---|---|---|---|
| jaJP_10s.wav | 10,257ms | 61 | 1 | true | null |
| jaJP_10s.m4a | 10,056ms | 61 | 1 | true | null |
| enUS_10s.wav | 12,468ms | 71 | 1 | true | null |
| enUS_10s.m4a | 12,513ms | 73 | 1 | true | null |
| jaJP_3m.wav | 175,803ms | 1,344 | 1 | true | null |
| jaJP_3m.m4a | 175,856ms | 1,345 | 1 | true | null |
| enUS_3m.wav | 178,831ms | 1,164 | 1 | true | null |
| enUS_3m.m4a | 178,761ms | 1,157 | 1 | true | null |

`All tests passed!`。**B-1 修正後、条件を満たした実行は3回とも 8/8 成功
している**(修正直後の2回と本実行)。修正前は20回中3回(15%)だった。

## キーワード包含率(最終)

| クリップ | 修正前 | 最終 | 判定 | 確定テキスト長 / 期待 |
|---|---|---|---|---|
| jaJP_10s.wav | 66.7% | **66.7%** | 不成立 | 51 / 57 |
| jaJP_10s.m4a | 66.7% | **66.7%** | 不成立 | 51 / 57 |
| enUS_10s.wav | 100.0% | **100.0%** | **合格** | 154 / 159 |
| enUS_10s.m4a | 100.0% | **100.0%** | **合格** | 154 / 159 |
| jaJP_3m.wav | 17.9% | **82.1%** | 不成立 | 1,059 / 1,151 |
| jaJP_3m.m4a | 17.9% | **78.6%** | 不成立 | 1,059 / 1,151 |
| enUS_3m.wav | 4.0% | **40.0%** | 不成立 | 4,305 / 2,888 |
| enUS_3m.m4a | 4.0% | **40.0%** | 不成立 | 4,311 / 2,888 |

**10秒クリップの値は B-1〜B-4 の修正を通して1文字も変わっていない。**
修正が認識結果そのものに影響していないことの裏付けである。

**`enUS_3m` には依然として約1,400文字の重複が残る**(4,305 / 期待2,888)。
`joinWithOverlap()` は完全一致の重なりしか除かず、再認識のたびに細部が
揺れる(`Moji tall core` / `Mojit tall core`、`ISO 2701` / `ISO 27001`)ため
拾いきれない。曖昧一致での除去は本文を削る危険があるため採っていない。
包含率への影響は無い(重複は部分文字列の集合を減らさない)。

`enUS_3m` が 40.0% に留まるのは**基準音声セット側の不備**である。期待
キーワードが英単語綴り(`three hundred and twenty thousand`)なのに認識結果は
数字表記(`320 000`)になる。design.md §7 は「許容表記を列挙する」と定めて
いるが `enUS_3m.json` が従っていない。M0 出口判定(Issue #19 / #20)で
保留になっている論点であり、ライブラリの不具合ではない。

## Issue #50 の扱い

本 Issue は当初「Pixel系 + 非Pixel系の2機種」を求めていたが、**利用者の判断に
より1機種(Pixel 6)で完了とした。** 非Pixel機での検証は実施していない。
