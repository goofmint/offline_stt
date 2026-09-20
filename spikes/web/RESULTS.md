# RESULTS.md — Web M0 検証結果

対応 Issue: #3 / #4 / #5 / #6。対応する設計: design.md §4.1 Web、§8 未決事項4。

**このファイルは Web M0 スパイクの実機検証結果である。** Issue #3 / #4(`available()` / `install()`)と Issue #5 / #6(`start(audioTrack)` + `processLocally: true` の併用動作、基準音声での精度確認)は、**それぞれ異なる実行条件で実施した**(詳細は各節冒頭の検証環境表を参照)。Issue #3 / #4 は CDP(Chrome DevTools Protocol)管理下のクリーンな一時プロファイルで、言語パック未取得の状態から実施した。Issue #5 / #6 は、後述のとおり一時プロファイルではオーディオレンダリングが動作しなかったため、ユーザーの通常の Chrome プロファイルでの対話的な実行に切り替え、ja-JP言語パック取得済みの状態で実施した。いずれも Chrome 153.0.8010.48、localhost配信、実行日時 2026-09-20(JST)である。ただし精度確認(Issue #6)は基準音声 `jaJP_10s`(wav、1.0x/1.5x/2.0x)のみが実施範囲であり、`jaJP_3m` / `enUS_*` / m4a形式は本ラウンドでは未実施である(該当箇所は `(未実施)` と明示している)。

## 検証環境(Issue #3 / #4: 可用性チェック・言語パック取得)

| 項目 | 値 |
|---|---|
| 実行日時 | 2026-09-20(JST) |
| Chromeバージョン(正確な値、`chrome://version` 等で確認) | 153.0.8010.48 |
| ブラウザUA | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36` |
| OS | macOS 26.5.1 (build 25F80), arm64 |
| 配信方法(localhost / https、URLも記載) | localhost(`http://localhost:8765/spikes/web/index.html`、リポジトリルートを `python3 -m http.server 8765` で配信) |
| 実行方法 | Chrome DevTools Protocol 経由でクリーンな一時プロファイル(`--user-data-dir` に新規ディレクトリを指定して起動) |
| 言語パック状態(実行開始時点) | 未取得(クリーンプロファイルのため)。`available()` が `downloadable` を返すことと、`install()` により `available` へ遷移することをこの節で確認した |

## `available()` 戻り値(Issue #3)

機能検出: `window.SpeechRecognition` が存在(`hasSR: true`)。`SpeechRecognition.available` および `SpeechRecognition.install` も存在(いずれも `true`)。

| ロケール | 戻り値 | 備考(例外発生時は `err.name` / `err.message`) |
|---|---|---|
| ja-JP | `"downloadable"` | 例外なし |
| en-US | `"downloadable"` | 例外なし |

参考: `SpeechRecognition.available({ langs: ['ja-JP'], processLocally: false })` → `"available"`(サーバー認識は常時利用可。オンデバイスのみ言語パック取得が必要であることを示す)

## `install()` 結果(Issue #4)

| 項目 | 値 |
|---|---|
| 実行有無 | 実行した |
| `install()` 戻り値の型 | `[object Promise]` |
| Promise解決値 | `true`(型は `boolean`) |
| 進捗イベント(`downloadprogress` 等)の有無 | なし。戻り値に `addEventListener` は存在せず(`typeof p.addEventListener !== 'function'`)、進捗イベントは購読不可 |
| 所要時間 | 8743 ms(約8.7秒) |
| 実行後の `available()` 戻り値 | `"available"` |
| 言語パック取得の成功条件(install後に `available` を返すか)を満たしたか | 満たした |

## 検証環境(Issue #5 / #6: audioTrack併用動作・精度確認)

| 項目 | 値 |
|---|---|
| 実行日時 | 2026-09-20(JST) |
| Chromeバージョン | 153.0.8010.48 |
| OS | macOS 26.5.1 (build 25F80), arm64 |
| 配信方法 | localhost(`http://localhost:8765/spikes/web/index.html`、リポジトリルートを `python3 -m http.server 8765` で配信) |
| 実行方法 | ユーザーの通常の Chrome プロファイルでの対話的な実行(CDP管理下の一時プロファイルではオーディオレンダリングが動作しなかったため。詳細は本ファイル末尾「実行環境の制約」参照) |
| 言語パック状態(実行開始時点) | 取得済み。ja-JPを `install()` により取得済みで、`available()` が `available` を返す状態から開始した |

## `start(audioTrack)` + `processLocally: true` 併用動作(Issue #5、design.md §8 未決事項4)

| 項目 | 値 |
|---|---|
| 成否 | 成立。`processLocally = true` の設定と読み戻しが成功し、`audioTrack.readyState = "live"` の状態で `recognition.start(audioTrack)` が受理され、`onstart` が発火した。音声が実時間で処理され partial 結果が継続的に得られ、`stop()` 呼び出し後に `isFinal` の結果と `onend` が発火してセッションが正常終了した |
| `audioTrack.readyState` | `"live"`(開始時・認識中とも) |
| `processLocally` 読み戻し値(設定直後) | `true` |
| エラーの有無(`onerror` の `error` プロパティ) | エラーなし。`network` エラーも発生しなかった |
| 所見(未決事項4の結論に使う) | 併用動作は成立する。ただし `continuous = true` では `AudioBufferSourceNode` が再生を終えても `MediaStreamTrack` は `live` のまま無音を流し続けるため、Chrome は入力終了を自動認識しない。`source.onended` の後に明示的に `recognition.stop()` を呼んで初めて、約25ms後に `isFinal` の結果が発火し、その直後に `onend` が発火してセッションが終了した。design.md §4.1 の「sourceの `onended` 後、`recognition.onend` をもって Stream close」を成立させるには、`onended` ハンドラ内で `stop()` を呼ぶ実装が必須である |

## NFR-2 確認(プライバシー)

| 項目 | 値 |
|---|---|
| DevTools Networkタブでのネットワーク送信有無 | 目視確認は未実施。DevTools Networkタブでの目視によるパケットレベルの確認は行っていない |
| `"network"` エラーの有無 | 発生しなかった。Issue #5 / #6 の全実行を通じて `recognition.onerror` の `error` プロパティが `network` になった事例は一度もなかった |
| NFR-2違反の疑いの有無 | `network` エラーが発生しなかったという事実からは違反の兆候は見られない。ただしこれは DevTools Networkタブでのパケットレベルの確認を代替するものではなく、その確認自体は未実施である |

## クリップ別結果(Issue #6)

音声長 9.56秒、期待キーワード6件(jaJP_10s.wav)。

| クリップID | 形式 | 包含率 | 合否 | 所要時間 | 備考(失敗理由等) |
|---|---|---|---|---|---|
| jaJP_10s(1.0x) | wav | 4/6 = 66.7% | 不成立 | 9,676 ms | 不一致キーワード: 東京都渋谷区(「東京 都 渋谷 で」と誤認識、「区」→「で」)/ 株式会社モーンギフト(「株式会社 ムーン ギフト」と誤認識、「モーン」→「ムーン」) |
| jaJP_10s(1.5x) | wav | 3/6 = 50.0% | 不成立 | 6,464 ms | `AudioBufferSourceNode.playbackRate` による倍速再生(ピッチも同倍率で変化)。不一致キーワード: 東京都渋谷区 / 株式会社モーンギフト / 128名 |
| jaJP_10s(2.0x) | wav | 2/6 = 33.3% | 不成立 | 4,867 ms | 倍速再生(ピッチも同倍率で変化)。不一致キーワード: 東京都渋谷区 / 午後3時 / 株式会社モーンギフト / 128名 |
| jaJP_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_10s | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |

判定は design.md §7 のしきい値による(ja-JP: 95%以上合格・90〜94%条件付き合格・90%未満不成立。en-US: 95%以上合格・95%未満不成立)。`jaJP_10s` の m4a 形式、および `jaJP_3m` / `enUS_10s` / `enUS_3m` の全形式は本ラウンドでは未実施である。

1.0x の所要時間 9,676ms は音声長 9.56秒とほぼ同じであり、NFR-1 の「Webは実時間処理」が実測で裏付けられた。

## 確定結果のテキスト形式

partial と final でテキスト形式が異なることを確認した。

- partial: `東京都渋谷で2024年11月3日午後3時株式会社ムーンギフトが新製品を発表しました来場者は128名でした`
- final: `東京 都 渋谷 で 2024 年 11 月 3 日 午後 3 時 株式会社 ムーン ギフト が 新 製品 を 発表 し まし た 来場 者 は 128 名 でし た`

**確定結果は形態素単位で空白区切りされている。** 包含率の正規化は空白を除去するため判定には影響しないが、ライブラリがアプリへ返すテキストには余計な空白が入る。アプリへ返す前にこの空白を除去する等の整形が必要である。

## 再生速度による精度の変化

`AudioBufferSourceNode.playbackRate` による速度変更は、ピッチも同倍率で変化する(Web Audio にピッチ保持のタイムストレッチは無い)。jaJP_10s.wav での実測は以下のとおりであり、**1.0x → 1.5x → 2.0x と単調に精度が低下**した。

| 再生速度 | 所要時間 | 包含率 | 一致キーワード | 不一致キーワード |
|---|---|---|---|---|
| 1.0x | 9,676 ms | 4/6 = 66.7% | 2024年11月3日 / 午後3時 / 新製品 / 128名 | 東京都渋谷区 / 株式会社モーンギフト |
| 1.5x | 6,464 ms | 3/6 = 50.0% | 2024年11月3日 / 午後3時 / 新製品 | 東京都渋谷区 / 株式会社モーンギフト / 128名 |
| 2.0x | 4,867 ms | 2/6 = 33.3% | 2024年11月3日 / 新製品 | 東京都渋谷区 / 午後3時 / 株式会社モーンギフト / 128名 |

1.5x でも「モーンギフト→モンギフト」「128名→約28名」と崩れる。**実用的なスループット向上の余地はない。** 倍速再生は非対応の方針とする。

## 言語パック未取得時の挙動

言語パック(モデル)を `install()` で取得する前に `start()` を呼ぶと、ロケールによって異なる、原因が分かりにくいエラーが返ることを確認した。

- ja-JP: `aborted`
- en-US: `language-not-supported`

いずれも `ModelUnavailable` に相当する状況を直接表すエラー名ではないため、design.md §3 のとおり、`start()` 呼び出し前に `checkModel()` 相当(`SpeechRecognition.available()`)で状態を確認し、`available` であることを保証してから認識を開始する実装が必須である。

## Web 総合判定

| 項目 | 値 |
|---|---|
| 総合判定(成立 / 不成立) | 動作面(`available()` / `install()` / `start(audioTrack)` + `processLocally`)は**成立**。精度は design.md §7 のしきい値(ja-JP: 95%以上合格・90〜94%条件付き)に対して 66.7%(jaJP_10s、1.0x)であり**不成立** |
| 根拠 | `available()` と `install()` による言語パック取得、`start(audioTrack)` + `processLocally: true` の併用動作(`stop()` 呼び出しによる正常終了含む)はいずれも Chrome 153 実機で確認済み。一方、基準音声 jaJP_10s での精度は 66.7% で90%未満のため不成立である。ただし macOS 26.5.1 の Darwin スパイクも同一の基準音声(jaJP_10s)で 66.7%(4/6)であり同率である(外したキーワードは異なる: Darwin は株式会社モーンギフト / 128名、Web は東京都渋谷区 / 株式会社モーンギフト)。不成立の原因が(a)基準音声の設計(TTS合成音声・キーワード選定)によるものか、(b)両プラットフォームの認識モデル自体の実力によるものか、切り分けはできていない。design.md §7「注記: Darwin M0スパイクでのキーワード包含率実測結果」で述べられているとおり、原因未確定であることを理由に精度判定を条件付き成立として扱ってはならない。この論点は tasks.md「M0 出口判定」で決めるべき事項として残す |

## 実行環境の制約(Issue #5 / #6 が未実施である理由)

`decodeAudioData → MediaStreamAudioDestinationNode → start(audioTrack)` のパイプラインは、この自動実行環境では走らせられなかった。観測された事実は以下のとおりである。

- `SpeechRecognition` インスタンスに `processLocally = true` を設定し、読み戻したところ `true` を返した(設定自体は可能)
- `AudioContext.decodeAudioData` は成功した。`jaJP_10s.wav`(16kHz/モノラル、306,066バイト)を復号した結果、`duration = 9.56s`、`AudioBuffer.sampleRate = 48000`、`numberOfChannels = 1` となった。AudioContext が 16kHz から 48kHz へ自動リサンプリングしている
- `MediaStreamAudioDestinationNode` から得た `MediaStreamTrack` の `readyState` は `"live"` だった
- しかし `AudioContext.currentTime` が `0.01` 秒で停止したまま進まなかった(`AudioContext.state` は `"running"` を返すにもかかわらず)。そのため `AudioBufferSourceNode` が再生されず、`onended` も発火せず、認識結果(partial / final)もエラーも一切得られなかった
- `navigator.mediaDevices.enumerateDevices()` は audioinput 1件 / audiooutput 1件 / videoinput 1件を返しており、デバイス自体は列挙できている
- 回避を4通り試したがいずれも同じ症状だった: (1) 通常起動、(2) `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling --autoplay-policy=no-user-gesture-required` 付き起動、(3) macOS の `osascript` でウィンドウを前面化、(4) `open -na` による LaunchServices 経由起動。また `--use-fake-device-for-media-stream --use-file-for-fake-audio-capture` で `getUserMedia` から音声トラックを得る代替経路も試したが、`getUserMedia` の Promise が解決しなかった
- 結論: これは Web Speech API 側の制約ではなく、CDP 制御下の一時プロファイル Chrome でオーディオレンダリングスレッドが動作しないという実行環境の制約である。Issue #5 / #6 の判定には、通常の対話的な Chrome セッションでの手動実行が必要である

**追記(2026-09-20)**: 上記の制約は CDP 制御下の一時プロファイルに限定される問題であり、通常の対話的な Chrome セッション(ユーザーの通常 Chrome プロファイル)では `AudioContext.currentTime` が正常に進行し、`decodeAudioData → MediaStreamAudioDestinationNode → start(audioTrack)` のパイプライン全体が問題なく動作した。これにより Issue #5(併用動作)と Issue #6(jaJP_10s での精度確認)を実測できた。詳細は上記各節を参照。

---

記入後、以下への反映を検討すること(このファイル自体の役目ではなく、呼び出し元が別途実施):

- `tasks.md` の Web セクション各項目のチェック
- `requirements.md` の対応表(FR-5 検証済み事項)への反映
- `design.md` §8 未決事項4 の確定値への更新
