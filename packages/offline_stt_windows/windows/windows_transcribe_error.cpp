// windows_transcribe_error.cpp
#include "windows_transcribe_error.h"

#include <sstream>

namespace offline_stt_windows {

namespace {

std::string FormatHResult(HRESULT hr) {
  std::ostringstream ss;
  ss << "HRESULT=0x" << std::hex << static_cast<unsigned long>(hr);
  return ss.str();
}

}  // namespace

std::string WireCode(TranscribeErrorCode code) {
  switch (code) {
    case TranscribeErrorCode::kModelUnavailable:
      return "modelUnavailable";
    case TranscribeErrorCode::kLocaleUnsupported:
      return "localeUnsupported";
    case TranscribeErrorCode::kDecodeFailed:
      return "decodeFailed";
    case TranscribeErrorCode::kDeviceUnsupported:
      return "deviceUnsupported";
    case TranscribeErrorCode::kCancelled:
      return "cancelled";
    case TranscribeErrorCode::kPlatformError:
      return "platformError";
  }
  // enum の全値を上で列挙しているため到達しない。到達した場合は
  // 既定値で丸めず、Dart側の `mapNativeErrorCode` の default 分岐
  // (`PlatformException_` としてcodeをそのまま保持する)に落として
  // 原因が追えるようにする。
  return "unknownTranscribeErrorCode";
}

TranscribeError ClassifyHResult(HRESULT hr, const std::string& context) {
  TranscribeError error;
  error.message = context + ": " + FormatHResult(hr);

  if (hr == E_ACCESSDENIED) {
    // spikes/windows/README.md「systemAIModels capability を宣言しないと
    // どうなるか」の調査結果: 公式ドキュメント(get-started.md)は
    // `AIFeatureReadyState.CapabilityMissing` の説明として
    // 「EnsureReadyAsync and CreateAsync will throw
    //  winrt::hresult_access_denied (add the systemAIModels capability to
    //  the app manifest)」と明記している。ただしこの記述は
    // `Microsoft.Windows.AI.Text.LanguageModel` についてのものであり、
    // `SpeechRecognitionModel` について同一の記載は確認できていない(未検証)。
    //
    // design.md §5 の表にこの状況に対応する行は無い。アプリ側のMSIX
    // マニフェスト不備であって「端末が非対応」ではないため
    // `deviceUnsupported` には寄せず、`platformError` としたうえで
    // 対処方法をメッセージに含める(利用者が原因に到達できるようにする)。
    error.code = TranscribeErrorCode::kPlatformError;
    error.message +=
        " (E_ACCESSDENIED。MSIXパッケージの Package.appxmanifest に "
        "systemAIModels capability が宣言されていない可能性が高い。"
        "design.md §8 / README のWindows前提条件を参照)";
    return error;
  }

  // Media Foundation の HRESULT は FACILITY_MF(0x0D)を用い、
  // `MF_E_*` は 0xC00D.... の帯に入る。この帯を DecodeFailed へ寄せる。
  // **未検証**: 実機で実際にどの値が返るかは確認できていない(Issue #58)。
  if ((static_cast<unsigned long>(hr) & 0xFFFF0000UL) == 0xC00D0000UL) {
    error.code = TranscribeErrorCode::kDecodeFailed;
    return error;
  }

  error.code = TranscribeErrorCode::kPlatformError;
  return error;
}

}  // namespace offline_stt_windows
