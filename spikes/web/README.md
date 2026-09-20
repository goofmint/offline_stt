# M0 検証スパイク: Web (Chrome オンデバイス Web Speech API)

対応 Issue: #3(可用性チェック)/ #4(言語パック取得)/ #5(audioTrack + processLocally併用動作)/ #6(キーワード包含率)。
対応する設計: design.md §4.1 Web、§5 エラーマッピング、§7 テスト戦略・評価基準、§8 未決事項4。
対応するタスク: tasks.md「M0 検証スパイク」> Web セクション。

このディレクトリは、Flutterライブラリの実装に入る前に「Web上でオンデバイスWeb Speech API + `processLocally: true` + `audioTrack` 入力の組み合わせが実際に動くか」を確認するための、ビルドツール非依存の単体HTML/JSスパイクである。素のHTML/CSS/JSのみで構成しており、外部ライブラリ・CDN・npm等には依存しない。

## 前提

- **Chrome 142 以上、デスクトップ版**(Windows / macOS / Linux のいずれでも可)。requirements.md NFR-4 の最低バージョンに合わせる。
- **Android / WebView は非対応**。オンデバイスWeb Speech APIはデスクトップChromeのみを対象とする。
- `on-device-speech-recognition` Permissions Policy は既定値が `'self'` であるため、**`file://` で直接 `index.html` を開いても動作しない**。`https://` または `http://localhost` (`http://127.0.0.1` を含む) からの配信が必要である。

## ローカル配信手順

```bash
cd spikes/web
python3 -m http.server 8000
```

ブラウザで `http://localhost:8000/` を開く。

(Python が無い環境では `npx serve .` 等、localhost で配信できる任意の静的サーバーで代替してよい。ビルドは不要。)

## 実行手順(番号順)

1. `http://localhost:8000/` を開く。ページ上部に実行環境情報(User-Agent / `location.protocol` / Chrome判定)が表示されることを確認する。
2. 「可用性チェック」ボタンを押す。`SpeechRecognition.available({langs:['ja-JP'], processLocally:true})` と同 `en-US` 版の戻り値が画面とコンソール双方に表示される。
3. ja-JP の結果が `downloadable` の場合のみ「言語パック取得 (install)」ボタンが有効化されるので、必要なら押す。`install()` の Promise 解決値と、取得可能であれば進捗イベント(`downloadprogress` 等、存在しない場合はログにその旨が出る)が表示される。
4. install 実行後、自動的に再度 `available()` が呼ばれ、状態遷移(`downloadable` → `available` 等)が表示される。**`available` になったことを確認してから次に進むこと。**
5. 「ファイル選択」で `test-assets/baseline-audio/` 配下の基準音声ファイル(例: `jaJP_10s.wav`)を選ぶ。ファイル名からクリップIDが自動推定され、推定できない場合はプルダウンで手動選択する。
6. 「文字起こし実行」ボタンを押す。実行ログに各ステップ(ファイル読込 → decodeAudioData → audioTrack取得 → processLocally読み戻し検証 → recognition.start → partial/final結果 → onend)が逐次表示される。
7. 実行完了後、「結果テキスト」欄に確定(final)テキストが表示され、コピー可能である。「キーワード包含率スコア」欄に一致率・判定(合格/条件付き合格/不成立)・一致/不一致キーワードの一覧が表示される。

上記を `jaJP_10s` / `jaJP_3m` / `enUS_10s` / `enUS_3m` の各クリップ、wav・m4a両形式で繰り返し、結果を `RESULTS.md` に転記する。

## `available()` の戻り値の意味

| 戻り値 | 意味 |
|---|---|
| `available` | 対象ロケールのモデルが既に端末上で利用可能。すぐに認識を開始できる。 |
| `downloadable` | モデルは未取得だが取得可能。`install()` を呼べる状態。 |
| `downloading` | 現在ダウンロード中。 |
| `unavailable` | この環境(非Chrome、対応ロケール外、機能自体が無効化されている等)では利用不可。 |

## 合否判定基準

- **言語パック取得(Issue #4)の成功条件**: `install()` 実行後に `available()` が `available` を返すこと。
- **精度(Issue #6)の合否**: design.md §7「評価基準(キーワード包含率)」のしきい値による。
  - ja-JP: 95%以上で合格、90〜94%は「条件付き合格 / 要確認」、90%未満は不成立。
  - en-US: 95%以上で合格、95%未満は不成立。
  - しきい値は `spike.js` 内の `THRESHOLDS` 定数にまとめてあり、design.md §7 由来である旨をコメントに明記している。

## NFR-2(プライバシー)の確認手順

1. 文字起こし実行の**前に** Chrome DevTools の Network タブを開いておく。
2. 「文字起こし実行」を行っている間、Network タブにリクエストが記録されないことを目視で確認する(特に音声データや認識結果らしきペイロードの送信が無いこと)。
3. 実行ログに `"network"` エラー(`recognition.onerror` の `error` プロパティが `network`)が出た場合は、**サーバー認識へのフォールバックが発生している兆候であり、NFR-2違反の疑いとして扱う**。この場合、Webでの実装は成立しないと判定する。
4. `processLocally` の読み戻し検証(`spike.js` の `buildRecognition()`)が `true` 以外を検出した場合、スパイク自体がその場で明確にエラー停止する(サーバーへの暗黙フォールバックはしない実装になっている)。

## design.md §8 未決事項4 との対応

`start(audioTrack)` + `processLocally: true` の併用動作は design.md 時点で未検証(未決事項4)。本スパイクの手順6・7の実行結果(成功/失敗、エラー種別、`audioTrack.readyState`)がこの未決事項の確定材料になる。結果は `RESULTS.md` に記録し、確定後に design.md 本体へ反映する(反映作業はスパイク実行者が別途行う)。

## M1 手動E2Eチェックリストの雛形として

このハーネスは tasks.md M1「E2E手動チェックリスト作成」の雛形を兼ねる。以降のマイルストーンでも、以下の順序を基本形として再利用できる。

- 前提確認(Chromeバージョン、配信方法が `https`/`localhost` であること、言語パック状態)
- 音声投入(基準音声ファイルを選択し、文字起こしを実行)
- 包含率確認(キーワード包含率としきい値照合、NFR-2の確認)

## ファイル構成

- `index.html` — UI本体
- `spike.js` — 可用性チェック・install・デコード/認識パイプライン・キーワード包含率スコアリングのロジック
- `keywords.json` — `test-assets/baseline-audio/*.json` の `locale` / `transcript` / `keywords` を集約したデータ(手書きではなく元ファイルからの転記)
- `README.md` — 本ファイル
- `RESULTS.md` — 実機検証結果(Chrome 153 での `available()` / `install()` は実測済み。`start(audioTrack)` 併用と精度確認は未実施)
