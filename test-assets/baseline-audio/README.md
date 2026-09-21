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
2. **評価用キーワードリスト**(`{id}.json` の `keywords` 配列): 意味上重要な名詞・固有名詞・数値・専門用語から選定。10秒版は5件以上、3分版は15件以上を目安とする。表記揺れが起こりうるキーワード(日付・数値等)は許容表記を列挙してよく、いずれか1つに一致すれば当該キーワードを一致とみなす(design.md §7 参照)。スキーマは次節のとおり。

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

### `keywords` のスキーマ(文字列 または 許容表記の配列)

`keywords` は**キーワードグループの配列**である。1要素が1グループであり、要素は次の2形式のいずれかを取る。

| 形式 | 意味 | 例 |
|---|---|---|
| 文字列 | 表記が1つだけのキーワード | `"東京都渋谷区"` |
| 文字列の配列 | 許容表記を列挙したキーワード | `["2024年11月3日", "2024/11/3", "2024-11-03"]` |

- グループ内の**いずれか1表記が一致すれば、そのグループを一致**とみなす。
- **包含率の分母はグループ数であり、表記数ではない。** 表記を足しても分母は増えない。
- 文字列形式は要素数1の配列と等価であり、両形式は同一ファイル内で混在してよい。
- 読み出し側(`test-assets/keyword_score.py`、`spikes/darwin/.../KeywordScoring.swift`、`spikes/android/.../BaselineClip.kt`、`spikes/web/spike.js`)はいずれも両形式を受け付ける。

```json
"keywords": ["東京都渋谷区", ["2024年11月3日", "2024/11/3", "2024-11-03"], "新製品"]
```

**列挙してよいのは「同じ内容を別の表記で書いたもの」だけである。** 認識器がそう出力したというだけの誤認識を足してはならない(design.md §7)。

### 許容表記の一覧と選定理由

各表記は「同じ内容の別表記であること」を根拠に列挙した。正規化(NFKC → 小文字化 → 記号・空白除去)で吸収される差(`ISO 27001` と `ISO27001`、`November 3rd, 2024` と `November 3rd 2024`、`5,000` と `5000` など)は列挙不要のため載せていない。

| クリップ | 基準表記 | 追加した許容表記 | 選定理由 |
|---|---|---|---|
| jaJP_10s / jaJP_3m | `2024年11月3日` | `2024/11/3`、`2024-11-03` | 同一日付の区切り記号違い(design.md §7 が明示する例) |
| jaJP_10s | `午後3時` | `15時` | 12時間制と24時間制の同一時刻 |
| jaJP_3m | `モジトルCore` | `モジトルコア` | 製品名末尾 `Core` のラテン文字表記とカタカナ表記 |
| jaJP_3m | `32万人` | `320,000人` | 万単位表記と位取り表記。同じ数 |
| jaJP_3m | `96.4パーセント` | `96.4%` | 「パーセント」と記号 `%`。記号は正規化で除去されるため正規形は `964` |
| jaJP_3m | `98.1パーセント` | `98.1%` | 同上(正規形 `981`) |
| jaJP_3m | `12言語` | `十二言語` | 算用数字と漢数字 |
| jaJP_3m | `20言語` | `二十言語` | 算用数字と漢数字 |
| jaJP_3m | `2025年2月15日` | `2025/2/15`、`2025-02-15` | 同一日付の区切り記号違い |
| enUS_10s / enUS_3m | `November 3rd, 2024` | `November 3, 2024`、`11/3/2024` | 序数表記の有無、および数字形式の日付 |
| enUS_10s | `3 PM` | `3:00 PM` | 同一時刻の表記差 |
| enUS_10s | `Moongift Incorporated` | `Moongift Inc.` | `Incorporated` の一般的な省略形 |
| enUS_10s | `128` | `one hundred twenty eight`、`one hundred and twenty eight` | 算用数字と英単語綴り(`and` の有無は英語綴りの通常の揺れ) |
| enUS_3m | `three hundred and twenty thousand` | `three hundred twenty thousand`、`320,000` | `and` の有無、および数字表記。`320 000` も空白除去で `320000` となり同一 |
| enUS_3m | `forty five seconds` | `45 seconds` | 英単語綴りと算用数字 |
| enUS_3m | `ninety six point four percent` | `96.4%` | 英単語綴りと数字+記号表記 |
| enUS_3m | `ninety eight point one percent` | `98.1%` | 同上 |
| enUS_3m | `twelve languages` | `12 languages` | 英単語綴りと算用数字 |
| enUS_3m | `twenty languages` | `20 languages` | 同上 |
| enUS_3m | `five thousand` | `5,000` | 同上 |
| enUS_3m | `February 15th, 2025` | `February 15, 2025`、`2/15/2025` | 序数表記の有無、および数字形式の日付 |
| enUS_3m | `Austin, Texas` | `Austin, TX` | 州名の標準略号 |
| enUS_3m | `three million dollars` | `$3 million` | 英単語綴りと通貨記号表記 |
| enUS_3m | `eighteen` | `18 people` | 算用数字表記。`18` 単体は2文字で偶然一致の危険があるため、読み上げ本文どおり `18 people` とした(より狭い一致条件であり率を過大にしない) |
| enUS_3m | `November 10th, 2024` | `November 10, 2024`、`11/10/2024` | 序数表記の有無、および数字形式の日付 |
| enUS_3m | `forty two engineers` | `42 engineers` | 英単語綴りと算用数字 |

#### 列挙しなかったもの(誤認識であるため)

実測で認識結果に現れたが、**表記差ではなく誤認識**であるため許容表記に加えなかったもの。

| 基準表記 | 認識結果 | 加えなかった理由 |
|---|---|---|
| `ISO27001` / `ISO 27001` | `ISO 2701`、`ISO 2万70001` | 桁の脱落・混入。数値そのものが違う |
| `株式会社モーンギフト` | `モンギフト`、`モーギフト`、`モギフト` | 長音が脱落しており固有名詞として別語 |
| `Moongift Incorporated` | `Moon Gifting Corporated` | 語形が違う誤認識 |
| `128名` | `102十 8名` | 数の聞き取り結果そのものが違う |
| `東京都渋谷区` | `東京都渋谷で` | 「区」の脱落 |
| `ninety eight point one percent` | `98.one%` | 数字と英単語の混在した誤出力であり、`98.1%` とは別物 |
| `渋谷ヒカリエ` | `渋谷光への` | 誤認識 |
| `96.4パーセント` ほか | (該当箇所が丸ごと欠落) | 脱落は表記差ではない |

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
