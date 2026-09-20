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
- **Androidは実機が必要である。** バックエンドはAndroid標準の
  `android.speech.SpeechRecognizer`(オンデバイス)であり、エミュレータには
  オンデバイス認識のモデルが存在しない。また `minSdk` は 31 だが、モデル
  状態の判定に使う `checkRecognitionSupport()` がAPI 33 で追加された
  APIであるため、**API 31/32 では `checkModel()` が常に `unavailable` を
  返す。** 詳細は `packages/offline_stt_android/E2E_CHECKLIST.md` を参照。
- **Windowsは依存を書くだけでは動かない。** MSIXパッケージ化と
  `systemAIModels` capability の宣言、および `winapp init`(WinAppSDKの
  C++/WinRTプロジェクションヘッダー展開)が必要である。手順は
  `packages/offline_stt_windows/README.md` と
  `apps/example/windows/packaging/README.md` にある。**このexample appを
  Windowsで動かした実績は無い**(リポジトリにWindows実機が無いため。
  Issue #58)。`flutter build windows --debug` によるコンパイル検証のみ
  CIで行っている。
- **Webは Chrome 142 以上でのみ動作する。** それ以外のブラウザでは
  モデル状態が「利用不可」になる(requirements.md §8)。`localhost` または
  `https` 配信であることも必要(`on-device-speech-recognition`
  Permissions Policy)。詳細な手動E2E手順は
  `packages/offline_stt_web/E2E_CHECKLIST.md` を参照。

**検証状況について**: Android / iOS / macOS / Windows / Web のいずれについて
も、**本appを使って実機E2Eチェックリストを通して実行した実績は無い**
(`E2E_CHECKLIST.md` の「実行実績」欄を参照)。ローカルでビルド成功を確認
しているのは web / macOS / iOS の3つであり、android / windows はCIの
コンパイル検証のみである。実機E2Eは Issue #40(Darwin)/ #50(Android)/
#58(Windows)の対象である。

## モデルダウンロードの同意について

**同意なしに `downloadModel()` を呼んではならない**
(requirements.md FR-2・§8)。本appは `checkModel()` が `downloadable` を
返した場合のみダウンロードボタンを表示し、`download_consent_dialog.dart`
の同意ダイアログでユーザーが明示的に同意した場合のみ `downloadModel()` を
呼び出す。
