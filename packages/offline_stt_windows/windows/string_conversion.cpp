// string_conversion.cpp
#include "string_conversion.h"

#include <windows.h>

namespace offline_stt_windows {

bool Utf8ToWide(const std::string& input, std::wstring* output) {
  if (output == nullptr) return false;
  output->clear();
  if (input.empty()) return true;
  const int required = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
      static_cast<int>(input.size()), nullptr, 0);
  if (required <= 0) return false;
  output->resize(static_cast<size_t>(required));
  const int written = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
      static_cast<int>(input.size()), output->data(), required);
  if (written != required) {
    output->clear();
    return false;
  }
  return true;
}

bool WideToUtf8(const std::wstring& input, std::string* output) {
  if (output == nullptr) return false;
  output->clear();
  if (input.empty()) return true;
  const int required = ::WideCharToMultiByte(
      CP_UTF8, 0, input.data(), static_cast<int>(input.size()), nullptr, 0,
      nullptr, nullptr);
  if (required <= 0) return false;
  output->resize(static_cast<size_t>(required));
  const int written = ::WideCharToMultiByte(
      CP_UTF8, 0, input.data(), static_cast<int>(input.size()), output->data(),
      required, nullptr, nullptr);
  if (written != required) {
    output->clear();
    return false;
  }
  return true;
}

}  // namespace offline_stt_windows
