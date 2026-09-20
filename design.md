# design.md

Flutterライブラリ「オフライン音声ファイル文字起こし」技術設計

対応する要件: requirements.md v1

## 1. アーキテクチャ全体像

```
アプリ
 └── <name>(エントリパッケージ)
      └── <name>_platform_interface(共通抽象)
           ├── <name>_android   … Pigeon → Kotlin(ML Kit + MediaCodecポンプ)
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
- 終了検出: sourceの `onended` 後、`recognition.onend` をもってStream close
- 制約: 認識は実時間。倍速再生でのスループット向上は非対応として仕様化(認識品質への影響が未検証のため)
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

パイプライン:

```
入力ファイル
  → MediaExtractor + MediaCodec でデコード
  → リサンプリング(16kHz・モノラル・16-bit PCM)
  → ParcelFileDescriptor.createPipe()
  → 書き込み側: 実時間ポンプ(毎秒約32KB、コルーチンで供給)
  → AudioSource.fromPfd(読み取り側)
  → SpeechRecognizer.startRecognition() の Kotlin Flow
  → EventChannel へ転送
```

- `speechRecognizerOptions { locale; preferredMode = MODE_ADVANCED }` で生成し、Advanced非対応端末のBasicフォールバック挙動をM0で確認。フォールバックが自動でない場合はBasicで再生成するリトライを実装
- 実時間ポンプ設計:
  - 供給レートは壁時計基準(累積送信サンプル数と経過時間の差分でsleep調整)。バッファ単位100ms(3,200サンプル)
  - キャンセル時はパイプclose → `stopRecognition()` → `close()`
- リサンプリング: MediaCodec出力が16kHz以外の場合は線形補間ではなくAudioResampler相当の処理が必要。実装コスト次第で対応入力を「デコード後にリサンプル可能な形式」に限定するか判断(M3で決定)
- ブートローダーアンロック端末・AICore未初期化は `checkStatus()` 結果とAICoreエラーコード(601 / 606 等)を `DeviceUnsupportedException` / `ModelUnavailableException` に写像

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
- WinAppSDKのバージョン前提に課題がある: `Microsoft.Windows.AI.Speech` 名前空間のAPIリファレンスページは `windows-app-sdk-2.0-experimental` モニカーでのみ存在し、1.7 / 1.8 / 2.0(安定版)のいずれのモニカーにも掲載が確認できなかった。requirements.md NFR-4が前提とする「WinAppSDK 1.7.1以上」という記述の再確認が必要である(spikes/windows/RESULTS.md 参照)
- C++/WinRT実装。WinAppSDK 1.7.1+をプラグインの依存として宣言し、MSIX + `systemAIModels` はアプリ側要件としてREADMEに記載

## 5. エラーマッピング表

| 共通例外 | Android | Darwin | Windows | Web |
|---|---|---|---|---|
| ModelUnavailable | FeatureStatus.UNAVAILABLE / AICore 606 | アセット取得不可 | NotReady / EnsureNeeded で未同意 | available() = unavailable |
| LocaleUnsupported | ロケール非対応ステータス | supportedLocales外 | (M0確認後に確定) | language-not-supported |
| DecodeFailed | MediaCodecエラー | AVAudioFileエラー | Media Foundation失敗 | decodeAudioData reject |
| DeviceUnsupported | ブートローダーアンロック / API<31 | OS 26未満 | NotSupportedOnCurrentSystem | 非Chrome系 |
| Cancelled | Flow cancel | Task cancel | 認識中断 | stop/abort |

- 注記: Darwin列のうち DecodeFailed(AVAudioFileエラー)と LocaleUnsupported(supportedLocales外)は、macOS 26.5.1実機でエラーを実発火させ動作を確認済みである(spikes/darwin/RESULTS.md 参照)。
- 注記: Windows列の ModelUnavailable に記載の「NotReady / EnsureNeeded で未同意」のうち「EnsureNeeded」という状態は、実際の `AIFeatureReadyState` enumには存在しない。実際の値は `Ready` / `NotReady` / `NotSupportedOnCurrentSystem` / `DisabledByUser` / `CapabilityMissing` / `NotCompatibleWithSystemHardware` / `OSUpdateNeeded` の7つであることをドキュメント調査で確認した(spikes/windows/RESULTS.md 参照)。本表のWindows列は実機確認のうえ確定させる必要がある。

## 6. 並行性・スレッディング

- Android: デコードポンプはDispatchers.IO、認識FlowはML Kit既定。EventChannelへの転送はメインスレッドへpost
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

| 条件 | 言語 | 合格しきい値 | 備考 |
|---|---|---|---|
| クリーン基準音声 | ja-JP | 90%以上 | 90〜94%は「条件付き合格 / 要確認」の中間区分とする |
| クリーン基準音声 | en-US | 95%以上 | - |
| クリーン基準音声(共通) | - | 上記未満 | 「不成立」。tasks.mdの「M0 出口判定」で対象外化または構成変更の検討対象とする |
| 実環境(ノイズあり、参考値) | ja-JP / en-US | 上記しきい値から一律5ポイント程度緩和した値を参考とする | 後続のE2E回帰でも同一の算出式・正規化ルールを再利用する |

### 注記: Darwin M0スパイクでのキーワード包含率実測結果

macOS 26.5.1実機での実測(spikes/darwin/RESULTS.md 参照)では、基準音声8ファイル(ja-JP/en-US × 10秒/3分 × wav/m4a)**全てで上記しきい値に対して「不成立」**という結果になった(ja-JP: 28.6〜66.7%、en-US: 44.0〜80.0%)。

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
   - 対応フォーマット: **未確定**。`BatchRecognition.RecognizeFromFile` の公式APIリファレンスページ(および周辺ページ・名前空間全体)に、対応するコンテナ・コーデックの一覧や制約に関する記載が見つからなかった。wav / m4a / mp3 が受理されるかはWindows実機での確認が必須である(Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)
2. Windows: ja-JP対応可否
   - ロケール指定APIの有無: **確定**。`Microsoft.Windows.AI.Speech` 名前空間の全クラス・全メンバー(`SpeechRecognitionModel`・`BatchRecognition`・`AudioConfiguration`等)を公式APIリファレンスで突き合わせた結果、ロケール・言語を指定する引数・プロパティ・メソッドは1件も存在しないことをドキュメント調査で確定した(spikes/windows/RESULTS.md 参照)。ロケール指定ができない以上、design.md §4.4にある「指定不能ならOS言語依存としてREADME明記」という方針が確定した前提となる
   - ja-JP書き起こし可否: **未確定のまま**。ロケール指定APIが無い場合に実際にどの言語で認識されるか(OS表示言語連動か、既定入力言語連動か等)、およびja-JP音声が実際に高精度で認識されるかは、ドキュメントに記載が無くWindows実機でのみ確認可能である(Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)
3. Darwin: SpeechAnalyzerのja-JP対応可否とファイル処理速度
   - ファイル処理速度: **確定**。macOS 26.5.1実機でRTF 0.008〜0.026(実時間の約38〜125倍高速)を実測(spikes/darwin/RESULTS.md 参照)
   - ja-JP対応可否: **確認済み(iOS 26実機は未実施)**。macOS 26.5.1実機では `supportedLocales`(30件)にja-JPが含まれ、実際の文字起こしも動作することを確認済み。iOS 27.0実機(iPhone 17)でも `supportedLocales`(45件)にja-JPが含まれることを確認済み。ただしIssue #7が指定するiOS 26実機での確認は未実施である(iOSシミュレータでは`.app`バンドルでの再検証でも`isAvailable=false`となることを確認しており、原因はシミュレータ自体にオンデバイス音声モデルが無いことと判明している。spikes/darwin/RESULTS.md 参照)
4. Web: `start(audioTrack)` + `processLocally: true` の併用動作
   - 進捗注記: `processLocally = true` の設定と読み戻しはChrome 153で可能であることを確認済み。併用動作そのものは未検証
5. Android: MODE_ADVANCED指定時の非対応端末での自動フォールバック有無
6. Android: リサンプリング実装の要否(実ファイルのMediaCodec出力レート調査)

確定事項: `available()` / `install()` のja-JP実機確認結果(クリーンプロファイルで `downloadable` → `install()` で `available`。Chrome 153、spikes/web/RESULTS.md 参照)
