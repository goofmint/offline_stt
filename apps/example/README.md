# offline_stt example

`offline_stt` の参照実装example app(Issue #32・#41)。requirements.md §8・
design.md §7が定める「ファイルピッカー → モデル状態表示 → ダウンロード
同意ダイアログ → 文字起こし進行表示」という一連の正しい使い方を示す。

対応する実装は `lib/main.dart` および `lib/src/` 配下を参照:

- `lib/src/home_page.dart`: 画面本体・状態管理(checkModel/downloadModel/
  transcribeFileの呼び出し方、セッション排他、キャンセル)
- `lib/src/download_consent_dialog.dart`: モデルダウンロード同意ダイアログ
  (requirements.md §8の文言ガイドラインに従う)
- `lib/src/transcribe_error_messages.dart`: `TranscribeException` の
  各サブクラスを区別したエラーメッセージ
- `lib/src/object_url.dart` / `object_url_web.dart` / `object_url_stub.dart`:
  Web専用のBlob URL(ObjectURL)生成(design.md §2.2)。条件付きexportで
  非Webビルドから除外する

## 実行方法

```
cd apps/example
flutter run -d macos   # または -d chrome 等
```

## プラットフォームごとの注意

- **iOSシミュレータでは動作しない。** `SpeechTranscriber.isAvailable` が
  `false` になり、SpeechAnalyzerによる認識自体が利用できない
  (design.md §4.2)。文字起こしのE2E検証には実機が必要である。
- **Android / Windows は未実装である(M3/M4で実装予定)。** `checkModel()`
  等は `UnimplementedError` を送出する。example appはこれを捕捉して
  「未対応である」旨を画面に表示するが、実際の認識は行えない。
- **Webは Chrome 142 以上でのみ動作する。** それ以外のブラウザでは
  モデル状態が「利用不可」になる(requirements.md §8)。`localhost` または
  `https` 配信であることも必要(`on-device-speech-recognition`
  Permissions Policy)。詳細な手動E2E手順は
  `packages/offline_stt_web/E2E_CHECKLIST.md` を参照。

## モデルダウンロードの同意について

**同意なしに `downloadModel()` を呼んではならない**
(requirements.md FR-2・§8)。本appは `checkModel()` が `downloadable` を
返した場合のみダウンロードボタンを表示し、`download_consent_dialog.dart`
の同意ダイアログでユーザーが明示的に同意した場合のみ `downloadModel()` を
呼び出す。
