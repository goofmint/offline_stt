# requirements.md

Flutterライブラリ「オフライン音声ファイル文字起こし」要件定義

## 1. 概要

録音済みの任意の音声ファイルを、OSネイティブの音声認識APIのみでオフライン文字起こしするFlutterライブラリ。認識モデル・推論エンジン・バイナリは一切同梱せず、モデルの取得・更新・管理はすべてOS側(AICore / AssetInventory / Windows Update / Chrome)に委ねる。

## 2. 目的

- 既存の音声ファイル(ボイスメモ、録音、会議音声)をネットワーク非依存でテキスト化する共通APIを提供する
- pub.dev上に存在しない「ファイル入力・オフライン・モデル非同梱」の空白領域を埋める
- アプリサイズを増やさない(モデル同梱型の代替: whisper.cpp / sherpa-onnx / Vosk との差別化点)

## 3. スコープ

### 対象

| プラットフォーム | バックエンドAPI | モデル管理 |
|---|---|---|
| Android | Android 標準 SpeechRecognizer(オンデバイス) | OS(Google音声サービスが保持する言語パック。`checkRecognitionSupport()` の `installedOnDeviceLanguages` 等で状態照会する。ML Kit GenAI Speech Recognitionは不採用とした。理由: 同APIはAICoreの実体を伴う搭載をGoogleが個別に対応端末と認めている必要があり、API 37・ブートローダーロック済みのPixel 6実機でもAICoreがstub版のためGoogle Playストアが「対応しなくなりました」と明示し動作しないことを確認済みである一方、標準SpeechRecognizerは同じPixel 6実機でja-JPのファイル文字起こしに成功した(キーワード包含率66.7%、Darwin/Webと同水準)。spikes/android/RESULTS.md 参照) |
| iOS / macOS | SpeechAnalyzer | OS (AssetInventory) |
| Windows | Windows AI APIs Speech Recognition | OS (NPUプリインストール / Windows Update) |
| Web | Chrome オンデバイスWeb Speech (processLocally) | Chrome (言語パック約60MB。ja-JP言語パックの取得はChrome 153で実機確認済み) |

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
  - Android: `SpeechRecognizer.checkRecognitionSupport()` が返す `RecognitionSupport` の `supportedOnDeviceLanguages` / `installedOnDeviceLanguages` / `pendingOnDeviceLanguages` / `onlineLanguages` の4リストを突き合わせて4値へ写像する(ML Kit GenAI Speech Recognitionの `checkStatus()` は不採用。spikes/android/RESULTS.md 参照)。写像方針: 対象ロケールが `installedOnDeviceLanguages` に含まれれば `available`、`pendingOnDeviceLanguages` に含まれれば `downloading`、いずれにも含まれないが `supportedOnDeviceLanguages` に含まれれば `downloadable`、いずれにも含まれなければ `unavailable`。Pixel 6実機での実測では `isRecognitionAvailable() = true`・`isOnDeviceRecognitionAvailable() = true`・`supportedOnDeviceLanguages`(36件)にja-JPを含み、ML Kit GenAI Speech Recognitionの `checkStatus()` が `PERMISSION_DENIED` を返した状況とは対照的に正常応答した(spikes/android/RESULTS.md 参照)
  - Windows: `GetReadyState()` の AIFeatureReadyState(実際の値は `Ready` / `NotReady` / `NotSupportedOnCurrentSystem` / `DisabledByUser` / `CapabilityMissing` / `NotCompatibleWithSystemHardware` / `OSUpdateNeeded` の7値であり、このうち `downloading` に一意対応する状態が無いことをドキュメント調査で確認した。spikes/windows/RESULTS.md 参照)
  - Web: `SpeechRecognition.available()` の AvailabilityStatus
  - iOS/macOS: AssetInventory の照会結果(`AssetInventory.status` の `.installed` は予約(reserve)状態に連動する一時状態であり、ディスク上の永続状態を表す `installedLocales` とは別軸であることをmacOS実機で確認済み。この挙動はiOS実機でも再現し、macOS固有の挙動ではなくSpeechAnalyzer APIの仕様であることを確認済み。4値への写像には両方の突き合わせが必要。spikes/darwin/RESULTS.md 参照)

### FR-2 モデルダウンロード

- `downloadModel(locale)` でOS管理のモデル取得をトリガーし、進捗をStreamで返す
- ダウンロードはユーザー同意後に呼び出す前提とし、同意UIはライブラリ利用者(アプリ側)の責務とする(Windows AI推奨UXパターンに準拠)
- Windowsは進捗APIの粒度が異なるため、進捗が取得できない場合は不定進捗として通知
- Webの `install()` は進捗イベントを提供せず `Promise<boolean>` のみを返すため(Chrome 153で実機確認済み、spikes/web/RESULTS.md 参照)、Windowsと同様に不定進捗として扱う
- Androidは `SpeechRecognizer.triggerModelDownload(intent, executor, ModelDownloadListener)` でOS管理の言語パック取得をトリガーする。**`ModelDownloadListener` の `onScheduled`/`onProgress`/`onSuccess`/`onError` はダウンロード完了時に発火しない実測がある**(Pixel 6実機でja-JP言語パックを取得した際、`onScheduled()` のみ発火し、以降60秒以内に他のコールバックが一切到達しなかった。しかし直後に再照会すると実際にはダウンロードが完了していた)。そのため完了判定はコールバックに依らず、`checkRecognitionSupport()` を再照会し `installedOnDeviceLanguages` に対象ロケールが現れたかで行う(spikes/android/RESULTS.md 参照)

### FR-3 ファイル文字起こし

- `transcribeFile(path, locale)` で音声ファイルを文字起こしし、`Stream<TranscriptSegment>` を返す
- partial結果を許容する(isFinalフラグで区別)。Windowsバッチ認識はfinalのみ1回emit
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
  - Windows: `BatchRecognition.RecognizeFromFile(path)` にパスを直接渡す。対応フォーマットは要検証、必要時はMedia Foundationでwav変換
  - Web: `AudioContext.decodeAudioData` → MediaStreamAudioDestinationNode → `start(audioTrack)`
- デコード不能なファイルは明確なエラー型で通知

### FR-5 ロケール指定

- BCP-47形式でロケールを指定
- 対応ロケールはプラットフォーム・モードごとに異なるため、静的リストを持たず `checkModel(locale)` による実行時解決とする
- 日本語(ja-JP)は全プラットフォームで動作検証を必須とする(検証済み事項: Android Basic = ja-JP beta、Android Advanced = ja-JP 高精度リスト掲載、Chrome オンデバイス = ja-JP対応。Chrome 153で `available()` が `downloadable`、`install()` 後に `available` へ遷移することを実機確認済み(spikes/web/RESULTS.md 参照)。iOS SpeechAnalyzer の日本語対応は実機検証で確認する。Windows AI の日本語対応は**未検証**である(Windows機が無く、ロケール指定APIも存在しないため。spikes/windows/RESULTS.md 参照)。うちmacOS 26.5.1実機では `SpeechTranscriber.supportedLocales`(30件)に `ja-JP` が含まれることを確認済み。iOS 27.0実機(iPhone 17)でも `SpeechTranscriber.supportedLocales`(45件)に `ja-JP` が含まれることを確認済み。macOS 26.5.1の30件とiOS 27.0の45件は一致しておらず、この実測が本節冒頭の「静的リストを持たず `checkModel(locale)` による実行時解決とする」という設計判断を裏付けている(spikes/darwin/RESULTS.md 参照)

### FR-6 エラーモデル

- 共通エラー型: `modelUnavailable` / `localeUnsupported` / `decodeFailed` / `deviceUnsupported` / `cancelled` / `platformError(原因)`
- Android固有: `android.speech.SpeechRecognizer` の `RecognitionListener.onError(error: Int)` が返す `ERROR_*` 定数(`ERROR_AUDIO` / `ERROR_CLIENT` / `ERROR_INSUFFICIENT_PERMISSIONS` / `ERROR_NETWORK` / `ERROR_NETWORK_TIMEOUT` / `ERROR_NO_MATCH` / `ERROR_RECOGNIZER_BUSY` / `ERROR_SERVER` / `ERROR_SERVER_DISCONNECTED` / `ERROR_SPEECH_TIMEOUT` / `ERROR_TOO_MANY_REQUESTS` / `ERROR_LANGUAGE_NOT_SUPPORTED` / `ERROR_LANGUAGE_UNAVAILABLE` / `ERROR_CANNOT_CHECK_SUPPORT` / `ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS`)を共通エラー型へ写像する基盤とする(design.md §5 参照)。**ML Kit GenAI Speech Recognitionは不採用としたため、同APIに固有だった「ブートローダーアンロック端末では動作しない」旨のエラーや、AICoreがstub版の場合の `PERMISSION_DENIED: Api access revoked.` といった記述は、採用しなかったバックエンドに関する記録としてspikes/android/RESULTS.md にのみ残し、本節のエラーモデルからは対象外とする**

## 5. 非機能要件

### NFR-1 処理時間

- 所要時間はプラットフォーム依存であることをAPI契約に明記
- Android(実時間レート供給制約)とWeb(リアルタイム処理)はファイル長と同等の時間がかかる。Webについては、Chrome 153実機で9.56秒の基準音声(jaJP_10s)の文字起こしに9,676msを要し、Webが実時間処理であることが実測で裏付けられた(spikes/web/RESULTS.md 参照)
- Webは再生速度オプション(`playbackRate`、§7参照)により、この実時間制約を緩和できる。1.0より大きい値を指定すると所要時間は短縮される(jaJP_10s実測: 1.0xで9,676ms、2.0xで4,867ms)。ただし処理時間の短縮と認識精度はトレードオフの関係にあり、`AudioBufferSourceNode.playbackRate` はピッチも同倍率で変化させるため、速度を上げるほど精度が低下しうる(1.0x: 66.7% → 1.5x: 50.0% → 2.0x: 33.3%、jaJP_10s実測。spikes/web/RESULTS.md 参照)
- Windowsバッチは非実時間。macOS 26.5.1実機では RTF(処理時間 ÷ 実時間長)0.008〜0.026、すなわち実時間の約38〜125倍高速にファイル入力の文字起こしが完了することを実測済み(spikes/darwin/RESULTS.md 参照)。Android/Webの実時間制約とは対照的に高速である。iOSのファイル処理速度は実機未測定であり、引き続き要実測

### NFR-2 プライバシー

- 音声・書き起こし結果を一切ネットワーク送信しない。Webは `processLocally = true` を強制し、サーバー認識へのサイレントフォールバックを禁止する

### NFR-3 パッケージサイズ

- ライブラリ本体にモデル・推論バイナリを含めない。各パッケージはブリッジコードのみ

### NFR-4 最低動作環境

- Android 12 (API 31) 以上
- iOS 26 以上 / macOS 26 以上
- Windows 11 24H2 (build 26100) 以上、WinAppSDK 1.7.1以上(**M4実装時に再確認して確定**: 公式ドキュメント https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition の Prerequisites に「Windows 11, version 24H2 (build 26100) or later」「WinAppSDK version: Version 1.7.1 or later」と明記されている。M0調査時点ではAPIリファレンスが `windows-app-sdk-2.0-experimental` モニカーにしか無く本記述との齟齬を疑っていたが、本記述が正しかった。design.md §4.4 参照)
- Chrome 142 以上(オンデバイスWeb Speechのリグレッション修正済みバージョン)

### NFR-5 バージョニング

- 土台のAPIが新しく、Windows AI APIs は Experimental 段階であり、iOS/macOSのSpeechAnalyzerもOS 26で導入されたばかりである。また各OSのオンデバイス認識の挙動には実測で判明した未確定要素が残る(design.md §8)。そのためライブラリは0.x系で公開し、各OS APIのstable化までstableを名乗らない

## 6. パッケージ構成(federated plugin)

- `<name>_platform_interface`: 共通抽象、TranscriptSegment、エラー型
- `<name>_android`: Kotlin実装(標準 SpeechRecognizer + MediaCodecポンプ)
- `<name>_darwin`: Swift実装(iOS/macOS共用、SpeechAnalyzer + AVFoundation)
- `<name>_windows`: C++/WinRT実装(Windows AI + 必要ならMedia Foundation)
- `<name>_web`: Dart JS interop実装(Web Speech + Web Audio)
- `<name>`: エントリパッケージ(利用者が依存するのはこれのみ)

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
- `playbackRate`(既定値 1.0)は再生速度を指定するオプションである。意味を持つのはWebのみで、`AudioBufferSourceNode.playbackRate` に直結する。Darwin(SpeechAnalyzer)・Windows(BatchRecognition)はバッチ処理であり速度という概念自体が存在しないため、指定しても無視される(値そのものは受理するが動作に影響しない)。Androidは実時間ポンプ方式のため理論上は同種の適用余地があるが、M0時点では未検証である

## 8. 利用者(アプリ側)に課される制約(ドキュメント必須事項)

- Windows: MSIXパッケージ化 + `Package.appxmanifest` に `systemAIModels` capability宣言、`MaxVersionTested` を 10.0.26226.0 以降に設定
- Android: AICore初期化直後(端末セットアップ直後・AICoreリセット直後)はエラーになり得るため、`checkModel()` を必ず先に呼ぶUX
- モデルダウンロード同意ダイアログの実装(文言ガイドライン: モデル名ではなく「音声認識モデル」等の一般名称)
- Web: ファイル選択はユーザー操作起点(File / Blob)。Chrome以外のブラウザでは `unavailable` を返す

## 9. リスク

| リスク | 影響 | 対策 |
|---|---|---|
| ML Kit GenAI (alpha) の破壊的変更 | **該当しなくなった。** Androidバックエンドを標準 `android.speech.SpeechRecognizer` へ差し替えたため、ML Kit GenAI への依存自体が無くなった(spikes/android/RESULTS.md 参照) | — |
| Chrome オンデバイスWeb Speechの不安定さ(過去に一時無効化の実績) | Web実装が突然動かなくなる | `available()` を毎回確認、機能検出ベースで劣化 |
| iOS SpeechAnalyzer / Windows AI の日本語対応が未確認 | 主要ユースケース不成立 | 実装前に4プラットフォームでja-JP実機検証(マイルストーン0)。macOS 26.5.1実機・iOS 27.0実機の双方で`supportedLocales`にja-JPを含むことを確認済み(spikes/darwin/RESULTS.md 参照)。残課題: (a)iOS 26実機での確認(supportedLocalesはOSバージョンで異なるため外挿不可)、(b)iOS実機でのファイル文字起こし検証(記録済みの結果はmacOSのもの)、(c)Windows実機での検証全般(ロケール指定APIが存在しないことはドキュメント調査で確定済みだが、ja-JP書き起こしの可否自体は未検証。spikes/windows/RESULTS.md 参照) |
| `continuous = true` では `source.onended` 後に明示的に `recognition.stop()` を呼ばないと `onend` が発火せず、セッションが終了しない(終了検出の実装漏れ) | Web実装がアプリ側の実装ミスで無応答になる(transcribeFile()のStreamが完了しない) | design.md §4.1 に必須手順として明記済み。Chrome 153実機で `onended` 内の `stop()` 呼び出しにより `isFinal` 結果と `onend` が発火することを確認済み(spikes/web/RESULTS.md 参照) |
| `onResults()` が `null` になり確定結果が partial 側にしか来ない | Android実装が確定テキストを取得できない | Pixel 6実機で実測済み。末尾 `onPartialResults()` の最上位候補を確定結果として採用する(design.md §4.3)。この挙動が全端末共通かはdesign.md §8 未決事項8としてM3で確認する |
| 最低OSバージョンが高くユーザー母数が限られる | **ML Kit GenAI Speech Recognitionを採用しないことで、当初懸念していた「Googleが個別に対応と認めたAICore搭載ハードウェアでしか動かない」というリスクは大幅に低減した。** 差し替え後の標準 `android.speech.SpeechRecognizer` は、API 37・ブートローダーロック済みのPixel 6実機(ML Kit GenAI Speech Recognitionでは `checkStatus()` が `PERMISSION_DENIED: Api access revoked.` を返し動作しなかった端末)で、ja-JPのオンデバイス言語パック取得・ファイル入力受理・文字起こしのいずれも実測で成功した(spikes/android/RESULTS.md 参照)。ただし**この実測はPixel 6単一機種によるものであり、他機種・他OEMでの動作は未検証のまま残る** | READMEには「APIレベルの要件(NFR-4のAndroid 12/API 31以上)を満たしていても、`checkRecognitionSupport()` の結果は機種・言語パック導入状況によって異なりうる」旨を明記する。M3実装時にPixel 6以外の複数機種で追加検証を行い、対応機種の線引きを確定させる(spikes/android/RESULTS.md 参照) |

## 10. マイルストーン

- M0 検証: 4プラットフォームで ja-JP のファイル文字起こしをスパイク実装で確認(特に iOS / Windows の日本語、Webの組み合わせ動作)。不成立のプラットフォームがあれば構成を再検討
- M1 Web実装: 純Dartで最速検証。デコード層とモデル管理UXのAPI形状をここで固める
- M2 iOS/macOS実装(darwin統合)
- M3 Android実装(MediaCodecポンプ含む)
- M4 Windows実装 + MSIXセットアップドキュメント
- M5 pub.dev公開(0.1.0)、example app、対応状況マトリクスのREADME整備
