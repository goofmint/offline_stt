// winrt_includes.h
//
// C++/WinRT の共通インクルード(Issue #52)。
// `spikes/windows/src/Core/pch.h` に対応する。
//
// `winrt/Microsoft.Windows.AI.h` / `winrt/Microsoft.Windows.AI.Speech.h` は
// WinAppSDK の NuGet パッケージが `Microsoft.Windows.CppWinRT` の MSBuild
// ターゲット経由で生成するプロジェクションヘッダーである。
//
// **未検証**: 本リポジトリは Windows 実機を持たず、これらのヘッダーが
// 実際にこの名前で生成されるかを確認できていない。ヘッダー名は公式
// ドキュメントの名前空間表記から、C++/WinRT の標準的な命名規則
// (`winrt/<Namespace>.h`)に従って機械的に導いたものである
// (spikes/windows/src/Core/pch.h と同じ推定)。名前が違えばビルドエラーに
// なる。Issue #58 で確定させること。
//
// 本ヘッダーを include してよいのは、`windows/CMakeLists.txt` の
// `OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI` が ON のときだけコンパイルされる
// ファイル(`model_availability.cpp` / `model_acquisition.cpp` /
// `recognition_session.cpp` / `speech_backend_winrt.cpp`)に限る。
#ifndef OFFLINE_STT_WINDOWS_WINRT_INCLUDES_H_
#define OFFLINE_STT_WINDOWS_WINRT_INCLUDES_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <unknwn.h>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>

#include <winrt/Microsoft.Windows.AI.h>
#include <winrt/Microsoft.Windows.AI.Speech.h>

namespace offline_stt_windows {

namespace wai = ::winrt::Microsoft::Windows::AI;
namespace wais = ::winrt::Microsoft::Windows::AI::Speech;
namespace wf = ::winrt::Windows::Foundation;

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_WINRT_INCLUDES_H_
