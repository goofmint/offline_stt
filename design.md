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
- 要実測: ファイル入力時の処理速度(実時間より速いか)。結果をREADMEの所要時間表に反映

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
- `RecognizeFromFile` の対応入力フォーマットはM0で確認。wav以外が通らなければMedia Foundation変換層を必須化
- 言語指定APIの有無をM0で確認(ドキュメント上、ロケール指定の記載が未確認。指定不能ならOS言語依存としてREADME明記、ja-JP検証が最優先)
- C++/WinRT実装。WinAppSDK 1.7.1+をプラグインの依存として宣言し、MSIX + `systemAIModels` はアプリ側要件としてREADMEに記載

## 5. エラーマッピング表

| 共通例外 | Android | Darwin | Windows | Web |
|---|---|---|---|---|
| ModelUnavailable | FeatureStatus.UNAVAILABLE / AICore 606 | アセット取得不可 | NotReady / EnsureNeeded で未同意 | available() = unavailable |
| LocaleUnsupported | ロケール非対応ステータス | supportedLocales外 | (M0確認後に確定) | language-not-supported |
| DecodeFailed | MediaCodecエラー | AVAudioFileエラー | Media Foundation失敗 | decodeAudioData reject |
| DeviceUnsupported | ブートローダーアンロック / API<31 | OS 26未満 | NotSupportedOnCurrentSystem | 非Chrome系 |
| Cancelled | Flow cancel | Task cancel | 認識中断 | stop/abort |

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
- CI: ビルド検証のみ(Android/iOS/Windows/Webのコンパイル)。認識E2Eは手動チェックリスト運用
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

## 8. 設計上の未決事項(M0の結果で確定)

1. Windows: RecognizeFromFileの対応フォーマットとロケール指定可否
2. Windows: ja-JP対応可否
3. Darwin: SpeechAnalyzerのja-JP対応可否とファイル処理速度
4. Web: `start(audioTrack)` + `processLocally: true` の併用動作
5. Android: MODE_ADVANCED指定時の非対応端末での自動フォールバック有無
6. Android: リサンプリング実装の要否(実ファイルのMediaCodec出力レート調査)
