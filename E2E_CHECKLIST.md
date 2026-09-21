# E2E 手動チェックリスト(総覧)

対応 Issue: #66。対応する設計: design.md §7「テスト戦略」。

design.md §7 は **「CI: ビルド検証のみ(Android/iOS/Windows/Webのコンパイル)。
認識E2Eは手動チェックリスト運用」** と定めている。本書はその手動チェック
リスト群の入口であり、**リリース前に人手で実行する検証手順**である。

## なぜ認識E2EをCIに載せないのか

プラットフォームごとに理由は異なるが、いずれも実測に基づく事実である。

| プラットフォーム | CIで実行できない理由 | 出典 |
|---|---|---|
| iOS / macOS | iOSシミュレータでは `SpeechTranscriber.isAvailable` が `false`、`supportedLocales` が0件になる。正しい .app バンドルでも同じ結果であり、原因はシミュレータにオンデバイス音声モデルが無いこと | spikes/darwin/RESULTS.md |
| Android | エミュレータではオンデバイス認識のモデルが無く、実機が要る。かつM0検証で、実機であっても機種によっては成立しないことが判明している | spikes/android/RESULTS.md |
| Web | CDP等の自動化制御下のクリーンな一時プロファイルではオーディオレンダリングが動作しない(`AudioContext.currentTime` が停止したまま進行しない)。通常の対話的Chromeセッションでのみ動作した | spikes/web/RESULTS.md |
| Windows | **Windows機が本リポジトリに存在しない。** CIはWinRTバックエンドを除外した構成しかコンパイルしない | spikes/windows/RESULTS.md、.github/workflows/ci.yml |

## プラットフォーム別チェックリスト

| プラットフォーム | チェックリスト | 実行実績 | 対応する実機E2E Issue |
|---|---|---|---|
| Web (Chrome) | [packages/offline_stt_web/E2E_CHECKLIST.md](packages/offline_stt_web/E2E_CHECKLIST.md) | M0スパイクで実測あり(本番実装での再測定は未実施) | — |
| iOS / macOS | [packages/offline_stt_darwin/E2E_CHECKLIST.md](packages/offline_stt_darwin/E2E_CHECKLIST.md) | **2026-09-21 に本番実装を macOS 26.5.1 と iPad Pro (iOS 26.6.2) で実行済み(手順1〜6は全て期待どおり。包含率は8ファイル全て未達)。[結果](packages/offline_stt_darwin/E2E_RESULTS.md)。iOS 27実機は未実施** | #40、#7(iOS 26実機) |
| Android | [packages/offline_stt_android/E2E_CHECKLIST.md](packages/offline_stt_android/E2E_CHECKLIST.md) | **2026-09-21 に本番実装をPixel 6で実行済み。初回は不合格(バグ4件を発見)、B-1〜B-4 修正後の最終実行は手順3が8/8成功。包含率は未達(enUS_10s のみ 100% で合格)。[結果](packages/offline_stt_android/E2E_RESULTS.md)。非Pixel機は未実施** | #50 |
| Windows | [packages/offline_stt_windows/E2E_CHECKLIST.md](packages/offline_stt_windows/E2E_CHECKLIST.md) | **全項目未実行。** Windows機が無く、ビルドすら一度も通していない | #58 |

**本番実装(`packages/` 配下)に対して通して実行したのは Android と
Darwin である(いずれも 2026-09-21。Pixel 6 / macOS 26.5.1 + iPad Pro
iOS 26.6.2)。** Web の「実測あり」は M0 スパイク(`spikes/` 配下の独立した
検証コード)での実測を指す。

## 全プラットフォーム共通の前提

### 基準音声

`test-assets/baseline-audio/` 配下を使う。

- クリップ: `jaJP_10s` / `jaJP_3m` / `enUS_10s` / `enUS_3m`
- 形式: `.wav` / `.m4a`(計8ファイル)
- 期待テキスト全文: 同名の `.txt`
- 評価用キーワードリスト: 同名の `.json` の `keywords`

**これらは `say` コマンドによるTTS合成音声である**(`generate.sh` 参照)。
人間の自然発話に対する精度は全プラットフォームで未検証である。

### キーワード包含率の算出(design.md §7)

包含率 = 一致キーワード数 ÷ 期待キーワード総数。一致判定の前に、**期待
キーワードと認識結果テキストの両方へ**同一の正規化を同一手順で適用する
(片側のみへの適用は禁止)。

1. Unicode NFKC 正規化
2. 小文字化
3. 句読点・記号の除去(Unicode 一般カテゴリ P と S)
4. 空白の除去
5. ja-JP のみ: ひらがな→カタカナの畳み込み

### しきい値(design.md §7)

| 条件 | 言語 | 合格しきい値 |
|---|---|---|
| クリーン基準音声 | ja-JP | 90%以上(90〜94%は「条件付き合格 / 要確認」) |
| クリーン基準音声 | en-US | 95%以上 |
| 実環境(ノイズあり、参考値) | 共通 | 上記から一律5ポイント程度緩和した値を参考とする |

### 精度に関する既知の事実(重要)

**実測できたプラットフォームはいずれもしきい値に達していない。**

| プラットフォーム | 基準音声 jaJP_10s の包含率 | 出典 |
|---|---|---|
| Darwin (macOS 26.5.1) | 66.7%(4/6) | spikes/darwin/RESULTS.md。**本番実装でも同値**(packages/offline_stt_darwin/E2E_RESULTS.md) |
| Darwin (iOS 26.6.2 実機) | 66.7%(4/6) | packages/offline_stt_darwin/E2E_RESULTS.md |
| Web (Chrome 153) | 66.7%(4/6) | spikes/web/RESULTS.md |
| Android (Pixel 6) | 66.7%(4/6) | spikes/android/RESULTS.md |
| Windows | 未測定 | — |

いずれも同率だが、落としているキーワードは同一ではない(Darwin の macOS と iOS 実機は内訳まで完全に一致した)。
**不成立の原因は未確定である。** design.md §7 が挙げる候補((a)基準音声が
TTS合成であること、(b)プリセット等の設定、(c)認識モデル自体の精度、
(d)キーワード選定と正規化規則が表記差を吸収できていないこと)のどれが
支配的かを分離する対照実験は行っていない。

したがって各チェックリストの包含率の項目は、**合否ゲートではなく記録
項目**として扱う。ただし design.md §7 の注記どおり、**原因未調査のまま
合格扱いにしてはならない**。

## 結果の記録

チェックリストを実行したら、実行日・検証環境(OS・端末・ブラウザ・SDKの
各バージョン)・項目ごとの結果を、対応するIssueへ記録する。

| プラットフォーム | 記録先 |
|---|---|
| Darwin(iOS / macOS) | #40 |
| Android | #50 |
| Windows | #58 |
| Web | **専用の実機E2E Issueが無い。** Web は #31(チェックリストの作成)と #66(収録)で扱っており、実行結果を記録するIssueが立っていない。実行する際は Web 用の検証Issueを新規に立て、その番号を本表へ追記すること |

**未実施の項目は「合格」ではなく「未実施」と書くこと。**
