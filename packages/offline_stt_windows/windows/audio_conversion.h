// audio_conversion.h
//
// Issue #54: Media Foundation による wav 変換層。
// requirements.md FR-4(音声デコード層)、design.md §4.4。
// `offline_stt_android/.../AudioDecoder.kt`(MediaCodec)および
// `offline_stt_darwin/darwin/Classes/TranscriptionSession.swift`(AVFoundation)
// に対応する、Windowsのデコード担当モジュールである。
//
// ## 前提条件が未検証であること(重要)
// design.md §4.4 / §8 未決事項1 は次のように書いている:
//   「`RecognizeFromFile(String)` はファイルパス文字列を直接渡す。
//     対応入力フォーマットはドキュメントに記載が無く、実機での確認が必須で
//     ある(未確定)。wav以外が通らなければMedia Foundation変換層を必須化」
// つまり「変換層が要るか」は M0(Windows実機)の結果で決めるはずだった。
// **その M0 は実施できていない**(Windows機が無い)。したがって本実装は
// 未確認の前提の上に立っており、Issue #58 の実機E2Eで確定させる必要がある。
//
// ## それでも「常に変換する」を選んだ理由
// 取りうる方針は3つあった:
//   (a) 変換せず、入力ファイルのパスをそのまま `RecognizeFromFile` に渡す
//   (b) まずそのまま渡し、失敗したら変換して再試行する
//   (c) 常に変換してから渡す  ← 採用
// (a) は「wav以外が通らない」場合に mp3 / m4a が黙って使えなくなる。
// requirements.md FR-4 は「wav / m4a / mp3 / aac 等、各OS標準デコーダが
// 対応する範囲」を入力として要求しているので、要件を満たせない可能性が残る。
// (b) は「どのエラーが『フォーマット拒否』を意味するのか」を知っている必要が
// あるが、それこそが未検証の当の対象である。加えてリポジトリの方針が禁じる
// 「失敗したら別の手で取り繕う」フォールバックそのものになる。
// (c) は入力側の未確定要素を消し、経路を1本に固定できる。既に 16kHz
// モノラルの wav であっても再エンコードするぶん無駄はあるが、
// requirements.md NFR-1 が言うとおりWindowsのバッチ認識は非実時間であり、
// 変換コストは音声長に対して十分小さいと見込める(**これは見込みであって
// 実測ではない**)。
//
// ## 出力フォーマットの選定根拠(これも未検証)
// 16kHz / モノラル / 16-bit PCM の RIFF WAVE を出力する。
// - 16kHz モノラル 16-bit は `offline_stt_android` の MediaCodec ポンプが
//   requirements.md FR-4 に従って採用しているのと同じ形式であり、音声認識
//   モデルの一般的な入力形式でもある。
// - ただし `Microsoft.Windows.AI.Speech` が要求するサンプルレート・
//   チャンネル数は公式ドキュメントに記載が無い。この選定は推定であり、
//   Issue #58 で確認すること。
//
// ## Media Foundation を使う理由
// requirements.md FR-4 は「各OS純正デコーダのみ使用(FFmpeg等の同梱は不可)」
// と定める。Media Foundation は Windows 同梱のコンポーネントであり、
// Source Reader に出力メディアタイプとして PCM を指定すると、必要な
// デコーダとリサンプラーを自動で挿し込んでくれる(公式ドキュメントの
// Source Reader の「Processing Media Data」に記載のある標準的な使い方)。
#ifndef OFFLINE_STT_WINDOWS_AUDIO_CONVERSION_H_
#define OFFLINE_STT_WINDOWS_AUDIO_CONVERSION_H_

#include <optional>
#include <string>

#include "windows_transcribe_error.h"
// 出力パスは UTF-16(`std::wstring`)で扱う。UTF-8 との変換は
// `string_conversion.h` を使う。

namespace offline_stt_windows {

// 変換結果。成功なら `output_path` に一時ファイルのパス(UTF-16)が入り、
// 失敗なら `error` に値が入る。
struct AudioConversionResult {
  std::wstring output_path;
  std::optional<TranscribeError> error;
};

// 出力フォーマット(上記「出力フォーマットの選定根拠」参照)。
inline constexpr unsigned int kOutputSampleRate = 16000;
inline constexpr unsigned int kOutputChannels = 1;
inline constexpr unsigned int kOutputBitsPerSample = 16;

// `input_path_utf8` を 16kHz モノラル 16-bit PCM の wav へ変換し、
// 一時ディレクトリに書き出す。呼び出し側は使用後に
// [DeleteTemporaryFile] で削除すること。
//
// 本関数はブロッキングである(Source Reader を同期モードで使う)。
// プラットフォームスレッドから呼んではならない。
AudioConversionResult ConvertToPcmWav(const std::string& input_path_utf8);

// [ConvertToPcmWav] が作った一時ファイルを削除する。
// 削除に失敗しても回復手段は無いため戻り値は持たない(一時ディレクトリの
// ファイルであり、OS側の掃除に委ねられる)。
void DeleteTemporaryFile(const std::wstring& path);

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_AUDIO_CONVERSION_H_
