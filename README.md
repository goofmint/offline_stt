# offline_stt

録音済み音声ファイルを、OSネイティブの音声認識APIのみでオフライン文字起こしするFlutterライブラリ(モノレポ)。詳細な要件・設計は [requirements.md](./requirements.md) / [design.md](./design.md) / [tasks.md](./tasks.md) を参照。

このREADMEは最小限の構成案内のみを記載する。本格的なREADME(対応状況マトリクス等)はIssue #60〜#62で整備する。

## モノレポ構成

**Melos + Dart Pub Workspaces**(Melos 8系)を採用している。ルート `pubspec.yaml` の `workspace:` キーで全パッケージを列挙し、`melos:` キーにMelosのスクリプト定義を集約している(`melos.yaml` は使わない)。

```
offline_stt/
├── pubspec.yaml                          … workspace定義 + melos設定
├── packages/
│   ├── offline_stt/                      … エントリパッケージ(利用者はこれのみに依存)
│   ├── offline_stt_platform_interface/   … 共通抽象・データ型・例外(純Dart)
│   ├── offline_stt_android/              … Kotlin実装(ML Kit GenAI Speech Recognition)
│   ├── offline_stt_darwin/               … Swift実装(iOS/macOS共用、SpeechAnalyzer)
│   ├── offline_stt_windows/              … C++/WinRT実装(Windows AI Speech Recognition)
│   └── offline_stt_web/                  … Dart JS interop実装(Web Speech API)
└── apps/
    └── example/                          … example app
```

federated pluginのエンドースメント構成(`offline_stt` の `flutter.plugin.platforms` で各プラットフォームに `default_package` を指定し、各実装パッケージは `implements: offline_stt` を宣言)は requirements.md §6 / design.md §1 に従っている。

## セットアップ・コマンド

```bash
# 依存解決(初回・依存追加時)
melos bootstrap
# または Dart Pub Workspaces のみで: dart pub get

# 全パッケージの静的解析
melos run analyze

# test/ を持つパッケージでユニットテストを実行
melos run test
```

`melos` は `~/.pub-cache/bin/melos` にインストールされている想定。PATHに無ければフルパスで実行する。

## 現状

本リポジトリはM1(基盤 + Web実装、tasks.md参照)の初期段階であり、`offline_stt_platform_interface` 以外の各実装パッケージは雛形(`UnimplementedError` を送出するプレースホルダー)のみである。
