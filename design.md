# design.md

Flutterライブラリ「オフライン音声ファイル文字起こし」技術設計

対応する要件: requirements.md v1

## 1. アーキテクチャ全体像

```
アプリ
 └── <name>(エントリパッケージ)
      └── <name>_platform_interface(共通抽象)
           ├── <name>_android   … Pigeon → Kotlin(標準 SpeechRecognizer + MediaCodecポンプ)
           ├── <name>_darwin    … Pigeon → Swift(SpeechAnalyzer + AVFoundation)
           ├── <name>_windows   … Pigeon → C++/WinRT(Windows AI + Media Foundation)
           └── <name>_web       … Dart JS interop(Web Speech + Web Audio)
```

- レイヤは3層: 共通API層(Dart) / ブリッジ層(Pigeon生成コード) / ネイティブ実装層
- ネイティブ実装層は「デコード」「モデル管理」「認識セッション」の3モジュールに分割し、全プラットフォームで同じモジュール境界を維持する

## 2. パッケージ間契約

### 2.1 platform_interface

```dart
abstract class OfflineTranscriberPlatform extends PlatformInterface {
  Future<ModelState> checkModel(String locale);
  Stream<DownloadProgress> downloadModel(String locale);
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request);
}
```

- `PlatformInterface`(plugin_platform_interface)でtoken検証を行う標準構成
- 各実装パッケージは `registerWith()` でデフォルトインスタンスを差し替える

### 2.2 データ型

```dart
enum ModelState { available, downloadable, downloading, unavailable }

class DownloadProgress {
  final double? fraction;   // null = 不定進捗(Windows想定)
  final bool completed;
}

class TranscribeRequest {
  final String path;        // Webでは Blob URL / ObjectURL
  final String locale;      // BCP-47
  final double playbackRate; // 既定 1.0。Web専用オプション。他プラットフォームでは無視される
}

class TranscriptSegment {
  final String text;
  final bool isFinal;
}

sealed class TranscribeException implements Exception {}
class ModelUnavailableException extends TranscribeException {}
class LocaleUnsupportedException extends TranscribeException {}
class DecodeFailedException extends TranscribeException {}
class DeviceUnsupportedException extends TranscribeException {}  // ブートローダーアンロック等
class CancelledException extends TranscribeException {}
class PlatformException_ extends TranscribeException { final String code; final String? message; }
```

### 2.3 ブリッジ方式

- Android / Darwin / Windows: Pigeonでスキーマ駆動生成。手書きMethodChannelは使わない
  - 理由: 3ネイティブ言語(Kotlin / Swift / C++)への型安全な同時生成、enum・sealedのシリアライズ事故防止
- ストリームはPigeonのEventChannel対応(`@EventChannelApi`)で `segments` / `downloadProgress` の2本を定義
  - **ただしWindowsは例外**。PigeonのC++ジェネレータはEventChannelに未対応であり、`@EventChannelApi` を含むスキーマに `--cpp_header_out` を指定すると `C++ does not support event channels` で生成が失敗する(Pigeon 27.3.0 / 29.0.2 の両方で実行確認済み。Pigeon の README にも「Event channels are supported only on the Swift, Kotlin, and Dart generators.」と明記されている)
  - そのためWindowsのみ **HostApi + FlutterApi のコールバック**で同等のストリーム機能を実現する。スキーマファイルを Android/Darwin 用と Windows 用の2本に分ける。手書きMethodChannel/EventChannelは使わないという方針は維持する
- 共通エラー列挙型 `TranscribeErrorCode`(`modelUnavailable` / `localeUnsupported` / `decodeFailed` / `deviceUnsupported` / `cancelled` / `platformError`)をPigeonスキーマに定義する。§2.2 の sealed 例外階層に対応するが、C++ は sealed class を持てないため列挙型でワイヤを渡す。Android/Darwin ではEventChannelの組み込みエラーシンクを使うため、スキーマ上は定義のみとする
- 生成物(`.g.dart` / `.g.kt` / `.g.swift` / `.g.h` / `.g.cpp`)は**リポジトリにコミットする**。ネイティブビルド(Gradle / Xcode / CMake)はDart・Pigeonツールチェーンを経由せず生成済みコードを直接コンパイルするため、コミットしないとネイティブビルドが成立しない。再生成は melos スクリプト(`melos run pigeon`)で行う
- Web: Pigeon不要。`package:web` + `dart:js_interop` で直接実装
- `HostApi` はネイティブ側実装が非同期APIの完了を待って結果を返す必要があるメソッド(例: Darwinの `checkModel`、`AssetInventory`/`SpeechTranscriber` の async API に依存)には `@async` を使う。プラットフォームスレッドを `DispatchSemaphore` 等でブロックして待ち合わせる実装は禁止とする(ANR・デッドロックの危険があるため)

## 3. 状態遷移

```
[unavailable] … 端末/OS/ブラウザ非対応。終端
[downloadable] --downloadModel()--> [downloading] --完了--> [available]
                                        └--失敗--> [downloadable](エラー通知)
[available] --transcribeFile()--> セッション(idle→decoding→recognizing→done|cancelled|error)
```

- `transcribeFile()` は `checkModel()` が available 以外なら即座に `ModelUnavailableException` をStreamエラーで返す(内部で暗黙ダウンロードしない。同意UXをアプリ側に強制するため)
- 同時セッションはv1では1本に制限(プラットフォーム側の並行動作が未検証のため)。2本目の開始は `StateError`

### 状態遷移の細則

M1 の実装(`offline_stt_platform_interface`)で必要になったため、上記だけでは曖昧だった点を以下のとおり確定する。**全プラットフォーム実装はこの解釈に従うこと。** 実装が分かれると利用者から見た挙動が食い違う。

1. **セッションの開始時点と終了時点**
   - 開始は `transcribeFile()` の**呼び出し時点ではなく、返り値のStreamが購読(listen)された時点**とする。Dart の Stream は未購読なら何もしないのが自然であり、呼び出し時点で開始すると購読前に破棄した場合にセッション枠を1本消費してしまうため
   - 終了は正常終了(done) / エラー終了(error) / 購読キャンセル(cancel) のいずれかの時点とする。いずれの経路でも確実に解放すること

2. **2本目のセッションの拒否方法**
   - `StateError` は**同期的に throw せず、Streamエラーとして通知する**。`ModelUnavailableException` と流儀を揃え、「購読時点でセッション開始」という上記1と整合させるため
   - 2本目が拒否された場合、下層の認識セッションは**一切開始しない**こと

3. **`downloadModel()` の細則**
   - `downloadable` 以外の状態(特に `unavailable`)で呼ばれた場合は、**状態を一切変化させず、何も emit せずに完了するStreamを返す**
   - 状態変化(`downloadable` → `downloading`)は、`transcribeFile()` とは異なり**呼び出し時点で即座に**確定させる。ダウンロード同意UXがアプリ側で完了した後に呼ばれる前提であり、購読前の破棄を考慮する必要が薄いため。この非対称性は意図的である

4. **セッション内部フェーズ(`decoding` / `recognizing`)の扱い**
   - 上記の遷移図には現れるが、`TranscriptSegment` には現れないため**公開APIには露出しない**。各ネイティブ実装の内部状態として扱う

## 4. プラットフォーム別設計

### 4.1 Web(<name>_web)

パイプライン:

```
File/Blob → fetch/FileReader → ArrayBuffer
  → AudioContext.decodeAudioData → AudioBuffer
  → AudioBufferSourceNode → MediaStreamAudioDestinationNode
  → stream.getAudioTracks()[0]
  → SpeechRecognition.start(audioTrack)
```

- 初期化時に `SpeechRecognition.available({langs, processLocally: true})` を確認し、`downloadable` なら `install()` をFR-2のダウンロードとして扱う
- `install()` は進捗イベントを持たず `Promise<boolean>` を返す(Chrome 153で実機確認済み)。そのため `DownloadProgress(fraction: null)` の不定進捗として写像する
- `AudioContext.decodeAudioData` は入力が16kHzでも `AudioContext` の既定サンプルレートへ自動リサンプリングされる(実測環境では48kHz)
- `processLocally = true` を常時設定。設定不能・失敗時はサーバーフォールバックせずエラー終了(NFR-2)
- `continuous = true`、`interimResults = true` でpartialをTranscriptSegmentに写像
- 終了検出: sourceの `onended` 後、`recognition.onend` をもってStream close。**`onended` ハンドラ内で明示的に `recognition.stop()` を呼ぶ実装が必須である**(Chrome 153実機で確認済み)。`continuous = true` では `AudioBufferSourceNode` が再生を終えても `MediaStreamTrack` は `live` のまま無音を流し続けるため、`stop()` を呼ばない限り Chrome は入力終了を認識せず `onend` が発火しない
- `isFinal` の発火粒度(実測、Chrome 153): `isFinal = true` の結果は `stop()` 呼び出し後に1回だけ発火し、それ以前に得られる結果はすべて `isFinal = false`(interim)である。したがってWebでは、partialが認識中継続的にemitされ続け、finalは末尾に1件のみemitされる、という粒度になる。FR-3・§2.2の `TranscriptSegment.isFinal` はこの前提で扱う
- partialとfinalでテキスト形式が異なる。**確定(final)結果は形態素単位で空白区切りされる**(例: `東京 都 渋谷 で 2024 年 ...`)ことをChrome 153実機で確認済み。partial結果には空白が入らない。アプリへ返す前にこの空白を除去するかどうか、実装時にテキスト整形の方針を決める必要がある
- 再生速度オプション(`TranscribeRequest.playbackRate`、§2.2参照)は `AudioBufferSourceNode.playbackRate` にそのまま渡して実装する。**制約として、ピッチも同倍率で変化する**(Web Audio にピッチ保持のタイムストレッチは無い)。Chrome 153実機での jaJP_10s(音声長9.56秒、期待キーワード6件)実測は以下のとおりである

  | 再生速度 | 所要時間 | 包含率 | isFinal発火 |
  |---|---|---|---|
  | 1.0x | 9,676 ms | 4/6 = 66.7% | あり |
  | 1.1x | 8,808 ms | 4/6 = 66.7% | なし(interim採用) |
  | 1.25x | 7,726 ms | 4/6 = 66.7% | なし(interim採用) |
  | 1.5x | 6,464 ms | 3/6 = 50.0% | あり |
  | 1.75x | (未実施) | (未実施) | (未実施) |
  | 2.0x | 4,867 ms | 2/6 = 33.3% | あり |

  1.1x・1.25xでは `isFinal = true` の結果が発火しない事例が観測されており、その場合は末尾のinterim結果を実質的な確定結果として採用する実装上の対応が必要になる(前掲の「isFinalの発火粒度」の記述はあくまで1.0x等での実測であり、速度によって発火有無が変わりうる点に注意)。また「株式会社モーンギフト」の認識結果は 1.0x「ムーンギフト」→ 1.1x「モヨンギフト」→ 1.25x「オンギフト」→ 1.5x「モンギフト」→ 2.0x(消失)と推移しており、包含率が同じ1.0〜1.25xの間でもテキストの劣化は進行している。**限界**: この測定は jaJP_10s(期待キーワード6件)のみであり、キーワード1件の増減で包含率が16.7ポイント動く粗い分解能でしかない。他クリップでの追加測定はM0スコープ外であり未実施である。再生速度の実装上の上限値を設けるか、また精度低下を利用者へどう提示するかはM1で決める(§8参照)
- 言語パック未取得のまま `start()` を呼ぶと、ロケールによって異なるエラーが返る(ja-JP: `aborted`、en-US: `language-not-supported`)ことをChrome 153実機で確認済み。原因が分かりにくいエラーになるため、本節冒頭の `SpeechRecognition.available()` による事前確認(§3参照)が必須である
- Chrome以外・非対応環境は `checkModel()` が `unavailable` を返す

### 4.2 Darwin(<name>_darwin、iOS/macOS共用)

パイプライン:

```
AVAudioFile(任意フォーマット読込)
  → AnalyzerInput へ変換
  → SpeechAnalyzer + SpeechTranscriber(locale指定)
  → AsyncSequence の結果を EventChannel へ転送
```

- モデル管理: AssetInventoryでlocaleのアセット状態を照会・取得要求。FR-1/FR-2に写像
- OSバージョンゲート: iOS 26 / macOS 26 未満は `checkModel()` で `unavailable`(コンパイルは下位OSでも通す。`if #available` で分岐)
- 1パッケージでiOS/macOS両対応(sharedなSwiftソースを `darwin/` 配下に置くFlutter標準構成)
- ファイル入力時の処理速度: macOS 26.5.1実機でRTF(処理時間 ÷ 実時間長)0.008〜0.026を実測済み、すなわち実時間の約38〜125倍高速(ja-JP/en-US × 10秒/3分 × wav/m4aの全8ファイル、spikes/darwin/RESULTS.md 参照)。結果をREADMEの所要時間表に反映する
- `SpeechTranscriber.Preset` の選定は精度に大きく影響する(実測ではプリセット違いで包含率が最大20ポイント以上変動)ため、実装時に選定基準を定める必要がある。partial(volatile)結果を得るには `.progressiveTranscription` 系のプリセットが必要である(spikes/darwin/RESULTS.md 参照)
- `AssetInventory.status(forModules:)` の `.installed` は当該ロケールが現在「予約(reserve)」されているかに連動する一時状態であり、ディスク上のアセット存在を表す永続状態(`installedLocales`)とは別軸である。FR-1の4値への写像を実装する際は `installedLocales` との突き合わせが必要である(spikes/darwin/RESULTS.md 参照)
- `supportedLocales` はプラットフォーム・OSバージョンによって件数・内容が異なる(macOS 26.5.1: 30件、iOS 27.0: 45件)ことを実機で確認済みである。そのため静的リストを持たず、実行時に照会して解決する(spikes/darwin/RESULTS.md 参照)
- iOSシミュレータでは `SpeechTranscriber.isAvailable` が `false` となり、SpeechAnalyzerによる認識自体が利用できないことを確認済みである。認識のE2E検証には実機が必須である(spikes/darwin/RESULTS.md 参照)
- `AssetInventory.status(forModules:)` の `.installed` が予約状態に連動する上記の挙動は、iOS実機でも再現することを確認済みである。macOS固有の挙動ではなく、SpeechAnalyzer APIの仕様であることが確定した(spikes/darwin/RESULTS.md 参照)

### 4.3 Android(<name>_android)

**バックエンド差し替えの経緯**: 当初はML Kit GenAI Speech Recognitionを想定していたが、実体のあるAICoreをGoogleが個別に対応と認めた端末でしか動作せず、API 37・ブートローダーロック済みのPixel 6実機でもAICoreがstub版でGoogle Playストアが「対応しなくなりました」と明示し動作しなかった。そこでAndroid標準の `android.speech.SpeechRecognizer` へ差し替えた。詳細な経緯・実測はspikes/android/RESULTS.md の「代替案の検証: Android 標準 SpeechRecognizer」節を参照。

パイプライン:

```
入力ファイル
  → MediaExtractor + MediaCodec でデコード(チャンク単位)
  → リサンプリング(16kHz・モノラル・16-bit PCM、チャンク単位)
  → ParcelFileDescriptor.createPipe()
  → 書き込み側: 実時間ポンプ(毎秒約32KB、コルーチンで供給)
  → Intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, 読み取り側)
  → SpeechRecognizer.createOnDeviceSpeechRecognizer() の startListening() → RecognitionListener
  → EventChannel へ転送
```

- 認識セッションの生成: `SpeechRecognizer.createOnDeviceSpeechRecognizer(context)` でオンデバイス専用インスタンスを生成する。`Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)` に `EXTRA_LANGUAGE`(ロケール)と `EXTRA_PREFER_OFFLINE = true`(NFR-2のオフライン方針)を設定し、`startListening(intent)` を呼ぶ。ML Kit固有だった `MODE_ADVANCED` / `MODE_BASIC` のようなモードの概念は本APIには無く、代わりに「オンデバイス(`createOnDeviceSpeechRecognizer` + `EXTRA_PREFER_OFFLINE`)」と「オンライン」の区別のみが存在する
- ファイル入力: `RecognizerIntent.EXTRA_AUDIO_SOURCE` に読み取り側の `ParcelFileDescriptor` を設定する。併せて `EXTRA_AUDIO_SOURCE_CHANNEL_COUNT`(=1)・`EXTRA_AUDIO_SOURCE_ENCODING`(=`AudioFormat.ENCODING_PCM_16BIT`)・`EXTRA_AUDIO_SOURCE_SAMPLING_RATE`(=16000)の3つのExtraを必ず併せて渡す必要がある(Pixel 6実機で受理を確認済み。spikes/android/RESULTS.md 参照)
- **`RECORD_AUDIO` 権限は不要である。** Pixel 6実機での検証では同権限を一切付与せずに実行したが、`ERROR_INSUFFICIENT_PERMISSIONS` は発生せず、`onReadyForSpeech` → `onBeginningOfSpeech` → `onPartialResults`(日本語の逐次認識結果)と正常に進行した。これは音声がマイクではなくPFD経由で供給されていることの直接証拠である(spikes/android/RESULTS.md 参照)
- 実時間ポンプ設計:
  - 供給レートは壁時計基準(累積送信サンプル数と経過時間の差分でsleep調整)。バッファ単位100ms(16kHz・モノラル・16-bit PCMでは1,600サンプル=3,200バイト。1サンプル=2バイトである点に注意)
  - **既存の実時間ポンプ設計はバックエンド差し替え後もそのまま使える(実測で確認済み)。** Pixel 6実機でjaJP_10s(305,988バイト)を供給したところ `sentBytes=305988/305988, elapsedMs=9564, 実効レート=31993.7バイト/秒` となり、目標値(毎秒約32,000バイト)とほぼ一致した(spikes/android/RESULTS.md 参照)
  - キャンセル時はパイプclose → `stopListening()`(または `cancel()`)→ `destroy()`。ただしキャンセル経路そのものはM0スパイクの検証範囲外であり未検証である(spikes/android/RESULTS.md「限界」参照)
- **`onResults()` の確定結果(`RESULTS_RECOGNITION`)が `null` になり、確定テキストが得られない。** Pixel 6実機での2回の独立実行いずれでも再現した。ログの時系列上、`onResults` は**パイプ(書き込み側)を閉じた直後、`stopListening()` を呼ぶ*前*に発火している**。すなわち入力終了は `stopListening()` ではなくパイプのcloseによって検出されており、`stopListening()` の有無に関わらずこの挙動が生じる。なお `onResults` の後に遅れて `stopListening()` を呼ぶと `ERROR_CLIENT`(5)が誘発されるだけであった(実測)。一方で完全なテキストは `onPartialResults()` 側に逐次emitされ、最長のpartial(例: 「東京都渋谷で2024年11月3日午後3時株式会社モンギフトが新製品を発表しました来場者は128名でした」)が実質的な文字起こし結果になっていた。**そのため本実装では、`onResults()` のtexts が null の場合は直前の `onPartialResults()` の最上位候補を確定結果として採用する**(Webで `isFinal` が立たない場合に末尾interimを採用したのと同じ構図。spikes/android/RESULTS.md 参照)。原因(オンデバイスエンジン側の挙動か `EXTRA_AUDIO_SOURCE` 経由特有の終端処理かなど)は特定できておらず、M3実装時に追加調査が必要である
- リサンプリング: **必須(M0スパイクで実測確定。この結論はバックエンド差し替えの影響を受けない)**。MediaCodecはコーデックのデコードのみを行い、サンプルレート変換・チャンネルのダウンミックスは一切行わないことを実測で確認した。実環境相当の音源7ファイル(44.1kHz/48kHzステレオのwav・m4a・mp3、22.05kHzモノラル、8kHzモノラル)全てで出力`MediaFormat`のサンプルレート・チャンネル数が入力側と完全に一致し、16kHz・モノラルへの変換は起きなかった(resampleNeeded=true、7/7。spikes/android/RESULTS.md 参照)。よって線形補間ではなくAudioResampler相当のサンプルレート変換 + ステレオ→モノラルのダウンミックス処理をM3で実装する。MediaCodecのこの挙動は認識バックエンドとは無関係なAndroidフレームワークAPI(`MediaExtractor`/`MediaCodec`)の仕様であるため、ML Kit GenAI Speech Recognitionから標準SpeechRecognizerへの差し替えによってこの結論が変わることはない。なお本結果はエミュレータ単一環境での実測であり、実機での追試が引き続き望ましい
- モデル管理・状態確認: `SpeechRecognizer.checkRecognitionSupport(intent, executor, RecognitionSupportCallback)` が返す `RecognitionSupport` の `supportedOnDeviceLanguages` / `installedOnDeviceLanguages` / `pendingOnDeviceLanguages` / `onlineLanguages` を突き合わせてFR-1の4値へ写像する(写像方針の詳細はrequirements.md FR-1参照)。モデル取得は `SpeechRecognizer.triggerModelDownload(intent, executor, ModelDownloadListener)` を用いるが、**`ModelDownloadListener` のコールバックはダウンロード完了時に発火しない実測がある**(Pixel 6実機でja-JP言語パック取得を試みた際、`onScheduled()` のみ発火し以降60秒間他のコールバックが到達しなかったが、実際にはダウンロードは完了していた)。そのため完了判定はコールバックではなく `checkRecognitionSupport()` の再照会(`installedOnDeviceLanguages`)で行う(spikes/android/RESULTS.md 参照)
- **API 31/32 は `unavailable` に倒す。** `checkRecognitionSupport()` は API 33(TIRAMISU)で追加されたAPIであり、API 31/32 では4リストを取得する手段がそもそも無い。Darwin が OS 26 未満で `unavailable` を返すのと同じOSバージョンゲートである(§4.2 と揃えている)
- **デコード・リサンプリング・送出はチャンク単位でストリーミング処理する。** 全量を配列に materialize すると、48kHz・ステレオ・16-bit・60分の入力でピーク約1.73 GB に達して OOM になる。ストリーミングにより、同時に生存するバッファは音声長に依存しなくなる
- リサンプリングの実装は、全チャンネルの単純平均によるモノラル化と線形補間による 16kHz への変換の2段構成とする。線形補間はローパスフィルタを持たないためダウンサンプリング時のエイリアシングを理論上抑制できない。これは意図的な設計判断であり、将来 windowed-sinc 等へ置き換える余地がある
- エラー写像は `SpeechRecognizer.ERROR_*` 定数に対して行う(§5 参照)

### 4.4 Windows(<name>_windows)

パイプライン:

```
入力ファイル
  → (必要時) Media Foundation で wav へ変換
  → SpeechRecognitionModel.TryCreateAsync()
  → BatchRecognition.RecognizeFromFile(path)
  → 最終テキスト1件を isFinal=true でemit → close
```

- モデル管理: `GetReadyState()` → FR-1、`EnsureReadyAsync()` → FR-2。進捗APIの粒度が粗い場合は `DownloadProgress(fraction: null)` の不定進捗
- `AIFeatureReadyState` の実際の値は7つである: `Ready` / `NotReady` / `NotSupportedOnCurrentSystem` / `DisabledByUser` / `CapabilityMissing` / `NotCompatibleWithSystemHardware` / `OSUpdateNeeded`(うち `CapabilityMissing` / `NotCompatibleWithSystemHardware` / `OSUpdateNeeded` の3つはWinAppSDK 2.0以降の値。ドキュメント調査で確認済み。spikes/windows/RESULTS.md 参照)。FR-1の4値(available/downloadable/downloading/unavailable)への写像には課題がある: **`downloading` に一意対応する状態が存在しない**。`NotReady` はダウンロード開始前の状態であり、ダウンロード中であることを知るには `EnsureReadyAsync()` 実行中に `SpeechRecognitionModelProgress.Status`(`Installing`/`Caching`/`Loading`等)の進捗イベントを観測する必要がある
- `RecognizeFromFile(String)` はファイルパス文字列を直接渡す(StorageFileではない)。対応入力フォーマットはドキュメントに記載が無く、実機での確認が必須である(未確定。spikes/windows/RESULTS.md 参照)。wav以外が通らなければMedia Foundation変換層を必須化。なお `BatchRecognition` には `Recognize(Byte[])` という別オーバーロードも存在する(バイト列の期待フォーマットは未確認)
- 言語指定APIの有無: **確定**。`Microsoft.Windows.AI.Speech` 名前空間にロケール・言語を指定するAPIは存在しないことをドキュメント調査で確認した(spikes/windows/RESULTS.md 参照)。指定不能であるため、OS言語依存としてREADMEに明記する方針が確定した前提となる。ja-JPで実際に高精度認識されるかは実機未検証のまま残る
- WinAppSDKのバージョン前提は**M4実装時に解消した**: M0調査時点では `Microsoft.Windows.AI.Speech` のAPIリファレンスが `windows-app-sdk-2.0-experimental` モニカーでのみ存在し、requirements.md NFR-4の「WinAppSDK 1.7.1以上」と齟齬があった。M4実装時(2026-09)に公式ドキュメント https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition (最終更新 2026-07-07、モニカー指定なしの本線ドキュメント)を再確認したところ、Prerequisitesに「**WinAppSDK version: Version 1.7.1 or later**」「Windows 11, version 24H2 (build 26100) or later」と明記されており、**NFR-4の記述が正しい**ことが確認できた。APIはexperimentalチャンネル限定ではなくなっている。NuGetで「1.7.1」に相当するのは `Microsoft.WindowsAppSDK` の `1.7.250401001` である。**ただし実装側にバージョンを書く場所は現在存在しない。** M4 実装時に `VS_PACKAGE_REFERENCES` で NuGet を参照する方式が CI で失敗したため、winapp CLI(`winapp init`)がアプリ側に展開する `.winapp/include` を自動検出する方式へ切り替えた結果、実際に使われるバージョンは `winapp init` が展開したものに決まる。プラグイン側は下限を機械的に強制していない(`docs/VERSION_POLICY.md` 1.4節)
- 同ドキュメントで新たに確認できた事項: MSIXマニフェストの `MaxVersionTested` を `10.0.26226.0` 以降にしておく必要がある(古い値のままだと「Not declared by app」エラーになる)。またバッチ認識のサンプルコードは `RecognizeFromFile("path/to/audio.wav")` とwavを渡しており、**wav以外の受理可否は依然としてドキュメントに記載が無い**(設計未決事項1は未解決のまま)
- 同ドキュメントの「Recommended UX pattern」は `GetReadyState()` の分岐として `Ready` / `NotReady` または `EnsureNeeded` / `NotSupportedOnCurrentSystem` を挙げている。`EnsureNeeded` は本設計書§5の注記が「実際のenumには存在しない」と記録した名称であり、**ドキュメント間で不一致がある**。実装(`model_availability.cpp`)は全バージョンに存在する値のみを明示列挙し残りを `default` で `unavailable` に倒すため、この不一致があっても壊れない。確定はIssue #58の実機検証に委ねる
- C++/WinRT実装。**WinAppSDK 1.7.1+ は「アプリ側が満たすべき互換性要件」であり、プラグインがバージョンを宣言・検証するわけではない。** `windows/CMakeLists.txt` は `winrt/Microsoft.Windows.AI.Speech.h` の有無だけを見ており、バージョンは検証しない(`OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR` で任意の配置も指定できる)。MSIX + `systemAIModels` も同様にアプリ側要件であり、いずれもREADMEに記載する

## 5. エラーマッピング表

| 共通例外 | Android | Darwin | Windows | Web |
|---|---|---|---|---|
| ModelUnavailable | `supportedOnDeviceLanguages` にのみ含まれる / いずれのリストにも無い | アセット取得不可 | NotReady / EnsureNeeded で未同意 | available() = unavailable |
| LocaleUnsupported | `ERROR_LANGUAGE_NOT_SUPPORTED` / `ERROR_LANGUAGE_UNAVAILABLE` | supportedLocales外 | (M0確認後に確定) | language-not-supported |
| DecodeFailed | MediaCodecエラー | AVAudioFileエラー | Media Foundation失敗 | decodeAudioData reject |
| DeviceUnsupported | `ERROR_CANNOT_CHECK_SUPPORT`(API 31/32 は `checkModel()` が `unavailable` を返すためこの例外にはならない) | OS 26未満 | NotSupportedOnCurrentSystem | 非Chrome系 |
| Cancelled | コルーチンcancel → パイプclose | Task cancel | 認識中断 | stop/abort |

- 注記: Android列は ML Kit GenAI(AICore)前提から `android.speech.SpeechRecognizer` 前提へ書き換えたものである(§4.3 の冒頭参照)。**`ERROR_*` 定数の対応表は暫定である。** 上記3つのみ個別に分類し、残りは `PlatformError` へ倒している。実機で実際に発火させた確認は行っていないため、Issue #50 の実機E2Eで確定させる必要がある。
- 注記: Darwin列のうち DecodeFailed(AVAudioFileエラー)と LocaleUnsupported(supportedLocales外)は、macOS 26.5.1実機でエラーを実発火させ動作を確認済みである(spikes/darwin/RESULTS.md 参照)。
- 注記(採用しなかったバックエンドに関する記録): Android列が言及していた「AICore 606」のような数値エラーコードは、ML Kit GenAI Speech Recognitionの `GenAiException.ErrorCode`(`genai-common:1.0.0-beta3` をjavapで確認)の実際の定数一覧には含まれていなかった。同ライブラリが公開する定数は UNKNOWN / REQUEST_PROCESSING_ERROR / CANCELLED / NOT_AVAILABLE / BUSY / RESPONSE_PROCESSING_ERROR / REQUEST_TOO_LARGE / REQUEST_TOO_SMALL / RESPONSE_GENERATION_ERROR / PER_APP_BATTERY_USE_QUOTA_EXCEEDED / BACKGROUND_USE_BLOCKED / NOT_ENOUGH_DISK_SPACE / NEEDS_SYSTEM_UPDATE / AICORE_INCOMPATIBLE / INVALID_INPUT_IMAGE / CACHE_PROCESSING_ERROR であった(spikes/android/RESULTS.md 参照)。ML Kit GenAI Speech Recognitionを不採用としたため、この対応付けはもはや必要ない。
- 注記(採用しなかったバックエンドに関する記録): Pixel 6実機(API 37、ブートローダーロック済み)でのML Kit GenAI Speech Recognitionの実測では、`checkStatus()`/`startRecognition()` が `PERMISSION_DENIED: Api access revoked.`(AICoreがGoogle Playストアからも「対応しなくなりました」と明示されるstub版であることが原因)を、`MODE_ADVANCED` 指定時には `UNAVAILABLE: Peer process crashed, exited or was killed (binderDied)` を返すことを確認していた(spikes/android/RESULTS.md 参照)。この実測結果自体がAndroid標準SpeechRecognizerへの差し替えの根拠になったが、上表のAndroid列はすでに新バックエンドの `ERROR_*` 定数に置き換え済みであり、これらのML Kit固有エラーコードの写像は不要になった。
- 注記: 上表のAndroid列(標準SpeechRecognizerの `ERROR_*` 定数)は、Pixel 6実機での実測(`ERROR_INSUFFICIENT_PERMISSIONS` が発生しないこと等)に基づき初期版を記載したが、各 `ERROR_*` 定数と共通例外の対応付けは、`ERROR_LANGUAGE_UNAVAILABLE` / `ERROR_CANNOT_CHECK_SUPPORT` 等を含め実機でエラーを実発火させたわけではないため、M3実装時に確定させる必要がある。
- 注記: Web列について、言語パック未取得のまま `start()` を呼んだ場合に返るエラー名はロケールによって異なることをChrome 153実機で確認済みである。ja-JPでは `aborted`、en-USでは `language-not-supported` が返る(いずれも上表の `available() = unavailable` や `language-not-supported` とは別に、言語パック未取得という状況で観測された実測結果である)。この状況を `ModelUnavailable` へ写像する実装は、エラー名の判定ではなく `available()` による事前確認によって行うべきである(spikes/web/RESULTS.md 参照)。
- 注記: Windows列の ModelUnavailable に記載の「NotReady / EnsureNeeded で未同意」のうち「EnsureNeeded」という状態は、実際の `AIFeatureReadyState` enumには存在しない。実際の値は `Ready` / `NotReady` / `NotSupportedOnCurrentSystem` / `DisabledByUser` / `CapabilityMissing` / `NotCompatibleWithSystemHardware` / `OSUpdateNeeded` の7つであることをドキュメント調査で確認した(spikes/windows/RESULTS.md 参照)。本表のWindows列は実機確認のうえ確定させる必要がある。

## 6. 並行性・スレッディング

- Android: デコード・リサンプリング・実時間ポンプはDispatchers.IO上で1本のJobとして連結する。`SpeechRecognizer`はメインスレッドから生成・操作する契約であり、`RecognitionListener`と`checkRecognitionSupport()`のコールバックもメインスレッドのExecutorで受ける。EventChannelへの転送はメインスレッドへpost
- Darwin: SpeechAnalyzerのAsyncSequenceをTaskで消費、FlutterEventSinkへはmain actor経由
- Windows: WinRT asyncをcoroutine(C++/WinRT)で待機、結果はplatform threadへdispatch
- Web: シングルスレッド。長時間ファイルでもdecodeAudioDataは非同期なのでUIブロックなし

## 7. テスト戦略

- platform_interface: 純Dartユニットテスト(状態遷移、例外、二重セッション拒否)
- 各ネイティブ実装: モック不能なOS APIが中心のため、実機E2Eテストを主とする
  - 共通テスト資産: ja-JP / en-US の基準音声(10秒 / 3分 / 30分、wav・m4a・mp3)+ 期待テキスト。期待テキストは「全文文字起こし」と「評価用キーワードリスト」の2要素で構成する。キーワードは意味上重要な名詞・固有名詞・数値・専門用語から選定し、各基準音声ファイルごとに個別のキーワードリストを用意する。件数の目安は10秒で5件以上、3分で15件以上とし、件数が少なすぎる統計的に弱い判定は避ける方針とする
    - 注記: tasks.mdのM0記述は10秒・3分・wav・m4aの範囲であり、本項の30分・mp3はM0スコープ外。30分版・mp3形式は後続マイルストーン(実運用に近い長時間音声での検証等)向けの用途とする
  - 評価: WERではなくキーワード包含率での簡易判定(モデル差があるため厳密一致は不可)。算出式・正規化ルール・しきい値は下記「評価基準(キーワード包含率)」を参照
- CI: ビルド検証のみ(Android/iOS/Windows/Webのコンパイル)。認識E2Eは手動チェックリスト運用。iOSシミュレータではSpeechAnalyzerが利用できないため、認識E2Eはシミュレータでは原理的に実行できず実機が必須である
- example app: ファイルピッカー → モデル状態表示 → ダウンロード同意ダイアログ → 文字起こし進行表示、の参照実装を兼ねる

### 評価基準(キーワード包含率)

- 算出式: キーワード包含率 = 一致キーワード数 ÷ 期待キーワード総数
- 正規化ルール: 一致判定の前に、期待キーワードと認識結果テキストの**両方**へ同一の正規化を同一手順で適用する。片側のみへの適用は禁止する
  - 共通(全言語に適用、この順で実施する):
    1. Unicode NFKC 正規化を行う。これにより全角英数字・記号は半角へ、半角カナは全角カナへ統一される
    2. 小文字化する(ja-JPに含まれるラテン文字にも適用する)
    3. 句読点・記号を除去する。対象は Unicode 一般カテゴリ P(句読点)と S(記号)の全文字、および `、。「」・,.!?:;()[]{}"'-/` を含む
    4. 空白を除去する。対象は半角/全角スペース、タブ、改行を含む全空白文字。これにより `ISO 27001` と `ISO27001`、`November 3rd, 2024` と `November 3rd 2024` はいずれも同一の正規形になる
  - ja-JP 固有: 上記に加えてひらがなをカタカナへ畳み込み、ひらがな/カタカナ表記の揺れを同一視する
  - 数値・日付: 上記の共通正規化で区切り記号と空白が除去されるため、`2024年11月3日` / `2024/11/3` のような区切りの違いは吸収されない。表記が複数あり得るキーワードは、基準音声の `.json` の `keywords` に**許容表記を列挙**し、いずれか1つに一致すれば当該キーワードを一致とみなす
  - 注記: 空白除去により英語では語境界が失われ、語をまたいだ部分一致が成立しうる。キーワードは語境界をまたいだ偶然一致が起きない程度の長さ・具体性を持つものを選定する
- 判定は1ファイル単位で行い、結果は条件(クリーン/実環境等)別・言語別に集計する
- キーワード包含率はWERの代替指標であり、厳密一致を求めるものではない

しきい値は以下のとおり。

> **Issue #20 での是正**: 以前の表は ja-JP の「合格しきい値」を 90%以上と書きながら、同じ行の備考で「90〜94%は条件付き合格」としており、90〜94% が合格なのか条件付き合格なのかが読めなかった。3区分へ分けて解消した。なお `spikes/darwin/RESULTS.md` / `spikes/web/RESULTS.md` / `spikes/android/RESULTS.md` はいずれも ja-JP を 95%以上で判定しており、**是正後の本表と一致する**。実測はすべて 66.7% 以下であり、どちらの読み方でも判定は「不成立」で変わらない。


| 条件 | 言語 | 区分 | 判定 |
|---|---|---|---|
| クリーン基準音声 | ja-JP | 95%以上 | 合格 |
| クリーン基準音声 | ja-JP | 90〜94% | 条件付き合格 / 要確認 |
| クリーン基準音声 | ja-JP | 90%未満 | 不成立 |
| クリーン基準音声 | en-US | 95%以上 | 合格 |
| クリーン基準音声 | en-US | 95%未満 | 不成立 |
| クリーン基準音声(共通) | - | 不成立の場合 | tasks.mdの「M0 出口判定」で対象外化または構成変更の検討対象とする |
| 実環境(ノイズあり、参考値) | ja-JP / en-US | 上記しきい値から一律5ポイント程度緩和した値を参考とする | 後続のE2E回帰でも同一の算出式・正規化ルールを再利用する |

### 注記: Darwin M0スパイクでのキーワード包含率実測結果

macOS 26.5.1実機での実測(spikes/darwin/RESULTS.md 参照)では、基準音声8ファイル(ja-JP/en-US × 10秒/3分 × wav/m4a)**全てで上記しきい値に対して「不成立」**という結果になった(ja-JP: 28.6〜66.7%、en-US: 44.0〜80.0%)。

Webでも同じ基準音声 jaJP_10s(1.0x再生)で実測したところ、包含率は 66.7%(4/6)であり、Darwinの jaJP_10s と**同率**であった(spikes/web/RESULTS.md 参照)。ただし両プラットフォームで落としているキーワードは同一ではない(Darwin: 株式会社モーンギフト / 128名。Web: 東京都渋谷区 / 株式会社モーンギフト)。同率という事実は、原因が(a)基準音声の設計、(b)各プラットフォームの認識モデル自体の実力、のいずれであるかを切り分ける材料にはなっておらず、原因未確定であることは変わらない。

一方で、認識自体は概ね正確であることも確認できている。例えば jaJP_10s では6キーワード中4つが一致しており、不一致となった2件は「株式会社モーンギフト」→「モーギフト/モギフト」(架空の固有名詞の誤認識)と「128名」→「102十8名」(数値の表記形式の揺れ)のみであった。

**不成立の原因は未確定である。** 対照条件を振った再測定を行っていないため、(a)基準音声がTTS合成音声であること、(b)`SpeechTranscriber.Preset` の選択、(c)認識モデル自体の精度、(d)キーワード選定と上記正規化規則が表記差を吸収できていないこと、のいずれが支配的かを分離できていない。上記の例も、認識内容そのものの誤りと、キーワード比較が表記差を吸収できていないことの切り分けができていない。

しきい値に照らした精度判定は不成立であり、この事実は変わらない。したがって、原因が未確定であることを理由にM0を条件付き成立として扱ってはならない。以下はM0出口判定で決める事項とする。

1. 精度判定そのものの合否
2. 基準音声セットの読み上げスクリプトとキーワード選定を見直すか
3. 本節のしきい値・正規化規則を見直すか
4. プリセットを判定条件に含めるか

## 8. 設計上の未決事項(M0の結果で確定)

1. Windows: RecognizeFromFileの対応フォーマットとロケール指定可否
   - ロケール指定可否: **確定**。下記未決事項2参照
   - 対応フォーマット: **未確定のまま。M4では「常に変換する」という処置で回避した。** `BatchRecognition.RecognizeFromFile` は Media Foundation で 16kHz・モノラル・16-bit PCM の RIFF WAVE へ変換してから渡す。素通しして失敗したら変換する方式は「どのエラーがフォーマット拒否か」を知っている必要があり、それ自体が未確定の当の対象であるうえ、フォールバックそのものになるため採らなかった。**出力形式(16kHz・モノラル)の選定も推定である**(Windows AI 側の要求サンプルレートは非公開)。Issue #58 で確定させる。以下は調査時点の記録である。`BatchRecognition.RecognizeFromFile` の公式APIリファレンスページ(および周辺ページ・名前空間全体)に、対応するコンテナ・コーデックの一覧や制約に関する記載が見つからなかった。wav / m4a / mp3 が受理されるかはWindows実機での確認が必須である(Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)
2. Windows: ja-JP対応可否
   - ロケール指定APIの有無: **確定**。`Microsoft.Windows.AI.Speech` 名前空間の全クラス・全メンバー(`SpeechRecognitionModel`・`BatchRecognition`・`AudioConfiguration`等)を公式APIリファレンスで突き合わせた結果、ロケール・言語を指定する引数・プロパティ・メソッドは1件も存在しないことをドキュメント調査で確定した(spikes/windows/RESULTS.md 参照)。ロケール指定ができない以上、design.md §4.4にある「指定不能ならOS言語依存としてREADME明記」という方針が確定した前提となる
   - ja-JP書き起こし可否: **未確定のまま**。ロケール指定APIが無い場合に実際にどの言語で認識されるか(OS表示言語連動か、既定入力言語連動か等)、およびja-JP音声が実際に高精度で認識されるかは、ドキュメントに記載が無くWindows実機でのみ確認可能である(Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)
3. Darwin: SpeechAnalyzerのja-JP対応可否とファイル処理速度
   - ファイル処理速度: **確定**。macOS 26.5.1実機でRTF 0.008〜0.026(実時間の約38〜125倍高速)を実測(spikes/darwin/RESULTS.md 参照)
   - ja-JP対応可否: **確定**。macOS 26.5.1実機では `supportedLocales`(30件)にja-JPが含まれ、実際の文字起こしも動作することを確認済み。**iOS 26.6.2実機(iPad Pro 11-inch M4)でも `supportedLocales`(30件)にja-JPが含まれることを確認した(Issue #7)**。iOS 27.0実機(iPhone 17)では45件でありja-JPを含む。**`supportedLocales` はOSバージョンで実際に変わる(26系30件 / 27系45件)ため、27系の結果から下限である26系を外挿することはできず、下限での確認が必要だった。** iOSシミュレータでは`.app`バンドルでの再検証でも`isAvailable=false`となる(シミュレータ自体にオンデバイス音声モデルが無い)。spikes/darwin/RESULTS.md 参照
4. Web: `start(audioTrack)` + `processLocally: true` の併用動作
   - **確定**。Chrome 153実機(通常の対話的Chromeセッション)で実測し、成立することを確認した。`processLocally = true` の設定と読み戻しが成功し、`audioTrack.readyState = "live"` の状態で `recognition.start(audioTrack)` が受理されて `onstart` が発火、partial結果が実時間で継続的に得られた。`network` エラーは発生しなかった。ただし `continuous = true` では `AudioBufferSourceNode` の再生終了後も `MediaStreamTrack` が `live` のまま無音を流し続けるため、Chromeは入力終了を自動認識しない。`source.onended` の後に明示的に `recognition.stop()` を呼んで初めて、約25ms後に `isFinal` の結果と、その直後に `onend` が発火してセッションが正常終了する。この `stop()` 呼び出しが§4.1の終了検出フローの必須要素である(spikes/web/RESULTS.md 参照)
5. Android: MODE_ADVANCED指定時の非対応端末での自動フォールバック有無
   - **ML Kit GenAI Speech Recognitionを採用しないため本項目は対象外となった。** バックエンドをAndroid標準 `android.speech.SpeechRecognizer` へ差し替えたことにより、ML Kit固有の概念である `MODE_ADVANCED`/`MODE_BASIC` およびそのフォールバック挙動自体が存在しなくなった(経緯はspikes/android/RESULTS.md「代替案の検証: Android 標準 SpeechRecognizer」節、および本ドキュメント§4.3冒頭参照)。
6. Android: リサンプリング実装の要否(実ファイルのMediaCodec出力レート調査)
   - **確定: リサンプリングは必須**。MediaCodecはコーデックのデコードのみを行い、サンプルレート変換・チャンネルのダウンミックスは一切行わないことを実測で確認した。実環境相当の音源7ファイル(44.1kHz/48kHzステレオのwav・m4a・mp3、22.05kHzモノラル、8kHzモノラル)全てで`resampleNeeded=true`となった(spikes/android/RESULTS.md 参照)。エミュレータ(`sdk_gphone64_arm64`, Android 16/API 36)単一環境での実測であり、実機での追試は引き続き望ましい。この結論は認識バックエンド(ML Kit GenAI Speech Recognition / 標準SpeechRecognizer)とは無関係なMediaCodecの挙動であり、バックエンド差し替えの影響を受けない
7. Web: 再生速度オプション(`playbackRate`)の上限値と、精度低下に関する利用者への提示方法(M1で決定。§4.1参照)
   - **確定: 利用者が指定できるAPIオプションとして公開する**。`TranscribeRequest.playbackRate`(既定 1.0)であり、範囲外の値は `ArgumentError` で明確に失敗させる。上限は設けていない
   - Chrome 153 実機での実測(jaJP_10s、spikes/web/RESULTS.md): 1.0x で 66.7%、1.5x で 50.0%、2.0x で 33.3% と**単調に低下する**。1.1x / 1.25x も測定し、この範囲は選択肢に入りうると判断した
   - **注意**: `spikes/web/RESULTS.md` は M0 時点で「実用的なスループット向上の余地はない。倍速再生は非対応の方針とする」と結論していたが、**その後の判断でこれを覆し、利用者が速度を指定できるようにする方針が採られた**。ライブラリが勝手に速度を選ぶのではなく、トレードオフを提示したうえで利用者に選ばせるという整理である。RESULTS.md の当該結論は M0 時点の記録として残っている
   - Web専用オプションであり、他プラットフォームは無視する(§2.2)
8. Android: 標準SpeechRecognizerのPixel 6以外の端末での動作、および `onResults()` が `null` になる挙動が全端末共通かどうか
   - **未確定。M3で確認する必要がある。** §4.3記載のとおり、ja-JPオンデバイス言語パックの取得・`EXTRA_AUDIO_SOURCE`経由のファイル入力受理・`onResults()`が`null`になる挙動は、いずれもPixel 6(API 37、ブートローダーロック済み)単一機種での実測にとどまる(spikes/android/RESULTS.md「限界」参照)。他機種(特にja-JPのオンデバイス言語パックが最初から導入済みの機種や、`supportedOnDeviceLanguages`自体にja-JPを含まない機種)での挙動、および`onResults()`が`null`になる挙動がAndroidバージョン・機種によらず一貫するかは未検証である

確定事項: `available()` / `install()` のja-JP実機確認結果(クリーンプロファイルで `downloadable` → `install()` で `available`。Chrome 153、spikes/web/RESULTS.md 参照)
