// windows_transcribe_error.h
//
// design.md §5 エラーマッピング表 Windows列への分類(Issue #56)。
// `offline_stt_darwin/darwin/Classes/DarwinTranscribeError.swift` および
// `offline_stt_android/.../AndroidTranscribeError.kt` に対応するファイル。
//
// design.md §5 の Windows列:
//   ModelUnavailable  <- NotReady / EnsureReadyAsync の失敗
//   LocaleUnsupported <- (M0確認後に確定) → ロケール指定APIが存在しないこと
//                        がドキュメント調査で確定したため、Windows実装は
//                        このコードを発生させない(design.md §8 未決事項2)
//   DecodeFailed      <- Media Foundation失敗(audio_conversion.cpp)
//   DeviceUnsupported <- NotSupportedOnCurrentSystem 等
//   Cancelled         <- 認識中断
//   PlatformError     <- 上記のいずれにも分類できないもの
//
// spikes/windows/src/Core/Support.h の `ErrorCategory` からの差分:
// スパイクは `Timeout` / `CapabilityMissing` という独自分類を持っていたが、
// 本実装は design.md §5 の6値のみを持つ。理由は darwin 実装と同じで、
// スパイク独自の検証用分類を本実装の公開エラーモデル(requirements.md FR-6)
// に持ち込まないためである。`CapabilityMissing` 相当(MSIXマニフェストに
// `systemAIModels` capability が無い場合の `winrt::hresult_access_denied`)は
// `deviceUnsupported` ではなく `platformError` へ分類し、原因が分かるよう
// メッセージに明記する(分類の判断根拠は ClassifyHResult の実装コメント参照)。
#ifndef OFFLINE_STT_WINDOWS_WINDOWS_TRANSCRIBE_ERROR_H_
#define OFFLINE_STT_WINDOWS_WINDOWS_TRANSCRIBE_ERROR_H_

// `<windows.h>` は既定で min/max マクロを定義し、`std::min`/`std::max` を
// 使う標準ヘッダー(Flutter の C++ ラッパーが間接的に取り込む)を壊す。
// Flutter の Windows ランナーテンプレートと同じく NOMINMAX と
// WIN32_LEAN_AND_MEAN を先に定義してから取り込む。
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <string>

#include "pigeon.g.h"

namespace offline_stt_windows {

// requirements.md FR-6 のエラー1件。`message` は UTF-8。
// 空文字列は「追加情報なし」を表す(Dart側では `null` として扱われる)。
struct TranscribeError {
  TranscribeErrorCode code;
  std::string message;
};

// Pigeon の `TranscribeErrorCode` を、Dart側
// (`lib/src/error_code_mapping.dart`)が文字列比較で写像できる形へ落とす。
//
// この文字列は Dart 側の `TranscribeErrorCode.name`(enum名の文字列表現)と
// 完全一致させている。`lib/src/pigeon.g.dart` の `TranscribeErrorCode` 定義と
// この分岐の対応関係が崩れないよう、両方を変更する場合は必ず同時に更新すること
// (darwin の `DarwinTranscribeError.swift` の `wireCode` と同じ約束)。
std::string WireCode(TranscribeErrorCode code);

// HRESULT を design.md §5 の分類へ写像する。
//
// **未検証**: 本リポジトリには Windows 実機が無く、各APIが実際にどのHRESULTを
// 返すかは一度も観測できていない。ここでの分類は Microsoft 公式ドキュメント
// (get-started.md の `CapabilityMissing` の記述)と、Media Foundation の
// HRESULT ファシリティ(`MF_E_*` は `0xC00D....`)という一般的な規約に
// 基づく推定である。Issue #58 の実機E2Eで確定させること。
TranscribeError ClassifyHResult(HRESULT hr, const std::string& context);

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_WINDOWS_TRANSCRIBE_ERROR_H_
