// offline_stt_api_impl.cpp
#include "offline_stt_api_impl.h"

#include <utility>

namespace offline_stt_windows {

namespace {

FlutterError ToFlutterError(const TranscribeError& error) {
  return FlutterError(WireCode(error.code), error.message);
}

}  // namespace

OfflineSttApiImpl::OfflineSttApiImpl(
    std::unique_ptr<SpeechBackend> backend,
    std::shared_ptr<StreamCallbackSender> sender)
    : backend_(std::move(backend)),
      context_(std::make_shared<AsyncCallbackContext>()) {
  context_->sender = std::move(sender);
}

// ---------------------------------------------------------------------------
// 破棄 —— Issue #59 / CodeRabbit 指摘「非同期処理の完了前にコールバック対象を
// 破棄しないでください」への対処
// ---------------------------------------------------------------------------
//
// ## なぜ「待たない」のか(共有所有を選んだ理由)
// 指摘は「破棄時にキャンセルして完了を待つ」か「共有所有 + コールバック側で
// 有効性を確認する」かの二択を挙げている。本実装は後者を採った。
//
// 前者(完了待ち)は、このプラグインでは**待ち時間の上限を誰も保証できない**。
//   - 認識側: ワーカースレッドは Media Foundation の同期変換
//     (`ConvertToPcmWav`)の中で長時間ブロックしうる。この変換には
//     中断する手段が無いことを `recognition_session.cpp` のコメントに
//     記載済みである。join するとアプリ終了がその分固まる。
//   - モデル取得側: そもそも join できるスレッドが無い。`EnsureReadyAsync()`
//     の完了ハンドラは WinRT のスレッドプール上で走るため、「待つ」とは
//     条件変数でハンドラの発火を待つことになる。`Cancel()` がどれだけ速く
//     受理されるかは未検証(Issue #58)で、モデルのダウンロードが数分続く
//     可能性を否定できない。
// Windows 実機が無く実測できない以上、「終了時に不定時間ハングしうる」設計を
// 採るのは危険が大きい。共有所有なら待ち時間はゼロで、かつ
// use-after-free も起きない。
//
// ## デッドロックしないことの確認
// 仮に将来 join する形へ変えるとしても、少なくとも
// 「プラットフォームスレッドがワーカーを待ち、ワーカーがプラットフォーム
// スレッドを待つ」という循環は無い。`PlatformThreadDispatcher::Post()` は
// `PostMessage`(非同期投函)であって `SendMessage`(同期呼び出し)では
// ないため、ワーカースレッドがプラットフォームスレッドの応答を待つ箇所が
// 存在しないからである。
// 本実装は待たないので、この経路でデッドロックは起きない。
//
// ## 破棄後に起きること
// `Shutdown()` の後にコールバックが走っても、触るのは `AsyncCallbackContext`
// (`shared_ptr` で生き続ける)と、停止済みの `StreamCallbackSender` だけで
// ある。`Send*()` は何もしないので、Dart へは1件も届かない。Dart 側の
// ストリームはエンジンごと消えているため、届ける先がそもそも無い。
void OfflineSttApiImpl::Shutdown() {
  // 先に配送を止める。これ以降 `backend_->Cancel()` が誘発する
  // `kCancelled` 完了コールバックも Dart へは流れない。
  context_->sender->Shutdown();
  // OS 側にダウンロードや認識を走らせたままにしないよう、キャンセルは要求
  // する(完了は待たない)。実行中でなければ何もしない契約
  // (`speech_backend.h`)。
  backend_->Cancel();
}

// ---------------------------------------------------------------------------
// FR-1 モデル状態確認(Issue #53)
// ---------------------------------------------------------------------------

void OfflineSttApiImpl::CheckModel(
    const std::string& locale,
    std::function<void(ErrorOr<ModelState> reply)> result) {
  // design.md §4.4 / §8 未決事項2: `Microsoft.Windows.AI.Speech` には
  // ロケール・言語を指定するAPIが存在しないことがドキュメント調査で確定
  // している。したがって `locale` は状態判定に使えない。無視することが
  // 仕様であり、ここで既定ロケールを捏造するようなことはしない。
  // 「どの言語で認識されるか」はOS側の設定に依存する(READMEに明記する
  // のはIssue #57の担当範囲)。
  (void)locale;

  // `EnsureReadyAsync()` 実行中は `downloading` を返す(理由は
  // `offline_stt_api_impl.h` の `ensure_ready_in_flight_` のコメント参照)。
  // 先に判定するのは、ダウンロード中に `GetReadyState()` が返す値が
  // `NotReady` のままなのか、それとも別の値になるのかが未検証だからである。
  // 実行中であることはこのプラグイン自身が知っている確かな事実なので、
  // 未検証の推測より優先する。
  if (context_->ensure_ready_in_flight.load()) {
    result(ModelState::kDownloading);
    return;
  }

  ModelStateResult query = backend_->QueryModelState();
  if (query.error.has_value()) {
    result(ToFlutterError(*query.error));
    return;
  }
  if (!query.state.has_value()) {
    // `SpeechBackend` の契約違反。既定値で埋めず明確にエラーにする。
    result(FlutterError(
        WireCode(TranscribeErrorCode::kPlatformError),
        "offline_stt_windows: SpeechBackend::QueryModelState() が状態も"
        "エラーも返さなかった(実装の不具合)。"));
    return;
  }
  result(*query.state);
}

// ---------------------------------------------------------------------------
// FR-2 モデルダウンロード(Issue #53)
// ---------------------------------------------------------------------------

std::optional<FlutterError> OfflineSttApiImpl::DownloadModel(
    const std::string& locale) {
  (void)locale;  // 上記 CheckModel と同じ理由でロケールは使えない。

  if (context_->operation_in_flight.exchange(true)) {
    // ストリームはDart側で既に張られているため、同期エラーではなく
    // ストリームのエラーとして返す(design.md §3細則2と同じ流儀)。
    TranscribeError error;
    error.code = TranscribeErrorCode::kPlatformError;
    error.message =
        "offline_stt_windows: 既に別の操作(ダウンロードまたは文字起こし)が"
        "実行中である。design.md §3 のとおり同時実行は1本に制限される。";
    context_->sender->SendError(error);
    context_->sender->SendDone();
    return std::nullopt;
  }

  // design.md §3 細則3: `downloadable` 以外の状態で呼ばれた場合は、
  // 状態を一切変化させず、何も emit せずに完了するStreamを返す。
  ModelStateResult query = backend_->QueryModelState();
  if (query.error.has_value()) {
    context_->sender->SendError(*query.error);
    context_->sender->SendDone();
    context_->operation_in_flight.store(false);
    return std::nullopt;
  }
  if (query.state != ModelState::kDownloadable) {
    context_->sender->SendDone();
    context_->operation_in_flight.store(false);
    return std::nullopt;
  }

  context_->ensure_ready_in_flight.store(true);

  // FR-2: 開始した時点で1件目の進捗を送る。Windowsは常に不定進捗
  // (`fraction = std::nullopt`)である。理由は `model_acquisition.h` 参照。
  context_->sender->SendDownloadProgress(std::nullopt, false);

  // コールバックは `this` ではなく共有状態(`context_`)を捕捉する。
  // プラグインが先に破棄されてもここで解放済みメモリに触らないための要。
  backend_->StartEnsureReady(
      [context = context_]() {
        // `SpeechRecognitionModelProgress` の値は使わず、進捗が動いたこと
        // だけを不定進捗として通知する(理由は `model_acquisition.h`)。
        context->sender->SendDownloadProgress(std::nullopt, false);
      },
      [context = context_](std::optional<TranscribeError> error) {
        context->ensure_ready_in_flight.store(false);
        if (error.has_value()) {
          context->sender->SendError(*error);
        } else {
          context->sender->SendDownloadProgress(std::nullopt, true);
        }
        context->sender->SendDone();
        context->operation_in_flight.store(false);
      });

  return std::nullopt;
}

// ---------------------------------------------------------------------------
// FR-3 ファイル文字起こし(Issue #54 #55)
// ---------------------------------------------------------------------------

std::optional<FlutterError> OfflineSttApiImpl::TranscribeFile(
    const TranscribeRequest& request) {
  if (context_->operation_in_flight.exchange(true)) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kPlatformError;
    error.message =
        "offline_stt_windows: 既に別の操作(ダウンロードまたは文字起こし)が"
        "実行中である。design.md §3 のとおり同時実行は1本に制限される。";
    context_->sender->SendError(error);
    context_->sender->SendDone();
    return std::nullopt;
  }

  // design.md §3 / `pigeons/offline_stt_windows.dart` の `transcribeFile` の
  // docコメント: `checkModel()` が `available` 以外を返す状態で呼ばれた場合、
  // ネイティブ側は即座にエラーを返さなければならない(内部で暗黙的に
  // ダウンロードを開始してはならない)。Dart側
  // (`lib/src/recognition_session.dart`)にも同じガードがあり、二重チェックは
  // 意図的である(スキーマが「ネイティブ側は」と明記しているため)。
  if (context_->ensure_ready_in_flight.load()) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kModelUnavailable;
    error.message =
        "offline_stt_windows: モデルのダウンロード中は文字起こしを開始できない。";
    context_->sender->SendError(error);
    context_->sender->SendDone();
    context_->operation_in_flight.store(false);
    return std::nullopt;
  }
  ModelStateResult query = backend_->QueryModelState();
  if (query.error.has_value()) {
    context_->sender->SendError(*query.error);
    context_->sender->SendDone();
    context_->operation_in_flight.store(false);
    return std::nullopt;
  }
  if (query.state != ModelState::kAvailable) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kModelUnavailable;
    error.message =
        "offline_stt_windows: モデルが available ではない。"
        "downloadModel() でモデルを取得してから呼び出すこと"
        "(design.md §3。暗黙のダウンロードは行わない)。";
    context_->sender->SendError(error);
    context_->sender->SendDone();
    context_->operation_in_flight.store(false);
    return std::nullopt;
  }

  // design.md §2.2 / §7: `playbackRate` はWeb専用オプションであり、
  // Windows(BatchRecognition)はバッチ処理のため速度という概念が無い。
  // Windows向けPigeonスキーマの `TranscribeRequest` には
  // `path` / `locale` しか無いので、無視は自動的に満たされる。
  backend_->StartRecognizeFile(
      request.path(),
      // 上の `StartEnsureReady` と同じ理由で `this` は捕捉しない。
      // 認識ワーカーは `detach()` されており、プラグインより長く生きうる。
      [context = context_](std::string transcript,
                           std::optional<TranscribeError> error) {
        if (error.has_value()) {
          context->sender->SendError(*error);
        } else {
          // design.md §4.4: Windowsバッチ認識は final 1件のみを emit する。
          context->sender->SendSegment(transcript, true);
        }
        context->sender->SendDone();
        context->operation_in_flight.store(false);
      });

  return std::nullopt;
}

// ---------------------------------------------------------------------------
// FR-3 キャンセル(Issue #56)
// ---------------------------------------------------------------------------

std::optional<FlutterError> OfflineSttApiImpl::Cancel() {
  // 実行中でなければ何もしない(冪等)。実行中であれば、キャンセル後に
  // `on_complete` が `kCancelled` で呼ばれ、そこで `SendError` +
  // `SendDone` とフラグの解放が行われる。
  backend_->Cancel();
  return std::nullopt;
}

}  // namespace offline_stt_windows
