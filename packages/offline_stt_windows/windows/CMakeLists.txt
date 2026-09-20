cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "offline_stt_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "offline_stt_windows_plugin")

add_library(${PLUGIN_NAME} SHARED
  "offline_stt_windows_plugin.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# TODO(M4): WinAppSDK 1.7.1+ (Windows App SDK) をNuGet経由で追加する。

set(offline_stt_windows_bundled_libraries
  ""
  PARENT_SCOPE
)
