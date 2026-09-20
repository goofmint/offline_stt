// pch.h — プリコンパイル済みヘッダー。
// C++/WinRT のプロジェクションヘッダーは生成コストが高いため、
// spikes/darwin 同様に本スパイクでも最小限の共通インクルードのみをここに集約する。
#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <unknwn.h>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>

// Microsoft.Windows.AI / Microsoft.Windows.AI.Speech は WinAppSDK が生成する
// C++/WinRT プロジェクションヘッダーであり、NuGet パッケージ
// (Microsoft.WindowsAppSDK, Experimental channel — README 参照)の導入後に
// ビルドシステムが自動生成する。本スパイクはWindows機を持たず生成物を確認でき
// ないため、ヘッダー名は公式ドキュメントのネームスペース表記から機械的に推測した
// 標準的な命名規則(winrt/<Namespace>.h)に従っている。実際の生成ファイル名が
// 異なる場合はビルドエラーとなるため、README「要確認」欄に明記している。
#include <winrt/Microsoft.Windows.AI.h>
#include <winrt/Microsoft.Windows.AI.Speech.h>

#include <string>
#include <vector>
#include <optional>
#include <memory>
