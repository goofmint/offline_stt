# tasks.md

Flutterライブラリ「オフライン音声ファイル文字起こし」タスク分解

対応文書: requirements.md / design.md
凡例: [ ] 未着手。依存関係は各マイルストーン冒頭に記載。

## M0 検証スパイク(実装前の関門)

ゴール: 4プラットフォームで ja-JP のファイル文字起こしが成立するか判定する。不成立があれば構成再検討に戻る。

### 共通

- [x] 基準音声セット作成: ja-JP / en-US、各10秒・3分、wav と m4a(期待テキスト付き)。`test-assets/baseline-audio/` に格納。期待テキストは「全文文字起こし + キーワードリスト」の2要素構成(詳細は design.md 7章参照)
- [x] 判定基準の定義(キーワード包含率のしきい値)(design.md 7章 参照)

### Web

- [x] Chrome 142+ で `SpeechRecognition.available({langs: ['ja-JP'], processLocally: true})` の結果確認(結果: downloadable。spikes/web/RESULTS.md 参照)
- [x] `install()` での ja-JP 言語パック取得確認(取得成功、約8.7秒で available へ遷移。spikes/web/RESULTS.md 参照)
- [x] `start(audioTrack)` + `processLocally: true` の併用動作確認(設計未決事項4)(成立。source.onended 後に stop() を呼ぶと isFinal 結果と onend が発火する。spikes/web/RESULTS.md 参照)
- [x] 基準音声での書き起こし精度確認(jaJP_10s で 66.7%、しきい値未達。倍速は精度が単調低下。spikes/web/RESULTS.md 参照)

### Darwin

- [x] iOS 26実機で SpeechTranscriber の supportedLocales に ja が含まれるか確認(設計未決事項3)(**確認済み**。iPad Pro 11-inch (M4) / iOS 26.6.2 実機で `supportedLocales`(30件)に ja-JP を確認、`installedLocales` も ja-JP。OSバージョンによる差は実在した(26系30件 / 27系45件)ため、iOS 27.0 の結果からの外挿はできず下限での確認が必要だった。spikes/darwin/RESULTS.md 参照)
- [ ] iOS 実機でのファイル文字起こし検証(記録済みのファイル入力結果は macOS のものであり、iOS 実機では未実施。spikes/darwin/RESULTS.md 参照)
- [x] AVAudioFile → SpeechAnalyzer のファイル入力スパイク(Swift単体、Flutter外)(ja-JP/en-US × 10秒/3分 × wav/m4a の全8ファイルでエラーなく完走。spikes/darwin/RESULTS.md 参照)
- [x] ファイル処理速度の実測(実時間比)(RTF 0.008〜0.026、実時間の38〜125倍高速。spikes/darwin/RESULTS.md 参照)
- [x] macOS 26 でも同スパイクを確認(macOS 26.5.1 実機で確認済み。ただしキーワード包含率は8ファイル中8ファイルとも判定基準未達。spikes/darwin/RESULTS.md 参照)

### Android

- [ ] Pixel以外のAPI 31+実機で Basic モード + ja-JP の動作確認(ハーネス実装済み。Pixel 6 実機(API 37、ブートローダーロック済み)で実行したが、AICore が stub 版のため checkStatus() が PERMISSION_DENIED: Api access revoked. を返し到達せず。実体のある AICore を持つ端末が必要。**ユーザー判断によりバックエンドをML Kit GenAI Speech RecognitionからAndroid標準SpeechRecognizerへ差し替えたため、本項目が意図していた「Basicモード」自体がML Kit固有の概念であり対象外となった。標準SpeechRecognizerについてPixel 6実機ではja-JPのファイル文字起こしに成功した(包含率66.7%)が、Pixel以外の実機での動作は別途検証が必要である。** spikes/android/RESULTS.md 参照)
- [x] `MODE_ADVANCED` 指定時の非対応端末フォールバック挙動確認(design.md §8未決事項5)(ハーネス実装済み。Pixel 6 実機(API 37、ブートローダーロック済み)で実行したが、AICore が stub 版のため checkStatus() が PERMISSION_DENIED: Api access revoked. を返し到達せず。実体のある AICore を持つ端末が必要。**ユーザー判断によりバックエンドをML Kit GenAI Speech RecognitionからAndroid標準SpeechRecognizerへ差し替えたため、`MODE_ADVANCED`/`MODE_BASIC`という概念自体がML Kit固有であり本項目は対象外となった(design.md §8未決事項5参照)。標準SpeechRecognizerには対応するモード概念が無いため、本項目に代わる検証は不要である。** spikes/android/RESULTS.md 参照)(**#20で失効として確定**。design.md §8 未決事項5 参照)
- [ ] PFDパイプ + 実時間ポンプの最小実装で `AudioSource.fromPfd()` が受理されるか確認(ハーネス実装済み。Pixel 6 実機(API 37、ブートローダーロック済み)で実行したが、AICore が stub 版のため checkStatus() が PERMISSION_DENIED: Api access revoked. を返し到達せず。実体のある AICore を持つ端末が必要。**ユーザー判断によりバックエンドをML Kit GenAI Speech RecognitionからAndroid標準SpeechRecognizerへ差し替えたため、`AudioSource.fromPfd()`というML Kit固有APIでの受理確認自体は対象外となった。標準SpeechRecognizerの等価な仕組み(`RecognizerIntent.EXTRA_AUDIO_SOURCE`)については別途スパイクで受理を確認済み(Pixel 6実機、既存の実時間ポンプをそのまま流用)だが、これは本項目の代替検証であり別途実施したものである。Pixel以外の機種での受理確認は未実施のため、改めて別途検証が必要である。** spikes/android/RESULTS.md 参照)
- [x] 手持ち音源の MediaCodec デコード出力レート調査(リサンプリング要否判定、設計未決事項6)(結論: リサンプリング必須。MediaCodecはrate/chを変換しない。spikes/android/RESULTS.md 参照)

### Windows

- [ ] Windows 11 24H2機で `EnsureReadyAsync` → モデル取得確認(CPU機 / 可能ならCopilot+ PC両方)(スパイク実装済み。Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)
- [ ] `RecognizeFromFile` の対応フォーマット確認: wav / m4a / mp3(設計未決事項1)(スパイク実装済み。ドキュメントに記載が無く実機確認が必須。Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)
- [ ] ロケール指定APIの有無確認、ja-JP 書き起こし確認(設計未決事項2)(ロケール指定APIは存在しないことをドキュメント調査で確定。ja-JP 書き起こしは Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)
- [ ] MSIX + `systemAIModels` capability の最小構成アプリで動作確認(スパイク実装済み。capability あり/なし両方の manifest を用意済み。Windows機が無いため未実施。spikes/windows/RESULTS.md 参照)

### M0 出口判定

- [ ] 4プラットフォームの判定結果を requirements.md の対応表に反映(不成立項目は対象外化 or 構成変更)
- [x] design.md の未決事項1〜6を確定値で更新(あわせて §4.3 Android を標準 `SpeechRecognizer` 前提へ全面書き換え、§5 の Android 列を `ERROR_*` 写像へ更新、§7 しきい値表の内部矛盾(ja-JP 90% と「90〜94% は条件付き合格」の併記)を3区分に分けて解消、未決事項7(`playbackRate`)を追加して確定させた)

## M1 基盤 + Web実装

依存: M0完了

### パッケージ基盤

- [ ] モノレポ構成作成(melos)、6パッケージの雛形
- [ ] `<name>_platform_interface`: データ型・例外階層・抽象クラス実装
- [ ] 状態遷移とセッション排他(同時1本)のユニットテスト
- [ ] Pigeonスキーマ定義(Method + EventChannel、Android/Darwin/Windows向け生成確認)
- [ ] CI: 全パッケージのanalyze + test + 各プラットフォームビルド検証

### Web実装

- [ ] `checkModel` / `downloadModel`(available/install写像)
- [ ] デコード層: Blob → decodeAudioData → MediaStreamTrack
- [ ] 認識セッション: start(audioTrack)、partial/final写像、onendでclose
- [ ] キャンセル処理(source stop + recognition abort)
- [ ] 非Chrome環境の unavailable 分岐
- [ ] E2E手動チェックリスト作成 + 基準音声で確認

### example app(最小)

- [ ] ファイルピッカー + モデル状態表示 + ダウンロード同意ダイアログ + 結果表示

## M2 Darwin実装

依存: M1(platform_interface + Pigeonスキーマ確定)

- [ ] darwinパッケージ雛形(iOS/macOS共用ソース構成)
- [ ] OSバージョンゲート(`if #available`、26未満は unavailable)
- [ ] モデル管理: AssetInventory照会 → checkModel、取得要求 → downloadModel
- [ ] デコード層: AVAudioFile → AnalyzerInput変換
- [ ] 認識セッション: SpeechAnalyzer + SpeechTranscriber、AsyncSequence → EventChannel転送
- [ ] キャンセル(Task cancel → analyzer終了)
- [ ] エラーマッピング実装(design.md 5章の表)
- [ ] iOS実機 + macOS実機で基準音声E2E
- [ ] example appにiOS/macOS動作を追加

## M3 Android実装

依存: M1

- [ ] androidパッケージ雛形(バックエンドはAndroid標準 `android.speech.SpeechRecognizer` を使用するため、`genai-speech-recognition` 等ML Kit関連の依存追加は不要。design.md §4.3参照)
- [ ] モデル管理: `checkRecognitionSupport()` → checkModel(4値写像は`supportedOnDeviceLanguages`/`installedOnDeviceLanguages`/`pendingOnDeviceLanguages`/`onlineLanguages`の突き合わせ。requirements.md FR-1参照)、`triggerModelDownload()` → downloadModel進捗(完了判定は`ModelDownloadListener`のコールバックに依らず`checkRecognitionSupport()`の再照会で行う。spikes/android/RESULTS.md参照)
- [ ] デコード層: MediaExtractor + MediaCodec → 16kHz/モノラル/16-bit PCM
- [ ] リサンプリング実装 or 対応入力の限定(M0調査結果に従う)(M0結論: リサンプリング必須。バックエンド差し替えの影響を受けない)
- [ ] 実時間ポンプ: PFDパイプ、壁時計基準レート制御(100msバッファ)(標準SpeechRecognizerでも既存設計をそのまま流用できることをPixel 6実機で確認済み。spikes/android/RESULTS.md参照)
- [ ] 認識セッション: `createOnDeviceSpeechRecognizer()` + `EXTRA_PREFER_OFFLINE=true`設定、`RecognitionListener`コールバック → EventChannel転送、`onResults()`のtextsがnullの場合は直前の`onPartialResults()`の最上位候補を確定結果として採用(design.md §4.3参照。preferredMode設定・Basicリトライ関連はML Kit固有のため不要)
- [ ] キャンセル(パイプclose → `stopListening()` → `destroy()`。design.md §4.3参照)
- [ ] エラーマッピング(`SpeechRecognizer`の`ERROR_*`定数ベース。design.md §5参照。ブートローダーアンロック・AICoreエラーはML Kit固有のため対象外)
- [ ] Pixel系 + 非Pixel系の2機種で基準音声E2E(design.md §8未決事項8: Pixel 6以外の端末での動作、および`onResults()`がnullになる挙動が全端末共通かを確認する)
- [ ] example appにAndroid動作を追加

## M4 Windows実装

依存: M1

- [ ] windowsパッケージ雛形(C++/WinRT、WinAppSDK 1.7.1+依存宣言)
- [ ] モデル管理: GetReadyState → checkModel、EnsureReadyAsync → downloadModel(不定進捗対応)
- [ ] (M0結果次第)Media Foundation wav変換層
- [ ] 認識セッション: TryCreateAsync → BatchRecognition → final 1件emit
- [ ] キャンセルとエラーマッピング(NotSupportedOnCurrentSystem等)
- [ ] MSIXセットアップ手順ドキュメント(manifest記載例、AIコンポーネント削除時の再同意フロー)
- [ ] CPU機で基準音声E2E(可能ならCopilot+ PCでも)
- [ ] example appにWindows動作を追加(MSIX構成)

## M5 公開

依存: M2〜M4完了

- [ ] README: 対応状況マトリクス(OS / 最低バージョン / 所要時間特性 / ja-JP検証結果)
- [ ] README: アプリ側要件(MSIX、同意ダイアログ、AICore初期化、非Chrome分岐)
- [ ] README: モデル同梱型代替(sherpa-onnx等)との使い分け記載
- [ ] APIドキュメント(dartdoc)整備
- [ ] CHANGELOG / LICENSE / pubspec整備(0.1.0、全パッケージ)
- [ ] pub.dev dry-run → 6パッケージ公開(publish順: platform_interface → 各実装 → エントリ)
- [ ] E2E手動チェックリストをリポジトリに収録(リリース前検証手順として)

## 継続タスク(公開後)

いずれもコードとして「実装」できる種類のタスクではなく、**リポジトリの外で
継続的に人が回す運用**である。Issue #67 / #68 / #69 では、その運用の拠り所に
なる文書を `docs/` に用意した。**文書があることと運用が回っていることは別で
あり、下記のいずれもまだ一度も実行されていない。**

- [ ] 依存プラットフォームの変更監視(四半期ごとに基準音声E2E再実行)。
      手順は [docs/MONITORING.md](./docs/MONITORING.md)(Issue #67)。
      **監視対象は `android.speech.SpeechRecognizer` + Google Play services /
      Chromeのオンデバイス Web Speech / WinAppSDK・Windows AI APIs /
      iOS・macOS・Android・Windows のOSベータである。**
      当初ここに書いてあった「ML Kit alpha」は**対象外である**。M0検証で
      AICoreがPixel 6で使えないことが判明し、バックエンドを Android 標準の
      `android.speech.SpeechRecognizer` へ差し替えたため
      (design.md §4.3 冒頭、spikes/android/RESULTS.md)。
- [ ] 破壊的変更時の追従とバージョン固定更新。
      方針は [docs/VERSION_POLICY.md](./docs/VERSION_POLICY.md)(Issue #68)。
- [ ] 将来拡張の検討: タイムスタンプ、マイク入力、同時複数セッション。
      設計レベルの評価は
      [docs/FUTURE_EXTENSIONS.md](./docs/FUTURE_EXTENSIONS.md)(Issue #69)。
