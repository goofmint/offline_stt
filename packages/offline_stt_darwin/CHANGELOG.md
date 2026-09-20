# Changelog

## 0.1.0

初回リリース。iOS / macOS 共用の実装(design.md §4.2)。

### 追加

- モデル管理: `AssetInventory` によるロケール別のアセット照会・取得を
  `checkModel()` / `downloadModel()` に写像する。
- 文字起こし: `AVAudioFile(forReading:)` → `SpeechTranscriber(locale:preset:)`
  → `SpeechAnalyzer(modules:)` → `analyzeSequence(from:)` →
  `finalizeAndFinishThroughEndOfInput()` のパイプライン。
- partial(`isFinal: false`)/ final セグメントの逐次通知、購読キャンセル、
  design.md §5 Darwin列に沿ったエラー写像。
- セッション排他(design.md §3)は `TranscribeSessionGuard` で満たす。

### 既知の制約

- **iOSシミュレータでは動作しない。** `SpeechTranscriber.isAvailable` が
  `false` を返し、`supportedLocales` が0件になる。M0スパイクで、裸の実行
  ファイルと正しい .app バンドルの両方で同じ結果になることを確認済みで
  あり、原因は起動方法ではなくシミュレータにオンデバイス音声モデルが
  無いことである(spikes/darwin/RESULTS.md)。認識の検証には実機が要る。
- **`AssetInventory.status` と `installedLocales` は一致しないことがある。**
  モデルがディスク上に存在しても予約(reserve)されていなければ
  `.supported` が返る。macOS と iOS 実機の双方で再現したため SpeechAnalyzer
  の仕様である(spikes/darwin/RESULTS.md)。
- **認識精度は design.md §7 のしきい値に達していない。** M0スパイクの実測
  では基準音声8ファイル全てが不成立(ja-JP 28.6〜66.7%、en-US 44.0〜80.0%)
  であった。原因は未確定である。
- **実機E2Eは未実施である**(Issue #40)。iOS 26 実機での確認も残課題で
  ある(Issue #7。M0で使用できたのは iOS 27.0 実機であり、`supportedLocales`
  はOSバージョンで変動することが実測されているため外挿できない)。
