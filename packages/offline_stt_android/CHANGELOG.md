# Changelog

## 0.1.0

初回リリース。Android 実装(Kotlin)。

### 追加

- モデル管理: `SpeechRecognizer.checkRecognitionSupport()` が返す
  `RecognitionSupport` の4リストを突き合わせて `ModelState` の4値へ写像
  する。取得は `SpeechRecognizer.triggerModelDownload()` で行う。
- デコード: `MediaExtractor` / `MediaCodec` によるデコードと、16kHz・
  モノラル・16-bit PCM へのリサンプリング。
- 文字起こし: `ParcelFileDescriptor.createPipe()` + 実時間ポンプで PCM を
  送り込み、`RecognizerIntent.EXTRA_AUDIO_SOURCE` 経由で
  `SpeechRecognizer.createOnDeviceSpeechRecognizer()` に渡す。
  `EXTRA_PREFER_OFFLINE=true`。`RECORD_AUDIO` 権限は要求しない。
- partial / final セグメントの通知、キャンセル(パイプclose →
  `stopListening()` → `destroy()`)、requirements.md FR-6 に沿ったエラー写像。

### 既知の制約

- **バックエンドは Android 標準の `android.speech.SpeechRecognizer` である。**
  当初設計の ML Kit GenAI Speech Recognition は AICore を必要とするが、
  M0検証で使用した Pixel 6 実機の AICore は `versionName` が
  `0.stub.stub_aicore_...` の stub 版であり、`checkStatus()` /
  `startRecognition()` がいずれも `PERMISSION_DENIED: Api access revoked.`
  を返した。Google Play ストア自身が Pixel 6 を非対応と明示している
  (spikes/android/RESULTS.md)。
- **`ModelDownloadListener` のコールバックは完了を通知しない実測がある。**
  M0検証では `onSuccess()` が一度も観測できず、`onScheduled()` のみが
  発火した(2回目の実行ではそれすら発火しなかった)。一方で
  `installedOnDeviceLanguages` にはロケールが現れており、ダウンロード自体は
  成立していた。このためネイティブ実装は完了判定を
  `checkRecognitionSupport()` の再照会で行う。
- **`onResults()` の確定テキストが `null` になる現象がある。** M0検証では
  `onPartialResults()` は台本どおりに伸びていったが、パイプの EOF 直後に
  発火する `onResults()` は `RESULTS_RECOGNITION` を返さなかった。2回の
  独立した実行で再現しており、`stopListening()` の有無とは無関係だった。
  **原因は未特定である**(spikes/android/RESULTS.md)。
- **`TranscribeRequest.playbackRate` は無視される**(Web専用オプション、
  design.md §2.2)。
- **M0検証は Pixel 6 単一機種でのみ行っている。** 他機種・他OSバージョンの
  挙動、およびキャンセル経路は未検証である。実機E2Eは Issue #50。
- **認識精度は design.md §7 のしきい値に達していない。** M0検証では基準
  音声 jaJP_10s で包含率 66.7% であり不成立であった(確定テキストが
  得られなかったため最終 partial テキストでの代用値)。原因は未確定である。
