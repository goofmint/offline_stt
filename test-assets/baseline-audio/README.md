# baseline-audio — 基準音声セット

Flutterライブラリ「オフライン音声ファイル文字起こし」の M0 検証、および後続マイルストーン(M1〜M4)の実機E2E検証、公開後の四半期回帰(tasks.md「継続タスク」参照)で共通利用する基準音声・期待テキスト資産。

## ディレクトリ構成

```
test-assets/baseline-audio/
├── README.md              … 本ファイル
├── generate.sh             … 音声生成スクリプト(要 実行権限)
├── scripts/                 … TTS読み上げ用スクリプト本文(生成の入力)
│   ├── jaJP_10s.txt
│   ├── jaJP_3m.txt
│   ├── enUS_10s.txt
│   └── enUS_3m.txt
├── jaJP_10s.wav / .m4a / .txt / .json
├── jaJP_3m.wav  / .m4a / .txt / .json
├── enUS_10s.wav / .m4a / .txt / .json
└── enUS_3m.wav  / .m4a / .txt / .json
```

## 命名規約

`{locale}_{duration}.{ext}` 形式。

- `locale`: `jaJP` / `enUS`(ハイフンなし)
- `duration`: `10s` / `3m`
- `ext`: `wav` / `m4a` / `txt` / `json`

例: `jaJP_10s.wav`、`enUS_3m.m4a`

## 音声仕様

- WAVを正本とする: **16kHz・モノラル・16-bit PCM (pcm_s16le)**
  - design.md §4.3 のAndroid内部デコード目標(MediaCodec出力後のターゲット形式)と一致させている
- M4AはWAVからの派生: **AAC, 128kbps指定, 16kHz, モノラル**
  - 備考: FFmpegのネイティブAACエンコーダは16kHz・モノラルの組み合わせでは1フレームあたりのビット割当上限により128kbpsを維持できず、自動的に約96kbps相当(実測平均ビットレートは約75〜80kbps)にクランプされる(`Too many bits ... clamping to max` 警告)。サンプルレート・チャンネル数・コーデックの仕様(16kHz/モノラル/AAC)自体は満たしている。
- 長さの許容範囲: 10秒版は8〜13秒、3分版は165〜195秒(厳密一致は不要)

## 期待テキストの構成(.txt / .json)

各基準音声ファイルの期待テキストは以下の2要素で構成される(design.md §7参照)。

1. **全文文字起こし**(`{id}.txt`): 読み上げスクリプト(`scripts/{id}.txt`)と同一内容。UTF-8。
2. **評価用キーワードリスト**(`{id}.json` の `keywords` 配列): 意味上重要な名詞・固有名詞・数値・専門用語から選定。10秒版は5件以上、3分版は15件以上を目安とする。

`{id}.json` に含まれるキー:

| キー | 内容 |
|---|---|
| `locale` | BCP-47ロケール(`ja-JP` / `en-US`) |
| `transcript` | 全文文字起こし(`{id}.txt` と同一) |
| `keywords` | 評価用キーワード配列 |
| `tool` | 生成に使用したツール(`say+ffmpeg`) |
| `voice` | TTS音声名(`Kyoko` / `Samantha`) |
| `sample_rate` | サンプルレート(Hz、WAV基準) |
| `channels` | チャンネル数(WAV基準) |
| `encoding` | エンコーディング(WAV基準、`pcm_s16le`) |
| `generated_at` | 生成日時(UTC, ISO8601) |
| `sha256` | 正本WAVファイルのSHA-256 |

キーワード包含率による判定基準(算出式・正規化ルール・しきい値)は design.md §7「評価基準(キーワード包含率)」を参照。

## generate.sh の実行方法

### 前提

- macOS(`say` コマンドを使用)
- Homebrew等で導入した `ffmpeg` / `ffprobe`
- `say -v Kyoko` (ja_JP) および `say -v Samantha` (en_US) の音声がインストール済みであること(`say -v '?'` で確認可能。未インストールの場合はシステム環境設定 > アクセシビリティ > 読み上げコンテンツ、等からダウンロード)

### 実行

```bash
bash test-assets/baseline-audio/generate.sh
```

- `scripts/` 配下の読み上げスクリプトから `say` でTTS生成(aiff) → `ffmpeg` でWAV変換 → WAVからM4Aを派生 → `ffprobe` で仕様(サンプルレート・チャンネル数・コーデック・長さ)を検証 → SHA-256算出 → `.txt` / `.json` 出力、の順で処理する。
- `set -euo pipefail` を使用し、依存コマンド(`say` / `ffmpeg` / `ffprobe` / `shasum`)や音声の不足、生成物が仕様(サンプルレート・チャンネル数・コーデック・許容長)を満たさない場合は非ゼロで終了する。
- 冪等に再実行可能(既存の生成物を上書きする)。読み上げスクリプトの内容やパラメータ(`rate_for` 等)を変更した場合は再実行すればよい。

### 読み上げスクリプトの調整方針

10秒版・3分版とも、目標長への調整は基本的に `scripts/` 配下のスクリプト本文の分量で行う(文章を増減させる)。`generate.sh` 内の `rate_for()` で `say -r` の読み上げ速度を調整することも可能だが、まずは文章量での調整を優先する。3分版は10秒版の内容を含む・拡張する構成とし、キーワードが明確に含まれるようにする。

## この資産の再利用範囲

- **M0検証**: tasks.md「M0 検証スパイク」の各プラットフォーム(Web / Darwin / Android / Windows)でのja-JP文字起こし精度確認に使用する。
- **M1〜M4のE2E検証**: 各プラットフォーム実装のE2Eテスト(手動チェックリスト運用、design.md §7)で再利用する。
- **公開後の四半期回帰**: tasks.md「継続タスク」に記載の、ML Kit alpha / Chrome / WinAppSDK / OSベータ変更時の四半期ごとの基準音声E2E再実行で再利用する。

## design.md / tasks.md との差異(スコープ注記)

design.md §7 に記載の「30分・mp3」は本セット(M0スコープ)には含まれない。tasks.md の M0記述(10秒・3分、wav・m4a)に合わせたスコープとしている。30分版・mp3形式はM0スコープ外であり、後続マイルストーン(実運用に近い長時間音声での検証等)で別途整備する想定。
