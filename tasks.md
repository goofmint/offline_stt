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
- [ ] `start(audioTrack)` + `processLocally: true` の併用動作確認(設計未決事項4)
- [ ] 基準音声での書き起こし精度確認

### Darwin

- [ ] iOS 26実機で SpeechTranscriber の supportedLocales に ja が含まれるか確認(設計未決事項3)(macOS 26.5.1 では ja-JP を確認済み。iOS実機は未検証。spikes/darwin/RESULTS.md 参照)
- [x] AVAudioFile → SpeechAnalyzer のファイル入力スパイク(Swift単体、Flutter外)(ja-JP/en-US × 10秒/3分 × wav/m4a の全8ファイルでエラーなく完走。spikes/darwin/RESULTS.md 参照)
- [x] ファイル処理速度の実測(実時間比)(RTF 0.008〜0.026、実時間の38〜125倍高速。spikes/darwin/RESULTS.md 参照)
- [x] macOS 26 でも同スパイクを確認(macOS 26.5.1 実機で確認済み。ただしキーワード包含率は8ファイル中8ファイルとも判定基準未達。spikes/darwin/RESULTS.md 参照)

### Android

- [ ] Pixel以外のAPI 31+実機で Basic モード + ja-JP の動作確認
- [ ] `MODE_ADVANCED` 指定時の非対応端末フォールバック挙動確認(設計未決事項5)
- [ ] PFDパイプ + 実時間ポンプの最小実装で `AudioSource.fromPfd()` が受理されるか確認
- [ ] 手持ち音源の MediaCodec デコード出力レート調査(リサンプリング要否判定、設計未決事項6)

### Windows

- [ ] Windows 11 24H2機で `EnsureReadyAsync` → モデル取得確認(CPU機 / 可能ならCopilot+ PC両方)
- [ ] `RecognizeFromFile` の対応フォーマット確認: wav / m4a / mp3(設計未決事項1)
- [ ] ロケール指定APIの有無確認、ja-JP 書き起こし確認(設計未決事項2)
- [ ] MSIX + `systemAIModels` capability の最小構成アプリで動作確認

### M0 出口判定

- [ ] 4プラットフォームの判定結果を requirements.md の対応表に反映(不成立項目は対象外化 or 構成変更)
- [ ] design.md の未決事項1〜6を確定値で更新

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

- [ ] androidパッケージ雛形、`genai-speech-recognition` 依存追加(バージョン固定)
- [ ] モデル管理: checkStatus → checkModel、download Flow → downloadModel進捗
- [ ] デコード層: MediaExtractor + MediaCodec → 16kHz/モノラル/16-bit PCM
- [ ] リサンプリング実装 or 対応入力の限定(M0調査結果に従う)
- [ ] 実時間ポンプ: PFDパイプ、壁時計基準レート制御(100msバッファ)
- [ ] 認識セッション: preferredMode設定、Flow → EventChannel転送、Basicリトライ(M0結果次第)
- [ ] キャンセル(パイプclose → stopRecognition → close)
- [ ] エラーマッピング(ブートローダーアンロック、AICoreエラー601/606)
- [ ] Pixel系 + 非Pixel系の2機種で基準音声E2E
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

- [ ] ML Kit alpha / Chrome / WinAppSDK / OSベータの変更監視(四半期ごとに基準音声E2E再実行)
- [ ] 破壊的変更時の追従とバージョン固定更新
- [ ] 将来拡張の検討: タイムスタンプ、マイク入力、同時複数セッション
