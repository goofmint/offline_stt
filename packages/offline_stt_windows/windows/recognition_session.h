// recognition_session.h
//
// Issue #55(FR-3): 認識セッション。
// `offline_stt_darwin/darwin/Classes/TranscriptionSession.swift` および
// `offline_stt_android/.../RecognitionSession.kt` に対応するファイル。
//
// design.md §4.4 のパイプラインをそのまま実装する:
//
//   入力ファイル
//     → Media Foundation で wav へ変換(audio_conversion.h、Issue #54)
//     → SpeechRecognitionModel.TryCreateAsync()
//     → BatchRecognition.RecognizeFromFile(path)
//     → 最終テキスト1件を isFinal=true でemit → close
//
// ## final 1件だけである根拠
// `BatchRecognition.RecognizeFromFile()` の戻り値は
// `IAsyncOperation<winrt::hstring>` であり、単一の文字列を返す。partial を
// 通知するイベント(`Recognizing`)は `StreamingRecognition` クラス側にしか
// 存在しないことを名前空間のメンバー一覧で確認済み
// (spikes/windows/src/Core/FileRecognition.h の調査結果)。したがって
// requirements.md FR-3 の「Windowsバッチ認識はfinalのみ1回emit」は、
// 実装上の選択ではなくAPIの形そのものである。
//
// ## ロケールについて
// `RecognizeFromFile` にも `BatchRecognition` のコンストラクタにも、
// `SpeechRecognitionModel` のどのメンバーにも、ロケールを渡す口は無い
// (design.md §8 未決事項2、確定済み)。`TranscribeRequest.locale` は
// ここまで到達しない。
//
// ## スレッドとキャンセル
// Media Foundation の変換は同期APIで長時間ブロックしうるため、専用の
// バックグラウンドスレッドで実行する。同じスレッド上で WinRT 非同期を
// `get()` でブロック待機する(C++/WinRT のドキュメントが「呼び出し元
// スレッドをブロックする」手法として示すもの。MTA スレッドでのみ有効で
// あり、本実装はスレッド開始時に MTA として初期化する)。
// キャンセルは実行中の `IAsyncOperation::Cancel()` と、変換前・変換後の
// チェックポイントに置いたフラグの両方で効かせる。
#ifndef OFFLINE_STT_WINDOWS_RECOGNITION_SESSION_H_
#define OFFLINE_STT_WINDOWS_RECOGNITION_SESSION_H_

#include <functional>
#include <memory>
#include <optional>
#include <string>

#include "windows_transcribe_error.h"

namespace offline_stt_windows {

class RecognitionSession {
 public:
  RecognitionSession();
  ~RecognitionSession();

  RecognitionSession(const RecognitionSession&) = delete;
  RecognitionSession& operator=(const RecognitionSession&) = delete;

  // 即座に戻る。`on_complete` はバックグラウンドスレッドから1回だけ
  // 呼ばれる(成功なら認識テキスト(UTF-8)と `std::nullopt`、失敗なら
  // 空文字列とエラー)。
  void Start(std::string file_path_utf8,
             std::function<void(std::string, std::optional<TranscribeError>)>
                 on_complete);

  // 実行中であればキャンセルを要求する。
  void Cancel();

 private:
  struct State;
  std::shared_ptr<State> state_;
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_RECOGNITION_SESSION_H_
