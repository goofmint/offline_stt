# RESULTS.md — Web M0 検証結果

対応 Issue: #3 / #4 / #5 / #6。対応する設計: design.md §4.1 Web、§8 未決事項4。

**このファイルは未記入のテンプレートである。実機実行(Chrome 142+)は呼び出し元が別途行い、その結果をここに記入した上で、tasks.md / requirements.md / design.md へ反映する。未記入箇所は `(未実施)` と明示している。**

## 検証環境

| 項目 | 値 |
|---|---|
| 実行日時 | 2026-09-20(JST) |
| Chromeバージョン(正確な値、`chrome://version` 等で確認) | 153.0.8010.48 |
| ブラウザUA | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36` |
| OS | macOS 26.5.1 (build 25F80), arm64 |
| 配信方法(localhost / https、URLも記載) | localhost(`http://localhost:8765/spikes/web/index.html`、リポジトリルートを `python3 -m http.server 8765` で配信) |
| 実行方法 | Chrome DevTools Protocol 経由でクリーンな一時プロファイル(新規 user-data-dir)を使用 |
| 言語パック状態(実行開始時点) | 未取得(クリーンプロファイルのため) |

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

## `start(audioTrack)` + `processLocally: true` 併用動作(Issue #5、design.md §8 未決事項4)

| 項目 | 値 |
|---|---|
| 成否 | (未実施 — 環境要因。下記「実行環境の制約」参照) |
| `audioTrack.readyState` | (未実施 — 環境要因。下記「実行環境の制約」参照) |
| `processLocally` 読み戻し値(設定直後) | (未実施 — 環境要因。下記「実行環境の制約」参照) |
| エラーの有無(`onerror` の `error` プロパティ) | (未実施 — 環境要因。下記「実行環境の制約」参照) |
| 所見(未決事項4の結論に使う) | (未実施 — 環境要因。下記「実行環境の制約」参照) |

## NFR-2 確認(プライバシー)

| 項目 | 値 |
|---|---|
| DevTools Networkタブでのネットワーク送信有無 | (未実施 — 認識セッションを開始できていないため) |
| `"network"` エラーの有無 | (未実施 — 認識セッションを開始できていないため) |
| NFR-2違反の疑いの有無 | (未実施 — 認識セッションを開始できていないため) |

## クリップ別結果(Issue #6)

| クリップID | 形式 | 包含率 | 合否 | 所要時間 | 備考(失敗理由等) |
|---|---|---|---|---|---|
| jaJP_10s | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| jaJP_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_10s | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_10s | m4a | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_3m  | wav | (未実施) | (未実施) | (未実施) | (未実施) |
| enUS_3m  | m4a | (未実施) | (未実施) | (未実施) | (未実施) |

判定は design.md §7 のしきい値による(ja-JP: 95%以上合格・90〜94%条件付き合格・90%未満不成立。en-US: 95%以上合格・95%未満不成立)。

## Web 総合判定

| 項目 | 値 |
|---|---|
| 総合判定(成立 / 不成立) | (保留 — #5 / #6 未実施のため判定不能) |
| 根拠 | `available()` と `install()` による言語パック取得までは成立を確認済み。`start(audioTrack)` 併用と精度判定は未実施 |

## 実行環境の制約(Issue #5 / #6 が未実施である理由)

`decodeAudioData → MediaStreamAudioDestinationNode → start(audioTrack)` のパイプラインは、この自動実行環境では走らせられなかった。観測された事実は以下のとおりである。

- `SpeechRecognition` インスタンスに `processLocally = true` を設定し、読み戻したところ `true` を返した(設定自体は可能)
- `AudioContext.decodeAudioData` は成功した。`jaJP_10s.wav`(16kHz/モノラル、306,066バイト)を復号した結果、`duration = 9.56s`、`AudioBuffer.sampleRate = 48000`、`numberOfChannels = 1` となった。AudioContext が 16kHz から 48kHz へ自動リサンプリングしている
- `MediaStreamAudioDestinationNode` から得た `MediaStreamTrack` の `readyState` は `"live"` だった
- しかし `AudioContext.currentTime` が `0.01` 秒で停止したまま進まなかった(`AudioContext.state` は `"running"` を返すにもかかわらず)。そのため `AudioBufferSourceNode` が再生されず、`onended` も発火せず、認識結果(partial / final)もエラーも一切得られなかった
- `navigator.mediaDevices.enumerateDevices()` は audioinput 1件 / audiooutput 1件 / videoinput 1件を返しており、デバイス自体は列挙できている
- 回避を4通り試したがいずれも同じ症状だった: (1) 通常起動、(2) `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling --autoplay-policy=no-user-gesture-required` 付き起動、(3) macOS の `osascript` でウィンドウを前面化、(4) `open -na` による LaunchServices 経由起動。また `--use-fake-device-for-media-stream --use-file-for-fake-audio-capture` で `getUserMedia` から音声トラックを得る代替経路も試したが、`getUserMedia` の Promise が解決しなかった
- 結論: これは Web Speech API 側の制約ではなく、CDP 制御下の一時プロファイル Chrome でオーディオレンダリングスレッドが動作しないという実行環境の制約である。Issue #5 / #6 の判定には、通常の対話的な Chrome セッションでの手動実行が必要である

---

記入後、以下への反映を検討すること(このファイル自体の役目ではなく、呼び出し元が別途実施):

- `tasks.md` の Web セクション各項目のチェック
- `requirements.md` の対応表(FR-5 検証済み事項)への反映
- `design.md` §8 未決事項4 の確定値への更新
