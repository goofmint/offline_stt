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

### Android(Issue #51)

`apps/example/android/` はリポジトリにコミット済みである(生成時点の Flutter 3.41.9 の
`flutter create . --platforms=android --org com.moongift` の出力に、
`app/build.gradle.kts` の `minSdk = 31` だけを加えたもの)。`flutter create`
を再実行する必要は無い。

```
cd apps/example
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  flutter build apk --debug
flutter run -d <実機のデバイスID>
```

**JDK 17 を明示する必要がある場合がある。** 検証に使ったマシンの既定JDKは
26.0.1 であり、同梱のKotlinコンパイラがそのバージョン文字列を解釈できず
`java.lang.IllegalArgumentException: 26.0.1` で失敗する。CIの Android ジョブ
が `actions/setup-java` で JDK 17 を用意しているのと同じ理由である
(`packages/offline_stt_android/android/build.gradle` の
`sourceCompatibility` は 17)。

## プラットフォームごとの注意

- **iOSシミュレータでは動作しない。** `SpeechTranscriber.isAvailable` が
  `false` になり、SpeechAnalyzerによる認識自体が利用できない
  (design.md §4.2)。文字起こしのE2E検証には実機が必要である。
- **Androidは実機が必要である。** バックエンドはAndroid標準の
  `android.speech.SpeechRecognizer`(オンデバイス)であり、エミュレータには
  オンデバイス認識のモデルが存在しない(ML Kit GenAI / AICore は使って
  いない。design.md §4.3)。また `minSdk` は 31 だが、モデル状態の判定に
  使う `checkRecognitionSupport()` がAPI 33 で追加されたAPIであるため、
  **API 31/32 では `checkModel()` が常に `unavailable` を返す。**
- **Androidは実時間方式であり、ファイル長と同等の時間がかかる。**
  デコード済みPCMを `ParcelFileDescriptor` パイプへ毎秒約32KBで供給する
  ためである(Pixel 6実機の実測: 9.56秒の音声にポンプ9,564ms、実効
  31,993.7バイト/秒)。バッチ認識の iOS / macOS とはこの点が
  根本的に異なるため、長時間の音声ではその長さ分だけ待つことになる。
  なお **`RECORD_AUDIO` 権限は不要である**(マイクを使わない)。
  詳細は `packages/offline_stt_android/README.md` と
  `packages/offline_stt_android/E2E_CHECKLIST.md` を参照。
- **Webは Chrome 142 以上でのみ動作する。** それ以外のブラウザでは
  モデル状態が「利用不可」になる(requirements.md §8)。`localhost` または
  `https` 配信であることも必要(`on-device-speech-recognition`
  Permissions Policy)。詳細な手動E2E手順は
  `packages/offline_stt_web/E2E_CHECKLIST.md` を参照。

**検証状況について**: 2026-09-21 に、本 app の `integration_test/` から
**本番実装に対する実機E2Eを Darwin(macOS 26.5.1 + iPad Pro / iOS 26.6.2)と
Android(Pixel 6)で実行した**(Issue #40 / #50。結果は
`packages/offline_stt_darwin/E2E_RESULTS.md` と
`packages/offline_stt_android/E2E_RESULTS.md`)。

ただし **`integration_test` は `OfflineTranscriberPlatform.instance` を直接
呼ぶため、本 app の UI 経路(ファイルピッカー → 同意ダイアログ → 進行表示)は
通っていない。** UI を通した確認は人手で別途行う必要がある。

Web は M0 スパイクでの実測のみで、本番実装での再測定は未実施である。

## モデルダウンロードの同意について

**同意なしに `downloadModel()` を呼んではならない**
(requirements.md FR-2・§8)。本appは `checkModel()` が `downloadable` を
返した場合のみダウンロードボタンを表示し、`download_consent_dialog.dart`
の同意ダイアログでユーザーが明示的に同意した場合のみ `downloadModel()` を
呼び出す。
