#!/usr/bin/env bash
#
# generate-rate-fixtures.sh — Issue #14 実環境相当音源フィクスチャ生成スクリプト
#
# 対応Issue: #14 (MediaCodec デコード出力レート調査)。対応する設計: design.md §4.3, §8 未決事項6。
#
# 背景: test-assets/baseline-audio/ の基準音声は generate.sh により
# **16kHz・モノラルで生成されたもの**であり、これをデコードして16kHzが得られるのは当然で、
# 「リサンプリング不要」の結論は循環論法になる。実際のユーザー音源(ボイスメモ・会議録音等)は
# 44.1kHz/48kHzのステレオが一般的であり、そちらこそが調査対象である。本スクリプトは、
# test-assets/baseline-audio/jaJP_10s.wav (16kHz/モノラル) を入力として、ffmpeg で
# 実環境に近いサンプルレート・チャンネル数・コーデック/コンテナの組み合わせを生成する。
#
# 生成後、各ファイルを ffprobe で検証し、期待するサンプルレート/チャンネル数/コーデックと
# 一致しなければ非ゼロ終了する。
#
# 前提: ffmpeg / ffprobe (Homebrew等)
# 冪等性: 既存の生成物は再生成して上書きする(-y)。生成物はコミットしない
# (README.md 参照。基準音声から機械的に再生成できるため、リポジトリを肥大化させない)。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SRC_WAV="${REPO_ROOT}/test-assets/baseline-audio/jaJP_10s.wav"
OUT_DIR="${SCRIPT_DIR}/generated"

# ---------------------------------------------------------------------------
# 0. 依存コマンド・入力ファイルの存在チェック
# ---------------------------------------------------------------------------
for cmd in ffmpeg ffprobe; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: 必須コマンド '${cmd}' が見つかりません。インストールしてから再実行してください。" >&2
    exit 1
  fi
done

if [[ ! -f "${SRC_WAV}" ]]; then
  echo "ERROR: 入力音源が見つかりません: ${SRC_WAV}" >&2
  echo "  test-assets/baseline-audio/generate.sh を先に実行してください。" >&2
  exit 1
fi

echo "== 依存コマンド / 入力音源の確認OK (${SRC_WAV}) =="

mkdir -p "${OUT_DIR}"

# ---------------------------------------------------------------------------
# 1. 生成対象の定義
#    id (= 出力ファイル名) ごとに rate / channels / ffmpegエンコーダ / ffprobeで期待するcodec_name
#    を case文で引く (bash 3.2 でも動くよう連想配列を使わない。generate.shの方針を踏襲)。
# ---------------------------------------------------------------------------
IDS=(
  rate_44100_stereo.wav
  rate_48000_stereo.wav
  rate_44100_stereo.m4a
  rate_48000_stereo.m4a
  rate_44100_stereo.mp3
  rate_22050_mono.wav
  rate_8000_mono.wav
)

rate_for() {
  case "$1" in
    rate_44100_stereo.wav) echo 44100 ;;
    rate_48000_stereo.wav) echo 48000 ;;
    rate_44100_stereo.m4a) echo 44100 ;;
    rate_48000_stereo.m4a) echo 48000 ;;
    rate_44100_stereo.mp3) echo 44100 ;;
    rate_22050_mono.wav)   echo 22050 ;;
    rate_8000_mono.wav)    echo 8000 ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

channels_for() {
  case "$1" in
    rate_44100_stereo.wav) echo 2 ;;
    rate_48000_stereo.wav) echo 2 ;;
    rate_44100_stereo.m4a) echo 2 ;;
    rate_48000_stereo.m4a) echo 2 ;;
    rate_44100_stereo.mp3) echo 2 ;;
    rate_22050_mono.wav)   echo 1 ;;
    rate_8000_mono.wav)    echo 1 ;;
    *) echo "ERROR: 未知のID '$1'" >&2; exit 1 ;;
  esac
}

# ffmpeg の -c:a に渡すエンコーダ名
encoder_for() {
  case "$1" in
    *.wav) echo "pcm_s16le" ;;
    *.m4a) echo "aac" ;;
    *.mp3) echo "libmp3lame" ;;
    *) echo "ERROR: 未知の拡張子 '$1'" >&2; exit 1 ;;
  esac
}

# ffprobe の stream=codec_name として期待される値
expected_codec_for() {
  case "$1" in
    *.wav) echo "pcm_s16le" ;;
    *.m4a) echo "aac" ;;
    *.mp3) echo "mp3" ;;
    *) echo "ERROR: 未知の拡張子 '$1'" >&2; exit 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 2. 生成本体
# ---------------------------------------------------------------------------
for id in "${IDS[@]}"; do
  echo ""
  echo "== 生成中: ${id} =="

  rate="$(rate_for "${id}")"
  channels="$(channels_for "${id}")"
  encoder="$(encoder_for "${id}")"
  expected_codec="$(expected_codec_for "${id}")"
  out_path="${OUT_DIR}/${id}"

  case "${id}" in
    *.wav)
      ffmpeg -y -loglevel error -i "${SRC_WAV}" \
        -ar "${rate}" -ac "${channels}" -c:a "${encoder}" "${out_path}"
      ;;
    *.m4a)
      ffmpeg -y -loglevel error -i "${SRC_WAV}" \
        -ar "${rate}" -ac "${channels}" -c:a "${encoder}" -b:a 128k "${out_path}"
      ;;
    *.mp3)
      ffmpeg -y -loglevel error -i "${SRC_WAV}" \
        -ar "${rate}" -ac "${channels}" -c:a "${encoder}" -b:a 128k "${out_path}"
      ;;
  esac

  # -------------------------------------------------------------------------
  # 3. ffprobeによる仕様検証
  # -------------------------------------------------------------------------
  actual_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "${out_path}")
  actual_channels=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "${out_path}")
  actual_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${out_path}")

  if [[ "${actual_rate}" != "${rate}" ]]; then
    echo "ERROR: ${out_path} のサンプルレートが${rate}ではありません (実際: ${actual_rate})" >&2
    exit 1
  fi
  if [[ "${actual_channels}" != "${channels}" ]]; then
    echo "ERROR: ${out_path} のチャンネル数が${channels}ではありません (実際: ${actual_channels})" >&2
    exit 1
  fi
  if [[ "${actual_codec}" != "${expected_codec}" ]]; then
    echo "ERROR: ${out_path} のコーデックが${expected_codec}ではありません (実際: ${actual_codec})" >&2
    exit 1
  fi

  echo "  OK: rate=${actual_rate} channels=${actual_channels} codec=${actual_codec} -> ${out_path}"
done

echo ""
echo "== 全ファイルの生成・検証が完了しました (出力先: ${OUT_DIR}) =="
echo "== 生成物はコミットしないこと(README.md参照)。基準音声から再実行すれば再生成できる。 =="
