cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "offline_stt_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "offline_stt_windows_plugin")

# =============================================================================
# WinAppSDK(Microsoft.Windows.AI.Speech)の取り込みについて —— Issue #52
# =============================================================================
#
# ## バージョンの齟齬は解消した
# spikes/windows/RESULTS.md は「`Microsoft.Windows.AI.Speech` の API リファレンス
# ページは `windows-app-sdk-2.0-experimental` モニカーでのみ存在し、
# requirements.md NFR-4 の『WinAppSDK 1.7.1以上』と齟齬がある」と記録していた。
#
# M4 実装時点(2026-09)で公式ドキュメントを再確認したところ、
# https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition
# (最終更新 2026-07-07、モニカー指定なしの本線ドキュメント)の Prerequisites に
# 次のとおり明記されている:
#
#     - Windows version: Windows 11, version 24H2 (build 26100) or later
#     - WinAppSDK version: Version 1.7.1 or later
#
# すなわち **requirements.md NFR-4 の「1.7.1以上」が正しい**。API は
# experimental チャンネル限定ではなくなっている。RESULTS.md の記述は
# M0 調査時点(API が experimental にしか無かった頃)のものである。
#
# ## 採用したバージョン
# NuGet の `Microsoft.WindowsAppSDK` で「1.7.1」に相当するのは
# `1.7.250401001` である。本プラグインは 1.7 系の最新サービシング
# `1.7.260224002` を既定とする(上記の最低要件を満たしつつ 1.7 系の修正を
# 取り込むため)。バージョンは `OFFLINE_STT_WINDOWS_APP_SDK_VERSION` という
# 1箇所の cache 変数に集約してあり、差し替えはここだけで済む。
#
# なお `AIFeatureReadyState` の `CapabilityMissing` /
# `NotCompatibleWithSystemHardware` / `OSUpdateNeeded` は WinAppSDK 2.0 以降で
# 追加された値であり、1.7 系ではコンパイルできない。そのため
# model_availability.cpp の switch は全バージョンに存在する値のみを明示列挙し、
# 残りを `default` で受けている(同ファイルのコメント参照)。
#
# ## ビルドが壊れうる点(**すべて未検証**)
# 本プラグインはこれまで WinAppSDK を何も宣言していなかったため、Windows の
# CI ビルド(`flutter build windows --debug`)が通っていた。ここで NuGet 復元を
# 有効にする以上、CI が壊れる可能性がある。**Windows 実機が無く、一度も
# ビルドしていない。** CI が最初の検証である。特に次が未確認である:
#   - CMake(Visual Studio ジェネレータ)が生成する .vcxproj への
#     `VS_PACKAGE_REFERENCES` 経由の NuGet 復元が機能するか。
#   - Microsoft.WindowsAppSDK の MSBuild ターゲットが C++/WinRT の
#     プロジェクションヘッダー(`winrt/Microsoft.Windows.AI.Speech.h` 等)を
#     生成するか。公式の統合手順は Visual Studio の C++ プロジェクトに対する
#     ものであり、CMake 経由で同じことが成立する保証は無い。
#     成立しない場合は runner 側 .vcxproj へ手を入れる等の別手段が要る。
#
# `OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI=OFF` にすると WinAppSDK に触れずに
# ビルドでき、`speech_backend_unavailable.cpp` がリンクされる。その場合
# すべての API 呼び出しは「WinAppSDK 無しでビルドされている」という明示的な
# エラーで失敗する(黙って `unavailable` を返すようなフォールバックはしない)。
# これは配線を切り分けるための退避口であり、既定ではない。
# =============================================================================

option(OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI
  "Microsoft.Windows.AI.Speech (WinAppSDK) を使う実装をビルドする。OFF にすると全APIが明示的なエラーを返すだけになる(配線切り分け用の退避口)。"
  ON)

set(OFFLINE_STT_WINDOWS_APP_SDK_VERSION "1.7.260224002"
  CACHE STRING
  "Speech Recognition API を含む Microsoft.WindowsAppSDK NuGet パッケージのバージョン。公式ドキュメントの要件は 1.7.1 以上(= NuGet の 1.7.250401001)であり、既定値は 1.7 系の最新サービシングである。理由は本ファイル冒頭のコメント。")

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
  # OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI に関係なく常にビルドする。
  "audio_conversion.cpp"
  "pigeon.g.cpp"
)

if(OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI)
  if(OFFLINE_STT_WINDOWS_APP_SDK_VERSION STREQUAL "")
    message(FATAL_ERROR
      "OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI=ON のときは "
      "OFFLINE_STT_WINDOWS_APP_SDK_VERSION に Microsoft.WindowsAppSDK の "
      "バージョンを指定すること(既定値を空にした場合の保険)。要件は 1.7.1 以上 "
      "= NuGet の 1.7.250401001 である。")
  endif()
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

if(OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI)
  # C++/WinRT のランタイム。WindowsApp.lib は Windows SDK 同梱である。
  target_link_libraries(${PLUGIN_NAME} PRIVATE WindowsApp)

  # **未検証**: CMake の Visual Studio ジェネレータが生成する .vcxproj へ
  # NuGet の PackageReference を追加する。Microsoft.WindowsAppSDK の
  # MSBuild ターゲットが C++/WinRT のプロジェクションヘッダー
  # (winrt/Microsoft.Windows.AI.Speech.h 等)を生成する、というのが
  # 公式ドキュメント(get-started.md)が示す統合方法だが、それは
  # Visual Studio の C++ プロジェクトに対する手順であり、CMake 経由で
  # 同じことが成立するかは確認できていない。
  # spikes/windows/README.md「ビルド方法(MSBuild を選択した理由)」に、
  # CMake から cppwinrt.exe を回す公式手順が見つからなかった経緯を記録して
  # いる。CI(windows-2025)が最初の検証である。
  set_property(TARGET ${PLUGIN_NAME} PROPERTY VS_PACKAGE_REFERENCES
    "Microsoft.WindowsAppSDK_${OFFLINE_STT_WINDOWS_APP_SDK_VERSION}")

  target_compile_definitions(${PLUGIN_NAME} PRIVATE
    OFFLINE_STT_WINDOWS_ENABLE_WINDOWS_AI=1)
endif()

set(offline_stt_windows_bundled_libraries
  ""
  PARENT_SCOPE
)
