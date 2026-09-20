# offline_stt_android E2E 手動チェックリスト

対応 Issue: #66(収録)、#50(実機E2Eの実施)。対応する設計: design.md §7
「テスト戦略」、requirements.md FR-1/FR-2/FR-3/FR-6。共通の前提・包含率の
算出方法・しきい値は
[リポジトリルートの E2E_CHECKLIST.md](../../E2E_CHECKLIST.md) を参照。

**リリース前に人手で実行する手順書である。** 土台は M0 検証
(`spikes/android/RESULTS.md`、Pixel 6 実機)である。

**実行結果は [E2E_RESULTS.md](E2E_RESULTS.md) に記録する。** 2026-09-21 に
Pixel 6(Android 17 / API 37)で本番実装に対して初めて通した。結果は
**不合格**である(`transcribeFile()` が `ERROR_SERVER_DISCONNECTED(11)` で
即時失敗する不具合を発見した)。Issue #50 が要求する非Pixel機での検証は
未実施である。

## 認識バックエンドについて(古い記述に注意)

**本パッケージが使うのは Android 標準の `android.speech.SpeechRecognizer`
(オンデバイス)である。ML Kit GenAI / AICore ではない。**

当初設計は ML Kit GenAI Speech Recognition だったが、M0検証で使用した
Pixel 6 実機の AICore は `versionName` が `0.stub.stub_aicore_...` という
実体のない stub 版であり、`checkStatus()` / `startRecognition()` がいずれも
`PERMISSION_DENIED: Api access revoked.` を返した。Google Play ストア自身が
Pixel 6 を非対応と明示しており、アプリ側の実装では回避できない。そのため
バックエンドを標準 `SpeechRecognizer` へ差し替えてある
(spikes/android/RESULTS.md「代替案の検証: Android 標準 SpeechRecognizer」)。

**リポジトリ内に AICore / ML Kit GenAI を前提とした記述が残っている場合、
それは古い記述である**(design.md §4.3、.github/workflows/ci.yml のコメント
など)。

## なぜCIで検証できないのか

オンデバイス認識のモデルはOS / Google Play services 側が保持しており、
エミュレータには存在しない。さらにM0検証で、**実機であっても機種によっては
成立しない**ことが判明している(上記)。「実機さえあれば検証できる」という
前提そのものが誤りであったことが実測で示されている。

## 前提

- **実機であること。** エミュレータでは実行できない。
- **API 31 以上**(requirements.md NFR-4)。M0検証は Pixel 6 / API 37・
  ブートローダーロック済みで行った。
- **`SpeechRecognizer.isOnDeviceRecognitionAvailable()` が `true` を返す
  端末であること。** M0検証で確認できたのは Pixel 6 単一機種である。他機種の
  挙動は未検証であり、**対象ロケールが `supportedOnDeviceLanguages` に
  含まれない端末が存在しうる。**
- 基準音声: `test-assets/baseline-audio/`。
- 実行対象: `apps/example`(実機を指定して `flutter run`)。
- **`RECORD_AUDIO` 権限は付与しない。** 本実装はマイクを使わずPFDパイプ経由
  でファイルの音声を渡す。権限なしで動作することの確認を兼ねる。

## 手順

### 1. 可用性チェック(checkModel)

1. example app を起動し、`ja-JP` と `en-US` について `checkModel(locale)` を
   実行する。
2. ネイティブ側は `SpeechRecognizer.checkRecognitionSupport()` が返す
   `RecognitionSupport` の4リスト(`installedOnDeviceLanguages` /
   `pendingOnDeviceLanguages` / `supportedOnDeviceLanguages` /
   `onlineLanguages`)を突き合わせて `ModelState` を決める
   (requirements.md FR-1)。期待される戻り値:
   - `installedOnDeviceLanguages` に含まれる: `available`
   - `pendingOnDeviceLanguages` に含まれる: `downloading`
   - `supportedOnDeviceLanguages` にのみ含まれる: `downloadable`
   - いずれにも含まれない、または `isOnDeviceRecognitionAvailable()` が
     `false`: `unavailable`
3. `adb logcat` またはアプリのログで、実際の4リストの内容を記録する。
   M0検証時の Pixel 6 の値は `supportedOnDeviceLanguages` が36言語(ja-JP
   を含む)、`installedOnDeviceLanguages` が `[en-US]` のみだった。

### 2. downloadModel

1. `checkModel()` が `downloadable` を返したロケールについて、example app の
   **同意ダイアログで明示的に同意したうえで** `downloadModel(locale)` を
   実行する(requirements.md FR-2)。
2. **完了までに時間がかかる場合がある。** M0検証では
   `ModelDownloadListener` の `onScheduled()` のみが発火し、`onProgress()` /
   `onSuccess()` / `onError()` は60秒以内に一度も発火しなかった。それでも
   `installedOnDeviceLanguages` を再照会すると対象ロケールが現れており、
   ダウンロード自体は成立していた。2回目の実行では `onScheduled()` すら
   発火しなかった。
3. そのため本実装のネイティブ側は、完了判定を `ModelDownloadListener` では
   なく `checkRecognitionSupport()` の再照会でポーリングする。**この
   ポーリングが機能し、`DownloadProgress(completed: true)` が最終的に
   emit されることを確認する。**
4. 完了後に `checkModel()` を再実行し `available` になることを確認する。
5. `DownloadProgress.fraction` は `null`(不定進捗)になりうる。example app が
   不定進捗のインジケータを表示できていることを確認する。

### 3. 文字起こし実行(transcribeFile)

基準音声8ファイル(ja-JP / en-US × 10秒 / 3分 × wav / m4a)すべてについて
実行する。

1. 各ファイルについて、以下を確認する:
   - partial(`isFinal: false`)のセグメントが実行中に継続的に届き、
     **内容が音声の進行に追従して伸びていくこと**
   - 最終的に `isFinal: true` のセグメントが届き、Stream が `done` で
     完了すること
2. **【最重要】確定テキストが空でないことを確認する。** M0検証では、
   `onPartialResults()` は台本どおりに正しく伸びていったにもかかわらず、
   パイプのEOF直後に発火する `onResults()` の `RESULTS_RECOGNITION` が
   `null` だった。この現象は2回の独立した実行で再現し、`stopListening()` の
   呼び出し有無とは無関係だった。**原因は未特定である**
   (spikes/android/RESULTS.md「B: `EXTRA_AUDIO_SOURCE` によるファイル入力の
   受理確認」)。M0では未実施の「パイプclose直後、間を置かずに
   `stopListening()` を呼ぶ」順序を本実装が採っているかを含め、ここは
   最優先で確認する項目である。
3. **リサンプリングの確認。** 実環境の音源(44.1kHz / 48kHz ステレオ、mp3
   等)を渡して文字起こしできることを確認する。M0のデコードレート実測では、
   実環境相当音源7ファイル全てで `resampleNeeded=true` だった。
   `test-assets/baseline-audio/` は16kHz・モノラルで生成されているため、
   これだけではリサンプリング経路を通らない。
4. 処理時間を記録する。M0検証では実時間ポンプの実効レートが
   31,993.7バイト/秒(目標32,000バイト/秒)で、10秒クリップに対してほぼ
   実時間で追従した。**`transcribeFile()` は音声長と同程度の時間がかかる**
   (Darwinのようにファイル長より大幅に速くはならない)。
5. **`TranscribeRequest.playbackRate` はAndroidでは無視される**(Web専用
   オプション、design.md §2.2)。

### 4. キャンセル

1. 3分クリップの文字起こし実行中に購読(`StreamSubscription`)を
   `await subscription.cancel()` でキャンセルし、**返るFutureの完了まで
   待つ**。
2. 以下を確認する:
   - それ以降 `TranscriptSegment` が届かないこと
   - ネイティブ側がパイプclose →`stopListening()` → `destroy()` の順で
     後始末し、`ERROR_CLIENT`(5番)等のエラーがログに残らないこと
   - **キャンセルFutureの完了後に**別の `transcribeFile()` を開始でき、
     `StateError`(セッション排他違反)にならないこと。
     `TranscribeSessionGuard` はキャンセルFutureの完了を待たずにセッション枠
     を解放するため、これは `StateError` を避けるための待機ではなく、
     キャンセル後のネイティブ側の後始末が安定して終わったことを確認する
     ための待機である。未awaitで次を始めると、前のJobのキャンセル処理と
     次の開始処理が重なりうる
   - ポンプのスレッドがリークしないこと(連続実行を繰り返しても破綻
     しないこと)
3. **キャンセル経路はM0検証の範囲外であり、一度も検証されていない**
   (spikes/android/RESULTS.md「限界」)。

### 5. セッション排他(design.md §3)

1. `transcribeFile()` の Stream を購読したまま、2本目の `transcribeFile()` を
   購読する。
2. 2本目が Stream エラー(`StateError`)で即座に終了することを確認する。

### 6. エラーパス(requirements.md FR-6)

| 例外 | 発火方法 |
|---|---|
| `ModelUnavailableException` | 未取得のロケールで `transcribeFile()` を呼ぶ(暗黙にダウンロードが始まらないことの確認を兼ねる) |
| `LocaleUnsupportedException` | `supportedOnDeviceLanguages` に無いロケールを指定する |
| `DecodeFailedException` | テキストファイルを `.wav` として渡す |
| `DeviceUnsupportedException` | `isOnDeviceRecognitionAvailable()` が `false` の端末で実行する(該当端末がある場合) |
| `CancelledException` | 手順4のキャンセル |
| `PlatformException_` | 上記のいずれにも分類できないもの。`code` が保持されていることを確認する |

### 7. オフライン確認(NFR-2)

1. 機内モード、または Wi-Fi / モバイルデータを切った状態で手順3を実行し、
   文字起こしが成立することを確認する。
2. **M0検証ではこれを確認していない。** Wi-Fi接続状態で実行しており、
   実際に通信が発生しなかったことはパケットキャプチャ等で確認していない
   (`EXTRA_PREFER_OFFLINE=true` と `createOnDeviceSpeechRecognizer()` を
   使い、アプリに `INTERNET` 権限も付与していない、という設計上の根拠に
   留まる)。

### 8. キーワード包含率の記録

1. 各ファイルの確定テキストと `.json` の `keywords` を、ルートの
   E2E_CHECKLIST.md の正規化ルールに従って突き合わせる。
2. **しきい値未達は既知である。** M0検証では jaJP_10s で 66.7%(4/6)で
   あり不成立だった。ただしこれは確定テキストが得られなかったため、
   最終 partial テキストの最上位候補で代用した値である。不一致は
   「東京都渋谷区」(→「渋谷で」)と「株式会社モーンギフト」
   (→「モンギフト」)の2件で、「区」はどの候補でも一貫して脱落した。
3. **原因は未確定である。** 本番実装での値を記録し、M0の値から著しく劣化
   していないかを確認する。

## 合否基準

- 手順1〜7は**すべて期待どおりに動作すること**。バグがあれば不合格。
  特に手順3の2.(確定テキストが `null` にならないこと)は、未解決の既知
  現象であり最優先の確認項目である。
- 手順8(包含率)は記録項目である。しきい値未達そのものは自動的に不合格を
  意味しないが、**原因未調査のまま合格扱いにしてはならない**
  (design.md §7)。

## このチェックリストで確認できないこと

- **Pixel 6 以外の機種・他のOSバージョンでの挙動。** M0検証は単一機種の
  実測である。OEM のコーデック実装(ハードウェアデコーダ等)の差も未検証で
  ある。
- **人間の自然発話に対する精度。** 基準音声はTTS合成音声である。
