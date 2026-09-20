#!/usr/bin/env bash
# integration_test/android_baseline_e2e_test.dart が読む音声ファイルを
# Android 実機へ配置する(Issue #50 / packages/offline_stt_android/
# E2E_CHECKLIST.md)。
#
# ## 配置先とタイミング
# 配置先はアプリ専用外部ストレージ
# (/sdcard/Android/data/com.moongift.example/files/baseline-audio)である。
# Android 11 以降でもアプリ自身は実行時権限なしで読めるため、
# E2E_CHECKLIST.md の前提(RECORD_AUDIO 権限を付与しない)を崩さずに
# 検証できる。
#
# ただし **`flutter test integration_test/...` は実行の前後でアプリを
# インストール・アンインストールする**。アンインストール時にこのディレクトリ
# ごと消えるため、事前に push しても test 本体からは見えない(実測。
# ファイルが全て MISSING になる)。そのため本スクリプトは
#
#   1. アプリのディレクトリが現れる(= flutter test がインストールした)まで待つ
#   2. 音声ファイルを push する
#   3. 最後に READY という番兵ファイルを置く
#
# という順で動く。test 側は READY が現れるまで待ってから本体を実行する。
# したがって **本スクリプトは `flutter test` の直前にバックグラウンドで
# 起動しておく**。
#
# 使い方:
#   apps/example/tool/push_baseline_audio.sh &
#   JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
#     flutter test integration_test/android_baseline_e2e_test.dart -d <device-id>
#
# 第1引数で adb のパスを指定できる(既定:
# ~/Library/Android/sdk/platform-tools/adb)。
set -euo pipefail

ADB="${1:-$HOME/Library/Android/sdk/platform-tools/adb}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$REPO_ROOT/test-assets/baseline-audio"
STAGE="$(mktemp -d)"
APP_DIR="/sdcard/Android/data/com.moongift.example"
DEST="$APP_DIR/files/baseline-audio"

trap 'rm -rf "$STAGE"' EXIT

for name in jaJP_10s jaJP_3m enUS_10s enUS_3m; do
  cp "$SRC/$name.wav" "$SRC/$name.m4a" "$STAGE/"
done

# E2E_CHECKLIST.md 手順3の3.(リサンプリング経路の確認)。基準音声は
# 16kHz・モノラルで生成されているため、そのままではリサンプラを通らない。
# 実環境相当(48kHz / 44.1kHz・ステレオ・AAC)へ変換したものを併せて置く。
ffmpeg -nostdin -loglevel error -y -i "$SRC/jaJP_10s.wav" \
  -ar 48000 -ac 2 -c:a aac "$STAGE/jaJP_10s_48k_stereo.m4a"
ffmpeg -nostdin -loglevel error -y -i "$SRC/enUS_10s.wav" \
  -ar 44100 -ac 2 -c:a aac "$STAGE/enUS_10s_44k1_stereo.m4a"

# E2E_CHECKLIST.md 手順6 DecodeFailedException: テキストファイルを .wav
# として渡す。
printf 'this is not audio\n' > "$STAGE/not_audio.wav"

# 配置先ディレクトリは test 本体(アプリ自身)が作る。adb shell が作った
# ディレクトリはアプリから読めない(実測: File.existsSync() が一貫して
# false を返した)。ここではディレクトリが現れるまで待つだけにする。
echo "test 側がディレクトリを作るのを待っている: $DEST"
for _ in $(seq 1 900); do
  if "$ADB" shell "test -d $DEST" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
"$ADB" shell "test -d $DEST"
for f in "$STAGE"/*; do
  "$ADB" push "$f" "$DEST/" >/dev/null
done
# 番兵は必ず最後に置く(test 側はこれを待つ)。
"$ADB" shell "echo ready > $DEST/READY"
"$ADB" shell ls -l "$DEST"
