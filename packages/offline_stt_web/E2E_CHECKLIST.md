# offline_stt_web E2E 手動チェックリスト

対応 Issue: #31。対応する設計: design.md §7「テスト戦略」(「CI: ビルド検証のみ
…認識E2Eは手動チェックリスト運用」)、§4.1 Web、§5 エラーマッピング表。

**リリース前に人手で実行する手順書である。** `spikes/web/README.md` の手順を
土台にしている。

## なぜCIで検証できないのか

以下はいずれも実測に基づく事実であり、Webの認識E2Eを自動CIに乗せられない
理由である。

1. **オンデバイスWeb Speech APIそのものが実ブラウザ・実言語パックを要求する。**
   `SpeechRecognition.available()` / `install()` / `start(audioTrack)` は
   Chromeが実際に音声認識モデルをOSに保持しているかどうかに依存する。ヘッド
   レスブラウザやモックでは代替できない(design.md §4.1)。
2. **CDP(Chrome DevTools Protocol)管理下のクリーンな一時プロファイルでは
   オーディオレンダリングが動作しない実測結果がある。** M0検証時、
   `decodeAudioData → MediaStreamAudioDestinationNode → start(audioTrack)` の
   パイプラインを自動化ハーネス(CDP制御)から実行したところ、
   `AudioContext.currentTime` が `0.01` 秒で停止したまま進行せず、
   `AudioBufferSourceNode` が再生されず、認識結果もエラーも一切得られな
   かった。`--autoplay-policy=no-user-gesture-required` 等のフラグや複数の
   起動方法を試したが再現しなかった。通常の対話的Chromeセッション(ユーザー
   の通常のChromeプロファイル)でのみ問題なく動作した。詳細は
   `spikes/web/RESULTS.md`「実行環境の制約」参照。この制約はCI環境(通常
   ヘッドレス・自動化されたブラウザ制御を用いる)にそのまま当てはまる。
3. **言語パック取得(`install()`)に8秒程度かかり、かつ一度取得すると
   ブラウザプロファイルに永続化される。** CI実行のたびにクリーンな状態から
   検証しようとすると毎回ダウンロードが必要になり、CI実行環境の
   ネットワーク・時間コストが不安定になる。
4. **認識精度(キーワード包含率)がCIで決定的に再現しない可能性が高い。**
   オンデバイス音声認識モデルはChromeの自動更新に追従するため、同じ音声
   ファイルでもモデルのバージョンによって認識結果が変わりうる。design.md §7
   の「評価基準(キーワード包含率)」はWERの代替指標であり、決定的な
   バイナリ合否ではなく人間が確認すべき性質のものである。

## 前提

- **Chrome 142 以上**(requirements.md NFR-4)、デスクトップ版。実機検証時は
  Chrome 153で確認済み(spikes/web/RESULTS.md)。
- **localhost または https 配信であること。** `on-device-speech-recognition`
  Permissions Policyの既定値が `'self'` であるため、`file://` で直接開いても
  動作しない。
- **通常の対話的Chromeプロファイルで実行すること。** 自動化ツール(CDP等)の
  制御下にあるクリーンな一時プロファイルでは、上記「なぜCIで検証できないか」
  2. のとおりオーディオレンダリングが動作しない実測結果があるため。
- 対象ロケール(`ja-JP` / `en-US`)の言語パックの取得状態を、手順内の
  可用性チェックで都度確認する(未取得でもチェックリスト内でinstallする)。
- 基準音声: `test-assets/baseline-audio/` 配下(`jaJP_10s` / `jaJP_3m` /
  `enUS_10s` / `enUS_3m`、wav・m4a各形式、期待テキストとキーワードリストは
  対応する `.json` / `.txt` を参照)。

## 手順

### 1. 可用性チェック

1. `example` アプリ(またはWebアプリ)をChromeで開く。
2. 対象ロケール(`ja-JP` / `en-US`)について `checkModel(locale)` を呼び出し、
   結果を画面またはログで確認する。
3. 期待される戻り値:
   - 初回(言語パック未取得): `downloadable`
   - 取得済み: `available`
   - Chrome以外のブラウザで開いた場合: `unavailable`(design.md §4.1・
     Issue #30の確認を兼ねる)

### 2. install(モデルダウンロード)

1. `checkModel()` が `downloadable` を返したロケールについて
   `downloadModel(locale)` を呼び出す。
2. `DownloadProgress(fraction: null, completed: false)` が最初に1回、完了時に
   `DownloadProgress(fraction: null, completed: true)` が1回、計2回emitされる
   ことを確認する(design.md §4.1「install()は進捗イベントを持たず
   Promise<boolean>を返す」ため不定進捗として扱う実装になっている)。
3. 完了後、`checkModel(locale)` を再実行し `available` になっていることを
   確認する。

### 3. 文字起こし実行

1. `test-assets/baseline-audio/` の基準音声ファイルをファイル選択でロードし、
   `Blob URL`(`URL.createObjectURL`)を `TranscribeRequest.path` に渡して
   `transcribeFile()` を実行する。
2. 以下を目視・ログで確認する:
   - partial(`isFinal: false`)のセグメントが実行中に継続的に届くこと
   - 最終的に `isFinal: true` のセグメントが1件以上届き、Streamが `done` で
     完了すること
   - `isFinal: true` の結果テキストに、Chrome内部の形態素区切り空白
     (`東京 都 渋谷 で` のような)が**残っていない**こと(空白除去の実装
     確認。`lib/src/final_text_formatting.dart` 参照)
   - DevTools Networkタブで、文字起こし実行中に音声データや認識結果らしき
     ペイロードが外部へ送信されていないこと(NFR-2確認)
   - `recognition.onerror` の `error` が `network` になっていないこと
     (NFR-2違反の兆候が無いことの確認)
3. `playbackRate` を 1.0 以外(例: 1.5)に変更して再実行し、以下を確認する:
   - 所要時間が短縮されること
   - `isFinal: true` が一度も発火しないまま完了した場合、末尾のinterim結果が
     確定結果として採用され、かつ `developer.log`(名前: `offline_stt_web`)
     にその旨が記録されていることをDevTools Consoleで確認する
     (`lib/src/recognition_session.dart` 参照)

### 4. キャンセル

1. 文字起こし実行中に購読(`StreamSubscription`)を `cancel()` する。
2. 以下を確認する:
   - それ以降 `TranscriptSegment` が届かないこと
   - `AudioContext` がリークせず解放されること(DevTools Performance /
     Memoryタブ、または連続実行してもエラーが蓄積しないことで確認)
   - 再生開始前(`onstart` 前)にキャンセルした場合でも例外なく終了すること

### 5. 包含率確認

1. 結果テキストと、対応する `.json` の `keywords` を突き合わせ、design.md §7
   「評価基準(キーワード包含率)」の正規化ルール(NFKC正規化→小文字化→
   句読点/記号除去→空白除去、ja-JPはひらがな→カタカナ畳み込み)に従って
   一致数を数える。
2. しきい値(design.md §7)に照らして判定する:

   | 条件 | 言語 | 合格しきい値 |
   |---|---|---|
   | クリーン基準音声 | ja-JP | 90%以上(90〜94%は条件付き合格) |
   | クリーン基準音声 | en-US | 95%以上 |

3. **参考値であることに注意する。** design.md §7「注記」のとおり、M0時点の
   実測(`spikes/web/RESULTS.md`)ではjaJP_10s(1.0x)で66.7%であり、上記
   しきい値に対して不成立だった。この結果はM0スパイクのものであり、本番
   実装(本パッケージ)での再測定が必要である。しきい値未達がライブラリの
   実装バグによるものか、認識モデル自体の精度限界によるものかを都度切り分
   けること。

## 合否基準

- 手順1〜4は**すべて期待どおりに動作すること**(バグがあれば不合格)。
- 手順5(包含率)は上記しきい値を目安とし、未達の場合はdesign.md §7の
  「1.0x → 1.5x → 2.0xと単調に精度が低下する」という既知の特性(倍速再生
  時)を踏まえたうえで、原因(実装バグかモデル精度限界か)を記録すること。
  未達そのものは自動的に不合格を意味しない(design.md §7も参照)が、原因
  未調査のまま合格扱いにしてはならない。
