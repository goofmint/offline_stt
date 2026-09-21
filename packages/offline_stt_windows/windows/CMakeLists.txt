cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "offline_stt_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "offline_stt_windows_plugin")

# =============================================================================
# WinAppSDK(Microsoft.Windows.AI.Speech)の取り込みについて —— Issue #52
# =============================================================================
#
# ## バージョン要件は確定している
# 公式ドキュメント
# https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition
# (最終更新 2026-07-07、モニカー指定なしの本線ドキュメント)の Prerequisites:
#
#     - Windows version: Windows 11, version 24H2 (build 26100) or later
#     - WinAppSDK version: Version 1.7.1 or later
#
# すなわち requirements.md NFR-4 の「WinAppSDK 1.7.1以上」が正しい。M0 調査
# 時点では API リファレンスが `windows-app-sdk-2.0-experimental` モニカーでしか
# 見つからず齟齬を疑っていたが、その疑いは解消した。
#
# ## ヘッダーをどう手に入れるか —— CI で実際に失敗させて分かったこと
# 当初は `VS_PACKAGE_REFERENCES` で Microsoft.WindowsAppSDK の NuGet
# PackageReference を足せばよいと考えたが、**CI(windows-2025)で実際に
# ビルドして失敗した**:
#
#     winrt_includes.h(37,10): error C1083: Cannot open include file:
#     'winrt/Microsoft.Windows.AI.h': No such file or directory
#
# `winrt/base.h` や `winrt/Windows.Foundation.h`(Windows SDK 同梱)は開けて
# いるため、C++/WinRT 自体は使える。開けないのは **WinAppSDK の
# プロジェクションヘッダー**である。これらは Windows SDK には含まれず、
# NuGet パッケージ内の .winmd から `cppwinrt.exe` が生成するものであり、
# CMake が生成する .vcxproj へ PackageReference を足すだけでは
# 復元も生成も走らなかった。
#
# ## 採用した方法: winapp CLI が用意する `.winapp/include` を使う
# Microsoft は Flutter 向けの公式手順を用意している:
# https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/guides/flutter
# アプリ側で `winapp init` を実行すると、WinAppSDK のヘッダー一式が
# `<app>/.winapp/include` に展開される。Flutter のランナー(C++)からは
# そのディレクトリを include path に足し `WindowsApp.lib` をリンクするだけで
# WinRT API を呼べる、というのが公式が示す手順である。
#
# **この手順はアプリ側で必ず必要になる。** Windows AI APIs はパッケージ
# 識別(MSIX + systemAIModels capability)が無いと動かず、その識別を
# 与えるのが winapp CLI だからである(packages/offline_stt_windows/README.md
# 参照)。したがって「プラグインのためだけに増える手順」ではない。
#
# 本 CMakeLists は `.winapp/include` を自動検出する:
#   - 見つかった場合  -> WinRT 実装(speech_backend_winrt.cpp 等)をビルドする。
#   - 見つからない場合 -> speech_backend_unavailable.cpp をビルドする。
#     モデル状態の照会・モデル取得・文字起こしは「WinAppSDK ヘッダー無しで
#     ビルドされている。
#     アプリ側で winapp init を実行せよ」という**明示的なエラー**で失敗する。
#     黙って `unavailable` を返すようなフォールバックはしない。
#   どちらになったかは構成時に message() で必ず出力する。
#
# CI は winapp CLI を持たないため常に後者になる。つまり **CI が検証するのは
# WinRT に触れない部分(Pigeon 受け口・スレッド調停・エラー分類・Media
# Foundation 変換)のコンパイルだけである。** WinRT 実装のコンパイルは
# Issue #58 の実機検証でしか確認できない。
#
# `OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR` を明示的に指定すれば、自動検出の
# 場所以外(NuGet を手で展開した先など)も使える。
# =============================================================================

# アプリ側の `winapp init` が展開する WinAppSDK ヘッダーの場所。
# 明示指定が無ければ自動検出する。
set(OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR ""
  CACHE PATH
  "WinAppSDK の C++/WinRT プロジェクションヘッダーがあるディレクトリ(通常はアプリの .winapp/include)。空の場合は自動検出する。")

if(OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR STREQUAL "")
  # Flutter の Windows ビルドでは、このファイルは
  # <app>/windows/flutter/ephemeral/.plugin_symlinks/<plugin>/windows/ から
  # 読み込まれる。CMAKE_SOURCE_DIR はアプリの windows/ ディレクトリを指すため、
  # その1つ上(= アプリのルート)に .winapp がある。
  # 念のため、アプリの windows/ 直下も見る。
  foreach(candidate
      "${CMAKE_SOURCE_DIR}/../.winapp/include"
      "${CMAKE_SOURCE_DIR}/.winapp/include")
    if(EXISTS "${candidate}/winrt/Microsoft.Windows.AI.Speech.h")
      set(OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR "${candidate}")
      break()
    endif()
  endforeach()
endif()

if(NOT OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR STREQUAL "")
  set(OFFLINE_STT_WINDOWS_HAVE_WINDOWS_AI TRUE)
  message(STATUS
    "offline_stt_windows: WinAppSDK ヘッダーを ${OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR} に発見した。Windows AI 実装をビルドする。")
else()
  set(OFFLINE_STT_WINDOWS_HAVE_WINDOWS_AI FALSE)
  message(STATUS
    "offline_stt_windows: WinAppSDK ヘッダー(winrt/Microsoft.Windows.AI.Speech.h)が見つからない。"
    "音声認識は無効のままビルドする。有効にするにはアプリのルートで `winapp init` を実行するか、"
    "OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR にヘッダーの場所を指定すること。"
    "詳細は packages/offline_stt_windows/README.md を参照。")
endif()

# WinRT に触れないソース。ビルド構成によらず常にコンパイルされるため、
# Windows CI はこれらのコンパイルエラーを検出できる。
set(PLUGIN_SOURCES
  "offline_stt_windows_plugin.cpp"
  "offline_stt_api_impl.cpp"
  "stream_callback_sender.cpp"
  "platform_thread_dispatcher.cpp"
  "windows_transcribe_error.cpp"
  "string_conversion.cpp"
  # Issue #54: Media Foundation による wav 変換。Media Foundation は
  # Windows SDK に含まれるため WinAppSDK には依存しない。したがって
  # WinAppSDK ヘッダーの有無に関係なく常にビルドする。
  "audio_conversion.cpp"
  "pigeon.g.cpp"
)

if(OFFLINE_STT_WINDOWS_HAVE_WINDOWS_AI)
  list(APPEND PLUGIN_SOURCES
    "speech_backend_winrt.cpp"
    "model_availability.cpp"
    "model_acquisition.cpp"
    "recognition_session.cpp"
  )
else()
  list(APPEND PLUGIN_SOURCES "speech_backend_unavailable.cpp")
endif()

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
# **ソースが UTF-8 であることを MSVC に明示する。**
# 本プラグインのソースは日本語のコメントと文字列リテラルを含む。MSVC は
# BOM の無いソースをシステムの ANSI コードページとして解釈するため、
# 日本語ロケールの Windows(CP932)では日本語が壊れ、
#   warning C4819(現在のコードページで表示できない文字を含む)
#   → C2220(警告のエラー化)
#   error C2001(定数が2行目に続いています)
# で必ずビルドが失敗する。**日本語ロケールの Windows 11 実機で実際に確認した。**
# GitHub Actions のランナーは英語ロケールのため CI では顕在化しない。
target_compile_options(${PLUGIN_NAME} PRIVATE "/utf-8")

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# Issue #54: Media Foundation(Source Reader)。いずれも Windows SDK 同梱で
# あり、requirements.md FR-4 の「各OS純正デコーダのみ使用」を満たす。
target_link_libraries(${PLUGIN_NAME} PRIVATE
  mfplat
  mfreadwrite
  mfuuid
  ole32
)

if(OFFLINE_STT_WINDOWS_HAVE_WINDOWS_AI)
  # C++/WinRT のランタイム。WindowsApp.lib は Windows SDK 同梱である。
  target_link_libraries(${PLUGIN_NAME} PRIVATE WindowsApp)

  # winapp CLI(あるいは手動展開)が用意した WinAppSDK のプロジェクション
  # ヘッダー。公式の Flutter 向け手順もこのディレクトリを include path に
  # 足すだけである(本ファイル冒頭のコメント参照)。
  target_include_directories(${PLUGIN_NAME} PRIVATE
    "${OFFLINE_STT_WINDOWS_WINAPP_INCLUDE_DIR}")

  # C++/WinRT のコルーチンは C++20 の <coroutine> を使う。Flutter の既定
  # (C++17)のままだと winrt/base.h が非推奨の <experimental/coroutine> へ
  # 落ち、MSVC 14.51 が
  #   error C2338: static assertion failed: 'error STL1011: ...
  #   <experimental/coroutine> ... deprecated ... will be REMOVED SOON'
  # で停止する。実際に CI(windows-2025)で発生したため C++20 を要求する。
  # 非推奨警告を黙らせるマクロ(_SILENCE_EXPERIMENTAL_COROUTINE_...)は、
  # 「SOON に削除される」と明言されているものを延命するだけなので使わない。
  target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_20)

  target_compile_definitions(${PLUGIN_NAME} PRIVATE
    OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI=1)
endif()

set(offline_stt_windows_bundled_libraries
  ""
  PARENT_SCOPE
)
