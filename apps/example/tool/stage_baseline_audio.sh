#!/usr/bin/env bash
# integration_test/darwin_baseline_e2e_test.dart が読む音声ファイルを、
# example app の Flutter アセットとして配置する(Issue #40 /
# packages/offline_stt_darwin/E2E_CHECKLIST.md)。
#
# ## なぜ「Flutterアセット」なのか(Android の push 方式との違い)
#
# Android も同じアセット方式である(以前は adb push 方式だったが、
# push している。Darwin では同じ方式を採れない。
#
# - **macOS**: example app は App Sandbox 有効
#   (macos/Runner/DebugProfile.entitlements の
#   `com.apple.security.app-sandbox` = true)である。テストプロセスは
#   アプリ本体と同じサンドボックス内で動くため、リポジトリ配下の
#   `test-assets/` を直接 open できない。エンタイトルメントを緩めるのは
#   example app の構成を検証のために弱めることになるので採らない。
# - **iOS 実機**: ホストのファイルシステムが見えない。
#   `xcrun devicectl device copy to` でアプリのデータコンテナへ送る方式も
#   あるが、`flutter test` は実行のたびにアプリを入れ直すためコンテナごと
#   消える(Android で実測済み。packages/offline_stt_android/E2E_RESULTS.md
#   「この手順を実行するときの必須条件」参照)。
#   Android と同様に「インストールを待ってから送る」バックグラウンド
#   スクリプトを書くこともできるが、USB 経由で 15MB を送る時間と競合の
#   不確実さが増えるだけである。
#
# アセットとして .app へ焼き込めば、**macOS と iOS 実機で同一の経路**に
# なり、インストールのタイミングにも依存しない。テスト側は起動時に
# `rootBundle` から読み出してアプリのテンポラリディレクトリへ書き出し、
# その**実ファイルパス**を `TranscribeRequest.path` へ渡す(本番実装は
# `AVAudioFile(forReading:)` に実パスを渡すため、アセットのままでは
# 読めない)。
#
# ## 使い方
#   apps/example/tool/stage_baseline_audio.sh
#   flutter test integration_test/darwin_baseline_e2e_test.dart -d <device-id>
#
# 配置先 `apps/example/assets/baseline-audio/` の音声ファイルは
# .gitignore 済みである(15MB をリポジトリへ二重に持たないため)。
# ディレクトリ自体は `.gitkeep` で追跡する(pubspec.yaml がアセット
# ディレクトリとして宣言しているため、存在しないと CI の
# `flutter build` が失敗する)。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$REPO_ROOT/test-assets/baseline-audio"
DEST="$REPO_ROOT/apps/example/assets/baseline-audio"

mkdir -p "$DEST"

for name in jaJP_10s jaJP_3m enUS_10s enUS_3m; do
  cp "$SRC/$name.wav" "$DEST/$name.wav"
  cp "$SRC/$name.m4a" "$DEST/$name.m4a"
done

# E2E_CHECKLIST.md 手順6 DecodeFailedException: テキストファイルを .wav
# として渡す。
printf 'this is not audio\n' > "$DEST/not_audio.wav"

# Android のリサンプリング経路(E2E_CHECKLIST.md 手順3の3.)用。基準音声は
# 16kHz・モノラルで生成されているためリサンプラを通らない。実環境相当の
# 48kHz / 44.1kHz・ステレオ・AAC を併せて置く。
ffmpeg -nostdin -loglevel error -y -i "$SRC/jaJP_10s.wav" \
  -ar 48000 -ac 2 -c:a aac "$DEST/jaJP_10s_48k_stereo.m4a"
ffmpeg -nostdin -loglevel error -y -i "$SRC/enUS_10s.wav" \
  -ar 44100 -ac 2 -c:a aac "$DEST/enUS_10s_44k1_stereo.m4a"

ls -l "$DEST"
