# Changelog

## 0.1.0

初回リリース。Web 実装(design.md §4.1)。Pigeon を使わず
`package:web` + `dart:js_interop` のみで構成する。

### 追加

- モデル管理: `SpeechRecognition.available()` / `install()` を
  `checkModel()` / `downloadModel()` に写像する。
- デコード層: Blob URL / ObjectURL → `fetch` → `AudioContext.decodeAudioData`
  → `AudioBufferSourceNode` → `MediaStreamAudioDestinationNode` →
  `audioTrack`。
- 文字起こし: `SpeechRecognition.start(audioTrack)` による認識と、partial /
  final セグメントの通知。`TranscribeRequest.playbackRate` に対応する
  (Web専用オプション)。
- CJKロケールでの確定テキストから、ブラウザ内部の形態素区切り空白を除去
  する。語間の空白が意味を持つ言語には適用しない。
- design.md §5 Web列に沿ったエラー写像。`network` は NFR-2 違反の兆候と
  して、コード名を保ったまま `PlatformException_` で伝播させる。

### 既知の制約

- **Chrome 142 以上のデスクトップ版でのみ動作する**(requirements.md NFR-4)。
  他のブラウザでは `checkModel()` が `unavailable` を返す。
- **`localhost` または https 配信が必要である。** `on-device-speech-recognition`
  Permissions Policy の既定値が `'self'` であるため、`file://` では動作
  しない。
- **`install()` は進捗を通知しない。** `DownloadProgress.fraction` は常に
  `null`(不定進捗)である。
- **CDP等の自動化制御下のクリーンな一時プロファイルではオーディオ
  レンダリングが動作しない実測がある**(spikes/web/RESULTS.md)。このため
  認識E2Eは自動CIに載せられず、手動チェックリスト運用としている
  (`E2E_CHECKLIST.md`)。
- **認識精度は design.md §7 のしきい値に達していない。** M0スパイクの実測
  では基準音声 jaJP_10s(1.0x)で包含率 66.7% であり不成立であった。原因は
  未確定である。
