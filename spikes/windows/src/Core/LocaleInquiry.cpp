// LocaleInquiry.cpp
#include "pch.h"
#include "LocaleInquiry.h"

#include <vector>

namespace wsspike {

LocaleInquiryResult QueryLocaleInquiry() {
    LocaleInquiryResult result;

    // GetUserDefaultLocaleName / GetSystemDefaultLocaleName (winnls.h, kernel32.dll)。
    // LOCALE_NAME_MAX_LENGTH は winnls.h で 85 と定義される。
    wchar_t buf[LOCALE_NAME_MAX_LENGTH] = {};
    if (::GetUserDefaultLocaleName(buf, LOCALE_NAME_MAX_LENGTH) > 0) {
        result.userDefaultLocaleName = buf;
    }
    ::ZeroMemory(buf, sizeof(buf));
    if (::GetSystemDefaultLocaleName(buf, LOCALE_NAME_MAX_LENGTH) > 0) {
        result.systemDefaultLocaleName = buf;
    }

    // GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, ...) は
    // NUL区切り・末尾二重NULのMULTI_SZ文字列を返す(標準Win32国際化API)。
    ULONG numLanguages = 0;
    ULONG bufferSize = 0;
    if (::GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &numLanguages, nullptr, &bufferSize) &&
        bufferSize > 0) {
        std::vector<wchar_t> langBuffer(bufferSize);
        if (::GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &numLanguages, langBuffer.data(), &bufferSize)) {
            result.preferredUiLanguage = langBuffer.data();  // 先頭(最優先)言語のみ採用
        }
    }

    return result;
}

}  // namespace wsspike
