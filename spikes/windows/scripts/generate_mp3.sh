#!/usr/bin/env bash
# generate_mp3.sh
#
# Issue #16(フォーマット受理テスト)用に、test-assets/baseline-audio/ の wav から
# mp3 版フィクスチャを生成する。design.mdは共通資産(test-assets/)のM0スコープを
# 変更しないと定めているため、生成物は test-assets/ の外(このスクリプトと同じ
# spikes/windows/fixtures/ 配下)に置く。
#
# 実行環境: macOS/Linuxでの実行を想定(ffmpegが必要)。生成したmp3ファイルは
# Windows実機の test-assets/baseline-audio/ 相当ディレクトリへ配置してから
# `windows-stt-spike format-test <clipId>` を実行すること(README参照)。
#
# 使い方:
#   cd spikes/windows
#   ./scripts/generate_mp3.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOWS_SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$WINDOWS_SPIKE_DIR/../.." && pwd)"
BASELINE_DIR="$REPO_ROOT/test-assets/baseline-audio"
OUT_DIR="$WINDOWS_SPIKE_DIR/fixtures/mp3"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg が見つかりません。'brew install ffmpeg' 等でインストールしてください。" >&2
  exit 1
fi

if [ ! -d "$BASELINE_DIR" ]; then
  echo "test-assets/baseline-audio が見つかりません: $BASELINE_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

for wav in "$BASELINE_DIR"/*.wav; do
  base="$(basename "$wav" .wav)"
  out="$OUT_DIR/$base.mp3"
  echo "generating: $out"
  # -qscale:a 2 は高品質側のVBR設定(FR-4のフォーマット受理テストの目的は
  # 「mp3コンテナ・コーデックとしてRecognizeFromFileに受理されるか」の確認であり、
  # 音質の厳密な作り込みは目的ではないため簡潔な設定にしている)。
  ffmpeg -y -i "$wav" -codec:a libmp3lame -qscale:a 2 "$out" -loglevel error
done

echo "done. 生成先: $OUT_DIR"
echo "Windows実機では、このディレクトリの *.mp3 を test-assets/baseline-audio/ 相当の"
echo "場所(--baseline-dir オプションで指定するディレクトリ)へコピーしてから"
echo "'windows-stt-spike format-test <clipId>' を実行すること。"
