// model_availability.cpp
//
// 写像の根拠と、どこが判断でどこが文書化された事実かは
// model_availability.h のコメントを参照。
#include "model_availability.h"

#include "winrt_includes.h"

namespace offline_stt_windows {

namespace {

ModelState MapReadyState(wai::AIFeatureReadyState state) {
  switch (state) {
    case wai::AIFeatureReadyState::Ready:
      return ModelState::kAvailable;
    case wai::AIFeatureReadyState::NotReady:
      return ModelState::kDownloadable;
    case wai::AIFeatureReadyState::NotSupportedOnCurrentSystem:
      return ModelState::kUnavailable;
    case wai::AIFeatureReadyState::DisabledByUser:
      return ModelState::kUnavailable;
    default:
      // WinAppSDK 2.0 以降で追加された `CapabilityMissing` /
      // `NotCompatibleWithSystemHardware` / `OSUpdateNeeded`、および将来
      // 追加されうる値。いずれも「アプリ側からダウンロードでは解消できない」
      // 状態なので `unavailable` に写す(理由は model_availability.h)。
      //
      // 識別子を明示的に列挙しないのは、requirements.md NFR-4 が指定する
      // WinAppSDK 1.7.1 ではこれらが定義されておらずコンパイルできないため
      // である。バージョン前提が Issue #58 で確定したら、明示列挙へ
      // 切り替えてもよい。
      return ModelState::kUnavailable;
  }
}

}  // namespace

ModelStateResult QueryModelReadyState() {
  ModelStateResult result;
  try {
    const wai::AIFeatureReadyState state =
        wais::SpeechRecognitionModel::GetReadyState();
    result.state = MapReadyState(state);
  } catch (const winrt::hresult_error& ex) {
    result.error = ClassifyHResult(ex.code(), "GetReadyState");
  }
  return result;
}

}  // namespace offline_stt_windows
