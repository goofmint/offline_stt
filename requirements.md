# requirements.md

Flutterライブラリ「オフライン音声ファイル文字起こし」要件定義

## 1. 概要

録音済みの任意の音声ファイルを、OSネイティブの音声認識APIのみでオフライン文字起こしするFlutterライブラリ。認識モデル・推論エンジン・バイナリは一切同梱せず、モデルの取得・更新・管理はすべてOS側(Android の音声認識サービス / AssetInventory / Chrome)に委ねる。

## 2. 目的

- 既存の音声ファイル(ボイスメモ、録音、会議音声)をネットワーク非依存でテキスト化する共通APIを提供する
- pub.dev上に存在しない「ファイル入力・オフライン・モデル非同梱」の空白領域を埋める
- アプリサイズを増やさない(モデル同梱型の代替: whisper.cpp / sherpa-onnx / Vosk との差別化点)

## 3. スコープ

### 対象

| プラットフォーム | バックエンドAPI | モデル管理 | M0検証結果(§10 参照) |
|---|---|---|---|
| Android | 標準 `android.speech.SpeechRecognizer`(`createOnDeviceSpeechRecognizer`)**(構成変更済み。下記「M0判定の反映」参照)** | OS / Google Play services のオンデバイス言語パック(`triggerModelDownload` / `checkRecognitionSupport`) | 技術成立(Pixel 6実機)。**精度は不成立**(jaJP_10s 66.7%) |
| iOS / macOS | SpeechAnalyzer | OS (AssetInventory) | 技術成立(macOS 26.5.1実機)。**精度は不成立**(jaJP_10s 66.7%)。iOS は `supportedLocales` 照会のみ実施 |
| Web | Chrome オンデバイスWeb Speech (processLocally) | Chrome (言語パック約60MB。ja-JP言語パックの取得はChrome 153で実機確認済み) | 技術成立(Chrome 153実機)。**精度は不成立**(jaJP_10s 1.0x 66.7%) |

### M0判定の反映(Issue #19)

3プラットフォームのM0検証結果を上表へ反映した内容は以下のとおりである。根拠は
`spikes/{web,darwin,android}/RESULTS.md`。

1. **Android: バックエンドを構成変更した(対象外化ではなく差し替え)。** 当初のML Kit GenAI
   Speech Recognition は AICore を前提とするが、検証に使用した Pixel 6 実機の
   `com.google.android.aicore` は実体の無い stub 版であり、**Google Play ストア自身が
   Pixel 6 を非対応端末として明示している**。`checkStatus()` / `startRecognition()` は
   いずれも `PERMISSION_DENIED: Api access revoked.` を返し、端末側の制約であって
   アプリ側の実装では回避できない。「モデルを同梱しない」(NFR-3)という方針を維持できる
   代替として、標準 `android.speech.SpeechRecognizer` のオンデバイス認識で
   `EXTRA_AUDIO_SOURCE` によるファイル入力が受理されることを Pixel 6 実機で実測したため、
   これを採用した。**したがって本書でAICore / ML Kit GenAI を前提とする記述はすべて失効している。**
   どの機種であれば実体のあるAICoreを持つかは未検証であり、断定しない。
2. **精度は3プラットフォームすべてで不成立だが、対象外化しない。** Darwin・Web・Android は
   同一の基準音声 `jaJP_10s` でいずれも 66.7%(4/6)であり、design.md §7 のしきい値に届かない。
   ただし**不成立の原因は未確定**である(基準音声がTTS合成音声であること、キーワード選定と
   正規化規則、認識モデル自体の精度、プリセット選択を分離する対照実験を行っていない)。
   3プラットフォームが同率であり、かつ3つとも同じキーワード `株式会社モーンギフト` を
   落としていることは、原因が基準音声側にある可能性を否定できないことを示す。
   原因が未確定である以上、この結果を根拠にいずれかのプラットフォームを対象外化する判断は
   行わず、基準音声セット・キーワード選定・しきい値の見直しを含めて別途決める。

### 対象外

- Linux(OSネイティブのASR APIが存在しないため。LinuxユーザーはWeb版を利用)
- マイクからのリアルタイム認識(将来拡張候補。v1はファイル入力専用)
- モデルの同梱・ダウンロード・自前管理
- クラウドASRへのフォールバック
- 話者分離、翻訳、要約

## 4. 機能要件

### FR-1 モデル状態確認

- `checkModel(locale)` で対象ロケールのモデル状態を返す
- 状態は4値に正規化: `available` / `downloadable` / `downloading` / `unavailable`
- 各OSの状態モデルとの対応:
  - Android: `SpeechRecognizer.checkRecognitionSupport()` が返す `RecognitionSupport` の `supportedOnDeviceLanguages` / `installedOnDeviceLanguages` / `pendingOnDeviceLanguages` / `onlineLanguages` の4リストを突き合わせて4値へ写像する(ML Kit GenAI Speech Recognitionの `checkStatus()` は不採用。spikes/android/RESULTS.md 参照)。写像方針: 対象ロケールが `installedOnDeviceLanguages` に含まれれば `available`、`pendingOnDeviceLanguages` に含まれれば `downloading`、いずれにも含まれないが `supportedOnDeviceLanguages` に含まれれば `downloadable`、いずれにも含まれなければ `unavailable`。Pixel 6実機での実測では `isRecognitionAvailable() = true`・`isOnDeviceRecognitionAvailable() = true`・`supportedOnDeviceLanguages`(36件)にja-JPを含み、ML Kit GenAI Speech Recognitionの `checkStatus()` が `PERMISSION_DENIED` を返した状況とは対照的に正常応答した(spikes/android/RESULTS.md 参照)。なお `triggerModelDownload()` の `ModelDownloadListener` はダウンロード完了を確実には通知しない実測があるため、完了判定は本APIの再照会でのみ行える(spikes/android/RESULTS.md 参照)
  - Web: `SpeechRecognition.available()` の AvailabilityStatus
  - iOS/macOS: AssetInventory の照会結果(`AssetInventory.status` の `.installed` は予約(reserve)状態に連動する一時状態であり、ディスク上の永続状態を表す `installedLocales` とは別軸であることをmacOS実機で確認済み。この挙動はiOS実機でも再現し、macOS固有の挙動ではなくSpeechAnalyzer APIの仕様であることを確認済み。4値への写像には両方の突き合わせが必要。spikes/darwin/RESULTS.md 参照)

### FR-2 モデルダウンロード

- `downloadModel(locale)` でOS管理のモデル取得をトリガーし、進捗をStreamで返す
- ダウンロードはユーザー同意後に呼び出す前提とし、同意UIはライブラリ利用者(アプリ側)の責務とする
- Webの `install()` は進捗イベントを提供せず `Promise<boolean>` のみを返すため(Chrome 153で実機確認済み、spikes/web/RESULTS.md 参照)、不定進捗として扱う
- Androidは `SpeechRecognizer.triggerModelDownload(intent, executor, ModelDownloadListener)` でOS管理の言語パック取得をトリガーする。**`ModelDownloadListener` の `onScheduled`/`onProgress`/`onSuccess`/`onError` はダウンロード完了時に発火しない実測がある**(Pixel 6実機でja-JP言語パックを取得した際、`onScheduled()` のみ発火し、以降60秒以内に他のコールバックが一切到達しなかった。しかし直後に再照会すると実際にはダウンロードが完了していた)。そのため完了判定はコールバックに依らず、`checkRecognitionSupport()` を再照会し `installedOnDeviceLanguages` に対象ロケールが現れたかで行う(spikes/android/RESULTS.md 参照)

### FR-3 ファイル文字起こし

- `transcribeFile(path, locale)` で音声ファイルを文字起こしし、`Stream<TranscriptSegment>` を返す
- partial結果を許容する(isFinalフラグで区別)
- キャンセル可能であること(Streamのcancelで下層の認識セッションを停止)
- Webでは確定(final)結果が形態素単位で空白区切りされることをChrome 153実機で確認した(spikes/web/RESULTS.md 参照)。アプリへ返す前にこの空白を除去するかどうか、Web実装ではテキスト整形の方針を決める必要がある
- 再生速度オプション(`playbackRate`、§7参照)は、1.0より大きい値を指定すると所要時間を短縮できるが、認識精度が低下しうる。Chrome 153実機でのjaJP_10s(音声長9.56秒、期待キーワード6件)実測は以下のとおりである

  | 再生速度 | 所要時間 | 包含率 | isFinal発火 |
  |---|---|---|---|
  | 1.0x | 9,676 ms | 4/6 = 66.7% | あり |
  | 1.1x | 8,808 ms | 4/6 = 66.7% | なし(interim採用) |
  | 1.25x | 7,726 ms | 4/6 = 66.7% | なし(interim採用) |
  | 1.5x | 6,464 ms | 3/6 = 50.0% | あり |
  | 1.75x | (未実施) | (未実施) | (未実施) |
  | 2.0x | 4,867 ms | 2/6 = 33.3% | あり |

  1.25xまでは本測定ではキーワード包含率そのものは変化しなかったが、認識結果のテキスト自体はキーワード判定に現れない形で劣化が進行していた。例えば「株式会社モーンギフト」の認識結果は、1.0x「ムーンギフト」→ 1.1x「モヨンギフト」→ 1.25x「オンギフト」→ 1.5x「モンギフト」→ 2.0x(消失)と推移した。包含率が同じでも精度が劣化している場合があるため、包含率のみでの判断は不十分である
- Androidでは `RecognitionListener.onResults()` の確定結果(`RESULTS_RECOGNITION`)が `null` になり、確定テキストが得られない実測がある(Pixel 6実機、`EXTRA_AUDIO_SOURCE` 経由のファイル入力で2回の独立実行いずれも再現)。完全なテキストは `onPartialResults()` 側に逐次emitされ、最長のpartialが実質的な文字起こし結果になる。したがってAndroid実装では**末尾のpartial結果を確定結果として扱う**必要がある。Web(本節前掲、Chrome 153実機)で `isFinal` が立たない場合に末尾interimを採用したのと同じ構図である(spikes/android/RESULTS.md 参照)

### FR-4 音声デコード層(任意フォーマット対応の中核)

- 入力: 一般的な音声ファイル形式(wav / m4a / mp3 / aac 等、各OS標準デコーダが対応する範囲)
- 各OS純正デコーダのみ使用(方針維持のためFFmpeg等の同梱は不可):
  - Android: MediaCodecで 16kHz・モノラル・16-bit raw PCM へ変換し、実時間レート(毎秒約32KB)でParcelFileDescriptorに供給するポンプを実装。MediaCodecはコーデックのデコードのみを行いサンプルレート変換・チャンネルのダウンミックスは行わないため(実測で確認済み、spikes/android/RESULTS.md 参照)、16kHz・モノラルへの変換処理はライブラリ側で別途実装する必要がある
  - iOS/macOS: AVFoundationでデコードしSpeechAnalyzerへ入力
  - Web: `AudioContext.decodeAudioData` → MediaStreamAudioDestinationNode → `start(audioTrack)`
- デコード不能なファイルは明確なエラー型で通知

### FR-5 ロケール指定

- BCP-47形式でロケールを指定
- 対応ロケールはプラットフォーム・モードごとに異なるため、静的リストを持たず `checkModel(locale)` による実行時解決とする
- 日本語(ja-JP)は全プラットフォームで動作検証を必須とする(検証済み事項: Android(標準 `SpeechRecognizer`)は Pixel 6 実機で `supportedOnDeviceLanguages`(36言語)に ja-JP が含まれ、`triggerModelDownload()` による ja-JP 言語パックの取得と、`EXTRA_AUDIO_SOURCE` 経由のファイル入力による ja-JP 認識が成立することを実測済み(spikes/android/RESULTS.md 参照)。初期状態の `installedOnDeviceLanguages` は `[en-US]` のみであり、ja-JP は取得が必要だった。Chrome オンデバイス = ja-JP対応。Chrome 153で `available()` が `downloadable`、`install()` 後に `available` へ遷移することを実機確認済み(spikes/web/RESULTS.md 参照)。iOS SpeechAnalyzer の日本語対応は実機検証で確認する。うちmacOS 26.5.1実機では `SpeechTranscriber.supportedLocales`(30件)に `ja-JP` が含まれることを確認済み。iOS 27.0実機(iPhone 17)でも `SpeechTranscriber.supportedLocales`(45件)に `ja-JP` が含まれることを確認済み。macOS 26.5.1の30件とiOS 27.0の45件は一致しておらず、この実測が本節冒頭の「静的リストを持たず `checkModel(locale)` による実行時解決とする」という設計判断を裏付けている(spikes/darwin/RESULTS.md 参照)

### FR-6 エラーモデル

- 共通エラー型: `modelUnavailable` / `localeUnsupported` / `decodeFailed` / `deviceUnsupported` / `cancelled` / `platformError(原因)`
- Android固有: `android.speech.SpeechRecognizer` の `RecognitionListener.onError(error: Int)` が返す `ERROR_*` 定数(`ERROR_AUDIO` / `ERROR_CLIENT` / `ERROR_INSUFFICIENT_PERMISSIONS` / `ERROR_NETWORK` / `ERROR_NETWORK_TIMEOUT` / `ERROR_NO_MATCH` / `ERROR_RECOGNIZER_BUSY` / `ERROR_SERVER` / `ERROR_SERVER_DISCONNECTED` / `ERROR_SPEECH_TIMEOUT` / `ERROR_TOO_MANY_REQUESTS` / `ERROR_LANGUAGE_NOT_SUPPORTED` / `ERROR_LANGUAGE_UNAVAILABLE` / `ERROR_CANNOT_CHECK_SUPPORT` / `ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS`)を共通エラー型へ写像する基盤とする(design.md §5 参照)。**ML Kit GenAI Speech Recognitionは不採用としたため、同APIに固有だった「ブートローダーアンロック端末では動作しない」旨のエラーや、AICoreがstub版の場合の `PERMISSION_DENIED: Api access revoked.` といった記述は、採用しなかったバックエンドに関する記録としてspikes/android/RESULTS.md にのみ残し、本節のエラーモデルからは対象外とする**
- Android固有(続き): 「ブートローダーアンロック端末では動作しない」という制約はML Kit GenAI Speech Recognition固有のものであり、構成変更後の標準 `SpeechRecognizer` に同じ制約があるかは**未検証**である(検証に使用した Pixel 6 はブートローダーがロック済みであり、アンロック端末での対照実験を行っていない)

## 5. 非機能要件

### NFR-1 処理時間

- 所要時間はプラットフォーム依存であることをAPI契約に明記
- Android(実時間レート供給制約)とWeb(リアルタイム処理)はファイル長と同等の時間がかかる。Webについては、Chrome 153実機で9.56秒の基準音声(jaJP_10s)の文字起こしに9,676msを要し、Webが実時間処理であることが実測で裏付けられた(spikes/web/RESULTS.md 参照)
- Webは再生速度オプション(`playbackRate`、§7参照)により、この実時間制約を緩和できる。1.0より大きい値を指定すると所要時間は短縮される(jaJP_10s実測: 1.0xで9,676ms、2.0xで4,867ms)。ただし処理時間の短縮と認識精度はトレードオフの関係にあり、`AudioBufferSourceNode.playbackRate` はピッチも同倍率で変化させるため、速度を上げるほど精度が低下しうる(1.0x: 66.7% → 1.5x: 50.0% → 2.0x: 33.3%、jaJP_10s実測。spikes/web/RESULTS.md 参照)
- macOS 26.5.1実機では RTF(処理時間 ÷ 実時間長)0.008〜0.026、すなわち実時間の約38〜125倍高速にファイル入力の文字起こしが完了することを実測済み(spikes/darwin/RESULTS.md 参照)。Android/Webの実時間制約とは対照的に高速である。iOSのファイル処理速度は実機未測定であり、引き続き要実測

### NFR-2 プライバシー

- 音声・書き起こし結果を一切ネットワーク送信しない。Webは `processLocally = true` を強制し、サーバー認識へのサイレントフォールバックを禁止する

### NFR-3 パッケージサイズ

- ライブラリ本体にモデル・推論バイナリを含めない。各パッケージはブリッジコードのみ

### NFR-4 最低動作環境

- Android 12 (API 31) 以上
- iOS 26 以上 / macOS 26 以上
- Chrome 142 以上(オンデバイスWeb Speechのリグレッション修正済みバージョン)

### NFR-5 バージョニング

- 土台のAPIが新しく、iOS/macOSのSpeechAnalyzerもOS 26で導入されたばかりである。また各OSのオンデバイス認識の挙動には実測で判明した未確定要素が残る(design.md §8)。そのためライブラリは0.x系で公開し、各OS APIのstable化までstableを名乗らない

## 6. パッケージ構成(単一パッケージ)

`offline_stt` は単一パッケージであり、Android / iOS / macOS / Web の全実装を
1つのパッケージに同梱する(Issue #91)。**アプリは `dependencies:` に
`offline_stt:` とだけ書けばよく、実装ごとに個別のパッケージへ依存する必要は
無い。**

- `lib/offline_stt.dart`: 公開バレル。`OfflineTranscriber` とデータ型・例外型のみを公開する
- `lib/src/offline_transcriber.dart`: 利用者向けファサード `OfflineTranscriber`
- `lib/src/offline_transcriber_platform.dart`: 内部の抽象クラス(公開APIではない)
- `lib/src/backend.dart` + `backend_io.dart` / `backend_web.dart`: 実行環境に応じた実装選択(design.md §1参照)
- `lib/src/android/` / `lib/src/darwin/` / `lib/src/web/`: 各プラットフォーム実装(Kotlin側は `android/`、Swift側は `darwin/` に同梱)
- `apps/example/`: 参照実装のexample app(公開対象外)

## 7. 共通API(案)

```dart
enum ModelState { available, downloadable, downloading, unavailable }

class TranscriptSegment {
  final String text;
  final bool isFinal;
}

abstract class OfflineTranscriber {
  Future<ModelState> checkModel(String locale);
  Stream<double> downloadModel(String locale);
  Stream<TranscriptSegment> transcribeFile(String path, String locale, {double playbackRate = 1.0});
}
```

- タイムスタンプ・信頼度スコアはプラットフォーム間で対応差が大きいためv1では非対応(将来拡張)
- `playbackRate`(既定値 1.0)は再生速度を指定するオプションである。意味を持つのはWebのみで、`AudioBufferSourceNode.playbackRate` に直結する。Darwin(SpeechAnalyzer)はバッチ処理であり速度という概念自体が存在しないため、指定しても無視される(値そのものは受理するが動作に影響しない)。Androidは実時間ポンプ方式のため理論上は同種の適用余地があるが、M0時点では未検証である

## 8. 利用者(アプリ側)に課される制約(ドキュメント必須事項)

- Android: 対象ロケールのオンデバイス言語パックが端末に無い場合があるため、`checkModel()` を必ず先に呼ぶUX(Pixel 6実機の初期状態では `installedOnDeviceLanguages` が `[en-US]` のみであり ja-JP は未取得だった)。なお構成変更により **AICore / ML Kit GenAI は使用しないため、「AICore初期化を待つ」といった対応は不要である**(§3「M0判定の反映」参照)
- モデルダウンロード同意ダイアログの実装(文言ガイドライン: モデル名ではなく「音声認識モデル」等の一般名称)
- Web: ファイル選択はユーザー操作起点(File / Blob)。Chrome以外のブラウザでは `unavailable` を返す

## 9. リスク

| リスク | 影響 | 対策 |
|---|---|---|
| ~~ML Kit GenAI (alpha) の破壊的変更~~ → **顕在化のうえ解消済み(構成変更)** | Android実装の書き直し | ML Kit GenAI は AICore を前提とするが、Pixel 6 実機で AICore が stub 版であり Google Play ストア自身が非対応と明示することが判明した。標準 `android.speech.SpeechRecognizer` へ差し替え済み(§3「M0判定の反映」)。差し替え後の残課題は下行を参照 |
| 標準 `SpeechRecognizer` の端末差・`onResults()` が確定テキストを返さない事例 | Android品質のばらつき、確定結果が得られない | Pixel 6 実機で `onResults()` の `RESULTS_RECOGNITION` が `null` になる事象を実測した(原因未特定)。他機種での挙動も未検証。実機E2E(Issue #50)で追試する |
| Chrome オンデバイスWeb Speechの不安定さ(過去に一時無効化の実績) | Web実装が突然動かなくなる | `available()` を毎回確認、機能検出ベースで劣化 |
| iOS SpeechAnalyzer の日本語対応が未確認 | 主要ユースケース不成立 | 実装前に3プラットフォームでja-JP実機検証(マイルストーン0)。macOS 26.5.1実機・**iOS 26.6.2実機(下限、30件)**・iOS 27.0実機(45件)のいずれでも`supportedLocales`にja-JPを含むことを確認済み(spikes/darwin/RESULTS.md 参照)。**`supportedLocales`はOSバージョンで実際に変わるため下限での確認が必要だったが、Issue #7 で完了した。** **(b)iOS実機でのファイル文字起こし検証は Issue #40 で完了した**(iPad Pro / iOS 26.6.2 で基準音声8ファイル、16回すべて完走) |
| `continuous = true` では `source.onended` 後に明示的に `recognition.stop()` を呼ばないと `onend` が発火せず、セッションが終了しない(終了検出の実装漏れ) | Web実装がアプリ側の実装ミスで無応答になる(transcribeFile()のStreamが完了しない) | design.md §4.1 に必須手順として明記済み。Chrome 153実機で `onended` 内の `stop()` 呼び出しにより `isFinal` 結果と `onend` が発火することを確認済み(spikes/web/RESULTS.md 参照) |
| ~~Advanced→Basicフォールバック挙動が未検証~~ → **失効**(ML Kit GenAI 固有の論点であり、構成変更により該当しなくなった) | - | - |
| 最低OSバージョンが高くユーザー母数が限られる | **ML Kit GenAI Speech Recognitionを採用しないことで、当初懸念していた「Googleが個別に対応と認めたAICore搭載ハードウェアでしか動かない」というリスクは大幅に低減した。** 差し替え後の標準 `android.speech.SpeechRecognizer` は、API 37・ブートローダーロック済みのPixel 6実機(ML Kit GenAI Speech Recognitionでは `checkStatus()` が `PERMISSION_DENIED: Api access revoked.` を返し動作しなかった端末)で、ja-JPのオンデバイス言語パック取得・ファイル入力受理・文字起こしのいずれも実測で成功した(spikes/android/RESULTS.md 参照)。ただし**この実測はPixel 6単一機種によるものであり、他機種・他OEMでの動作は未検証のまま残る** | READMEには「APIレベルの要件(NFR-4のAndroid 12/API 31以上)を満たしていても、`checkRecognitionSupport()` の結果は機種・言語パック導入状況によって異なりうる」旨を明記する。M3実装時にPixel 6以外の複数機種で追加検証を行い、対応機種の線引きを確定させる(spikes/android/RESULTS.md 参照) |
| キーワード包含率が design.md §7 のしきい値に届かない(検証できた3プラットフォームすべて) | 「OSネイティブで十分な精度が出る」という前提が崩れる | 原因が未確定(基準音声・キーワード選定・正規化規則・モデル精度・プリセット)であるため、対照実験による切り分けを行ったうえで、しきい値と基準音声セットの見直しを含めて判断する。READMEには実測値と原因未確定である旨を明記済み |

## 10. マイルストーン

- M0 検証: 3プラットフォームで ja-JP のファイル文字起こしをスパイク実装で確認(特に iOS の日本語、Webの組み合わせ動作)。不成立のプラットフォームがあれば構成を再検討
  - **結果**: Web / Darwin / Android の3つは技術統合が成立。精度は検証できた3つすべてで不成立(原因未確定)。Android のみバックエンドの構成変更を実施した。詳細は §3「M0判定の反映」を参照
- M1 Web実装: 純Dartで最速検証。デコード層とモデル管理UXのAPI形状をここで固める
- M2 iOS/macOS実装(darwin統合)
- M3 Android実装(MediaCodecポンプ含む)
- M5 pub.dev公開(0.1.0)、example app、対応状況マトリクスのREADME整備
