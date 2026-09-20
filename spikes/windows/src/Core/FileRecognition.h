// FileRecognition.h
//
// Issue #16: ファイル認識(TryCreateAsync → RecognizeFromFile)と
// フォーマット受理テスト(wav / m4a / mp3)。
//
// 対応する設計: design.md §4.4 Windows「SpeechRecognitionModel.TryCreateAsync()
// → BatchRecognition.RecognizeFromFile(path) → 最終テキスト1件を isFinal=true で
// emit → close」、§8 未決事項1(対応フォーマット)。
//
// 参照した公式ドキュメント(2026-09-20 WebFetchで確認):
// - https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition
//   (「Batch recognition from an audio file」節のC#サンプルコード)
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodel.trycreateasync
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.speechrecognitionmodelresult
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.batchrecognition
// - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.ai.speech.batchrecognition.recognizefromfile
//
// 確認できた事実:
// - `SpeechRecognitionModel.TryCreateAsync()` は static、
//   戻り値 `IAsyncOperationWithProgress<SpeechRecognitionModelResult, SpeechRecognitionModelProgress>`。
// - `SpeechRecognitionModelResult` は `SpeechModel` / `ExtendedError` の2プロパティを持つ。
//   公式サンプルは `speechModelResult.SpeechModel == null` を失敗判定に使っている。
// - `BatchRecognition` のコンストラクタは `BatchRecognition(SpeechRecognitionModel)` の1つのみ。
// - `RecognizeFromFile` の cppwinrt シグネチャは
//   `IAsyncOperation<winrt::hstring> RecognizeFromFile(winrt::hstring const& filePath);`
//   (パスを表す文字列を直接渡す。StorageFileではない)。
// - `BatchRecognition.Recognize(Byte[])` という、ファイルパスではなく生バイト列を
//   渡すオーバーロードも存在する(design.md には記載が無い追加知見。
//   Media Foundationでのwav変換結果をファイル化せず直接渡す経路として
//   将来検討の余地がある。RESULTS.md参照)。
//
// 要確認(ドキュメントに記載が無く実機でしか分からない事項。design.md §8 未決事項1):
// - `RecognizeFromFile` がAPIレベルで受理する具体的な音声フォーマット
//   (コンテナ・コーデック・サンプルレート)の一覧。公式ドキュメントに
//   フォーマット対応表は存在しない。
// - `Recognize(Byte[])` が期待するバイト列のフォーマット
//   (生PCMか、エンコード済みファイルのバイト列をそのまま渡せるか)も未記載。
// - 拒否時に具体的にどの例外・HRESULTが飛ぶか(Media Foundation起因かどうか)。

#pragma once

#include <optional>
#include <string>

#include "Support.h"

namespace wsspike {

// TryCreateAsync() の結果。SpeechModel の実体は呼び出し側では保持せず、
// 本スパイクでは1回のCLI実行内でモデルを都度生成する(darwinスパイクの
// 「1クリップごとに新規セッションを張る」構成に合わせた)。
struct FormatAcceptance {
    std::wstring filePath;
    bool accepted = false;
    // 拒否/失敗時の SpikeError.Describe()。成功時は空文字列。
    std::wstring failureDetail;
    double elapsedSeconds = 0.0;
};

struct TranscriptionResult {
    std::wstring filePath;
    std::wstring transcript;
    double elapsedSeconds = 0.0;
    double audioDurationSeconds = -1.0;  // 取得できない場合は負値のまま
};

// SpeechRecognitionModel.TryCreateAsync() を実行し、失敗時は
// SpikeError(ModelUnavailable、または PlatformError)を投げる。
// 戻り値は呼び出し側が BatchRecognition の生成にそのまま渡す不透明ハンドル。
// (C++/WinRT型を直接ヘッダーへ露出させないよう、Cliからは
//  RecognizeFile() 経由でのみ使う設計にしている)
void* CreateSpeechModelOrThrow(double timeoutSeconds);
void ReleaseSpeechModel(void* modelHandle);

// 1ファイルを RecognizeFromFile で認識する。design.mdの設計どおり、
// batch認識はfinalテキストを1回返すのみでpartialは発行されない
// (ドキュメント上もそのような設計であることをC#サンプルで確認済み。
//  RecognizeFromFileの戻り値は単一の文字列であり、Recognizing系イベントは
//  StreamingRecognitionクラス側にのみ存在する)。
TranscriptionResult RecognizeFile(void* modelHandle, const std::wstring& filePath, double timeoutSeconds);

// Issue #16: フォーマット受理テスト。RecognizeFromFile に投げて
// 成功/失敗を記録するだけの薄いラッパー(例外を握りつぶして記録する)。
FormatAcceptance TryRecognizeForFormatTest(void* modelHandle, const std::wstring& filePath, double timeoutSeconds);

}  // namespace wsspike
