// LocaleInquiry.h
//
// Issue #17: ロケール照会。design.md §8 未決事項2(ロケール指定可否)の確定材料。
//
// 結論(ドキュメント調査で確定): Microsoft.Windows.AI.Speech 名前空間には
// ロケール・言語を指定するAPIが一切存在しない。2026-09-20時点でWebFetchした
// 以下のページを突き合わせて確認した:
// - namespace一覧 https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech
//   (Classes: AudioConfiguration, BatchRecognition, SpeechAudioProvider,
//    SpeechRecognitionModel, SpeechRecognitionModelResult, StreamingRecognition,
//    StreamingRecognizedEventArgs, StreamingRecognizingEventArgs。
//    Structs: SpeechRecognitionModelProgress。
//    Enums: SpeechRecognitionModelProgressStatus。
//    ロケール・言語に関する型は1件も無い)
// - SpeechRecognitionModel クラスのメンバー一覧
//   https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel
//   (Close/Dispose/EnsureReadyAsync/GetReadyState/TryCreateAsyncの5メンバーのみ。
//    引数を取るメンバーが無く、ロケールを渡す余地がAPI形状として存在しない)
// - BatchRecognition クラスのメンバー一覧
//   https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.batchrecognition
//   (コンストラクタは BatchRecognition(SpeechRecognitionModel) の1つのみ。
//    メソッドは Recognize(Byte[]) と RecognizeFromFile(String) の2つのみで、
//    いずれもロケール引数を取らない)
// - AudioConfiguration クラスのメンバー一覧
//   https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.audioconfiguration
//   (ForProvider/FromAudioDevice/FromFile/FromStreamの4メンバー。いずれも
//    ロケールではなく音声ソースを指定するものであり、言語指定の手段ではない)
//
// 以上より、design.md §4.4「言語指定APIの有無をM0で確認(ドキュメント上、
// ロケール指定の記載が未確認)」は本スパイクの文献調査で「無い」と確定できる。
// ただし「無いことの実機での帰結」(SpeechRecognitionModelが実際にどの言語
// (OSの表示言語?キーボードレイアウト?システムロケール?)で認識するかは
// ドキュメントに記載が無く、実機でしか分からない。design.md §8同様、
// 「Windows: ja-JP対応可否」自体もこの帰結次第であり、ドキュメント調査だけでは
// 確定できない(RESULTS.md「実機でのみ確認可能な事項」参照)。

#pragma once

#include <string>

namespace wsspike {

// ロケール指定APIが存在しないという確定事実と、代わりに観測できる
// OS側の言語設定(システムロケール・既定入力言語)をあわせて返す。
// 「Windows AI Speech Recognitionが実際にどの言語で認識するか」の推測にはならない
// ―― あくまでOS設定値の記録であり、認識結果の言語とAPIで結び付けるものではない。
struct LocaleInquiryResult {
    // Speech名前空間にロケール指定APIが存在しないことの確認結果(常にtrue)。
    // フィールドとして残しているのは、将来のWinAppSDKバージョンでAPIが追加された
    // 場合に本スパイクを更新した際、trueのままなら「今回も確認した」ことを
    // 明示するため。
    bool localeApiConfirmedAbsent = true;

    // GetUserDefaultLocaleName (Win32 API, kernel32.dll) の結果。
    // https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-getuserdefaultlocalename
    std::wstring userDefaultLocaleName;

    // GetSystemDefaultLocaleName の結果。
    // https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-getsystemdefaultlocalename
    std::wstring systemDefaultLocaleName;

    // GetUserPreferredUILanguages の結果(先頭1件、取得できた場合)。
    std::wstring preferredUiLanguage;
};

LocaleInquiryResult QueryLocaleInquiry();

}  // namespace wsspike
