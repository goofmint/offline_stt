// string_conversion.h
//
// UTF-8(Pigeonのワイヤ表現・`std::string`)と UTF-16(Win32/WinRTの
// `std::wstring` / `winrt::hstring`)の相互変換(Issue #52)。
//
// Pigeon生成コード(`pigeon.g.h`)の文字列は `std::string` であり、Flutterの
// StandardMessageCodec がUTF-8でエンコードする。一方 Win32 / WinRT のAPIは
// UTF-16 を要求するため、境界で必ず変換が要る。取りこぼすとファイルパスの
// 非ASCII文字(日本語のファイル名等)で壊れる。
#ifndef OFFLINE_STT_WINDOWS_STRING_CONVERSION_H_
#define OFFLINE_STT_WINDOWS_STRING_CONVERSION_H_

#include <string>

namespace offline_stt_windows {

// 変換に失敗した場合は空文字列ではなく、呼び出し側が失敗を検知できるよう
// `false` を返す(空文字列を返すと「空のパス」と区別できず、フォールバック
// 的な握りつぶしになるため)。
bool Utf8ToWide(const std::string& input, std::wstring* output);
bool WideToUtf8(const std::wstring& input, std::string* output);

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_STRING_CONVERSION_H_
