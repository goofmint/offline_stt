#!/usr/bin/env bash
#
# generate.sh — 基準音声セット生成スクリプト
#
# test-assets/baseline-audio/scripts/ の読み上げスクリプトから、
# macOS の `say` コマンドでTTS音声を生成し、`ffmpeg` で
# 16kHz / モノラル / 16-bit PCM の WAV に変換する。
# WAV から AAC 128kbps の M4A を派生させ、`ffprobe` で仕様を検証、
# 各ファイルの sha256 を算出して .json に書き込む。
#
# 前提: macOS (say コマンド) + ffmpeg / ffprobe (Homebrew等)
# 冪等性: 既存の生成物は再計算して上書きする(スクリプト内容を変更した場合も再実行可能)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# ---------------------------------------------------------------------------
# 0. 依存コマンドの存在チェック
# ---------------------------------------------------------------------------
for cmd in say ffmpeg ffprobe shasum; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: 必須コマンド '${cmd}' が見つかりません。インストールしてから再実行してください。" >&2
    exit 1
  fi
done

# 音声(voice)の存在チェック
if ! say -v '?' | awk '{print $1}' | grep -qx "Kyoko"; then
  echo "ERROR: 音声 'Kyoko' (ja_JP) が見つかりません。システム環境設定でインストールしてください。" >&2
  exit 1
fi
if ! say -v '?' | awk '{print $1}' | grep -qx "Samantha"; then
  echo "ERROR: 音声 'Samantha' (en_US) が見つかりません。システム環境設定でインストールしてください。" >&2
  exit 1
fi

echo "== 依存コマンド / 音声の確認OK =="

# ---------------------------------------------------------------------------
# 1. 生成対象の定義
#    id: {locale}_{duration} 形式のベース名
#    voice: sayの音声名
#    rate: sayの読み上げ速度(-r)。10s/3mの目標長に収まるよう実測で調整済み
#    min/max: ffprobeで検証する許容長(秒)
# ---------------------------------------------------------------------------
IDS=(jaJP_10s jaJP_3m enUS_10s enUS_3m)

voice_for() {
  case "$1" in
    jaJP_*) echo "Kyoko" ;;
    enUS_*) echo "Samantha" ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

locale_for() {
  case "$1" in
    jaJP_*) echo "ja-JP" ;;
    enUS_*) echo "en-US" ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

rate_for() {
  case "$1" in
    jaJP_10s) echo 240 ;;
    jaJP_3m)  echo 240 ;;
    enUS_10s) echo 175 ;;
    enUS_3m)  echo 175 ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

min_sec_for() {
  case "$1" in
    *_10s) echo 8 ;;
    *_3m)  echo 165 ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

max_sec_for() {
  case "$1" in
    *_10s) echo 13 ;;
    *_3m)  echo 195 ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

# キーワードリスト(評価用)。design.md §7「評価基準(キーワード包含率)」の対象。
# 各キーワードは対応するscripts/配下のスクリプト本文から逐語で選定した
# 意味上重要な名詞・固有名詞・数値・専門用語。
#
# 1行 = 1キーワードグループ(包含率の分母は「グループ数」であり表記数ではない)。
# 表記が複数あり得るものは、同一行内をタブ区切りで許容表記を列挙する。
# いずれか1つに一致すれば当該グループを一致とみなす(design.md §7)。
# 列挙してよいのは「同じ内容の別表記」に限る。認識器が出したというだけの
# 誤認識(例: ISO 2701、モンギフト)を足してはならない。
# 各表記の選定理由は README.md「許容表記の一覧と選定理由」に記載する。
keywords_for() {
  local TAB=$'\t'
  case "$1" in
    jaJP_10s)
      printf '%s\n' \
        "東京都渋谷区" \
        "2024年11月3日${TAB}2024/11/3${TAB}2024-11-03" \
        "午後3時${TAB}15時" \
        "株式会社モーンギフト" \
        "新製品" \
        "128名"
      ;;
    jaJP_3m)
      printf '%s\n' \
        "東京都渋谷区" \
        "2024年11月3日${TAB}2024/11/3${TAB}2024-11-03" \
        "渋谷ヒカリエ" \
        "128名" \
        "モジトルCore${TAB}モジトルコア" \
        "月額980円" \
        "田中健一" \
        "2019年" \
        "32万人${TAB}320,000人" \
        "佐藤美咲" \
        "10分間" \
        "45秒" \
        "96.4パーセント${TAB}96.4%" \
        "98.1パーセント${TAB}98.1%" \
        "12言語${TAB}十二言語" \
        "20言語${TAB}二十言語" \
        "大阪府" \
        "月間5000件" \
        "2025年2月15日${TAB}2025/2/15${TAB}2025-02-15" \
        "名古屋市" \
        "サンフランシスコ" \
        "3億円" \
        "ベルリン" \
        "山田健太" \
        "ISO27001" \
        "月額4980円" \
        "鈴木一郎" \
        "18名"
      ;;
    enUS_10s)
      printf '%s\n' \
        "San Francisco" \
        "November 3rd, 2024${TAB}November 3, 2024${TAB}11/3/2024" \
        "3 PM${TAB}3:00 PM" \
        "Moongift Incorporated${TAB}Moongift Inc." \
        "128${TAB}one hundred twenty eight${TAB}one hundred and twenty eight"
      ;;
    enUS_3m)
      printf '%s\n' \
        "San Francisco" \
        "Salesforce Tower" \
        "November 3rd, 2024${TAB}November 3, 2024${TAB}11/3/2024" \
        "Kenichi Tanaka" \
        "2019" \
        "three hundred and twenty thousand${TAB}three hundred twenty thousand${TAB}320,000" \
        "Misaki Sato" \
        "forty five seconds${TAB}45 seconds" \
        "ninety six point four percent${TAB}96.4%" \
        "ninety eight point one percent${TAB}98.1%" \
        "twelve languages${TAB}12 languages" \
        "twenty languages${TAB}20 languages" \
        "Chicago" \
        "five thousand${TAB}5,000" \
        "February 15th, 2025${TAB}February 15, 2025${TAB}2/15/2025" \
        "Austin, Texas${TAB}Austin, TX" \
        "Berlin, Germany" \
        "three million dollars${TAB}\$3 million" \
        "Kenta Yamada" \
        "ISO 27001" \
        "Ichiro Suzuki" \
        "eighteen${TAB}18 people" \
        "Montgomery Street" \
        "November 10th, 2024${TAB}November 10, 2024${TAB}11/10/2024" \
        "forty two engineers${TAB}42 engineers"
      ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

# JSON文字列エスケープ(バックスラッシュ・ダブルクォート・改行)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

# ---------------------------------------------------------------------------
# 2. 生成本体
# ---------------------------------------------------------------------------
for id in "${IDS[@]}"; do
  echo ""
  echo "== 生成中: ${id} =="

  script_txt="${SCRIPTS_DIR}/${id}.txt"
  if [[ ! -f "${script_txt}" ]]; then
    echo "ERROR: 読み上げスクリプトが見つかりません: ${script_txt}" >&2
    exit 1
  fi

  voice="$(voice_for "${id}")"
  locale="$(locale_for "${id}")"
  rate="$(rate_for "${id}")"
  min_sec="$(min_sec_for "${id}")"
  max_sec="$(max_sec_for "${id}")"

  aiff_path="${WORK_DIR}/${id}.aiff"
  wav_path="${OUT_DIR}/${id}.wav"
  m4a_path="${OUT_DIR}/${id}.m4a"
  txt_path="${OUT_DIR}/${id}.txt"
  json_path="${OUT_DIR}/${id}.json"

  # 2-1. TTS生成 (aiff)
  say -v "${voice}" -r "${rate}" -f "${script_txt}" -o "${aiff_path}"

  # 2-2. WAV変換: 16kHz / モノラル / 16-bit PCM (pcm_s16le)
  ffmpeg -y -loglevel error -i "${aiff_path}" \
    -ar 16000 -ac 1 -c:a pcm_s16le "${wav_path}"

  # 2-3. M4A派生: AAC 128kbps / 16kHz / モノラル
  ffmpeg -y -loglevel error -i "${wav_path}" \
    -c:a aac -b:a 128k -ar 16000 -ac 1 "${m4a_path}"

  # 2-4. 期待テキスト(全文)をコピー
  cp "${script_txt}" "${txt_path}"

  # 2-5. ffprobeによる仕様検証 (WAV)
  wav_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "${wav_path}")
  wav_channels=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "${wav_path}")
  wav_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${wav_path}")
  wav_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${wav_path}")

  if [[ "${wav_rate}" != "16000" ]]; then
    echo "ERROR: ${wav_path} のサンプルレートが16000ではありません (実際: ${wav_rate})" >&2
    exit 1
  fi
  if [[ "${wav_channels}" != "1" ]]; then
    echo "ERROR: ${wav_path} のチャンネル数が1ではありません (実際: ${wav_channels})" >&2
    exit 1
  fi
  if [[ "${wav_codec}" != "pcm_s16le" ]]; then
    echo "ERROR: ${wav_path} のコーデックがpcm_s16leではありません (実際: ${wav_codec})" >&2
    exit 1
  fi
  if (( $(echo "${wav_duration} < ${min_sec} || ${wav_duration} > ${max_sec}" | bc -l) )); then
    echo "ERROR: ${wav_path} の長さが許容範囲外です (実際: ${wav_duration}秒 / 許容: ${min_sec}〜${max_sec}秒)" >&2
    exit 1
  fi
  echo "  WAV OK: rate=${wav_rate} channels=${wav_channels} codec=${wav_codec} duration=${wav_duration}s"

  # 2-6. ffprobeによる仕様検証 (M4A)
  m4a_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "${m4a_path}")
  m4a_channels=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "${m4a_path}")
  m4a_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${m4a_path}")
  m4a_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${m4a_path}")

  if [[ "${m4a_rate}" != "16000" ]]; then
    echo "ERROR: ${m4a_path} のサンプルレートが16000ではありません (実際: ${m4a_rate})" >&2
    exit 1
  fi
  if [[ "${m4a_channels}" != "1" ]]; then
    echo "ERROR: ${m4a_path} のチャンネル数が1ではありません (実際: ${m4a_channels})" >&2
    exit 1
  fi
  if [[ "${m4a_codec}" != "aac" ]]; then
    echo "ERROR: ${m4a_path} のコーデックがaacではありません (実際: ${m4a_codec})" >&2
    exit 1
  fi
  if (( $(echo "${m4a_duration} < ${min_sec} || ${m4a_duration} > ${max_sec}" | bc -l) )); then
    echo "ERROR: ${m4a_path} の長さが許容範囲外です (実際: ${m4a_duration}秒 / 許容: ${min_sec}〜${max_sec}秒)" >&2
    exit 1
  fi
  echo "  M4A OK: rate=${m4a_rate} channels=${m4a_channels} codec=${m4a_codec} duration=${m4a_duration}s"

  # 2-7. sha256算出(正本であるWAVを対象とする)
  wav_sha256=$(shasum -a 256 "${wav_path}" | awk '{print $1}')

  # 2-8. JSON生成
  # 本jsonは {locale}_{duration} 単位(wav/m4a共通)のメタデータを表す。
  # sample_rate / channels / encoding / sha256 は正本であるWAVの値。
  transcript="$(cat "${txt_path}")"
  transcript_escaped="$(json_escape "${transcript}")"
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # 1行 = 1キーワードグループ。タブ区切りで複数表記があるものはJSON配列として
  # 出力する(単一表記は従来どおり文字列)。読み出し側(keyword_score.py /
  # spikes/*/KeywordScoring.*)は文字列・配列の双方を受け付ける。
  keywords_json=""
  while IFS= read -r kw_group; do
    group_json=""
    while IFS= read -r variant; do
      variant_escaped="$(json_escape "${variant}")"
      if [[ -z "${group_json}" ]]; then
        group_json="\"${variant_escaped}\""
      else
        group_json="${group_json}, \"${variant_escaped}\""
      fi
    done < <(printf '%s\n' "${kw_group}" | tr '\t' '\n')
    # 表記が1つだけならスカラー、複数なら配列として出力する
    if [[ "${kw_group}" == *$'\t'* ]]; then
      group_json="[${group_json}]"
    fi
    if [[ -z "${keywords_json}" ]]; then
      keywords_json="${group_json}"
    else
      keywords_json="${keywords_json}, ${group_json}"
    fi
  done < <(keywords_for "${id}")

  cat > "${json_path}" <<JSON
{
  "locale": "${locale}",
  "transcript": "${transcript_escaped}",
  "keywords": [${keywords_json}],
  "tool": "say+ffmpeg",
  "voice": "${voice}",
  "sample_rate": 16000,
  "channels": 1,
  "encoding": "pcm_s16le",
  "generated_at": "${generated_at}",
  "sha256": "${wav_sha256}"
}
JSON

  echo "  JSON生成完了: ${json_path}"
done

echo ""
echo "== 全ファイルの生成・検証が完了しました =="
