// platform_thread_dispatcher.h
//
// design.md §6「Windows: WinRT asyncをcoroutine(C++/WinRT)で待機、結果は
// platform threadへdispatch」を満たすための仕組み(Issue #52)。
//
// ## なぜ必要か
// Flutter の `flutter::BinaryMessenger`(Pigeon生成の
// `OfflineSttStreamCallbackApi` が内部で使う)は、Windows 埋め込みでは
// プラットフォームスレッド(= Flutter のメッセージループが回っているスレッド、
// 通常はプロセスのメインスレッド)からのみ呼び出してよい。一方 C++/WinRT の
// 非同期処理の完了ハンドラ・コルーチンの再開は任意のスレッドプールスレッドで
// 走る。したがってネイティブ→Dartのコールバックは必ずここを経由して
// プラットフォームスレッドへ戻す。
// darwin 実装の `EventChannelWrappers.swift` が `DispatchQueue.main.async` で
// 統一しているのと同じ役割である。
//
// ## 実装方式(メッセージ専用ウィンドウ)と、その選択理由
// Win32 の message-only window(`HWND_MESSAGE` を親に持つウィンドウ)を
// プラットフォームスレッド上で生成し、`PostMessage` でタスクの到着を知らせる。
// Flutter の Windows ランナーは標準的な `GetMessage`/`DispatchMessage` の
// メッセージループを回しているため、投函したメッセージはプラットフォーム
// スレッドの `WndProc` で処理される。
//
// 他に検討した方式と見送った理由:
// - `winrt::apartment_context` を登録時に取得して `co_await` する方式:
//   プラットフォームスレッドが COM アパートメントを初期化済みであることに
//   依存する。Flutter の Windows 埋め込みがどう初期化しているかを本リポジトリ
//   からは確認できず、前提が崩れると静かに別スレッドへ再開しうるため見送った。
// - `FlutterDesktopMessenger` のロックAPIを直接使う方式:
//   `flutter::BinaryMessenger` の C++ ラッパー越しには露出しておらず、
//   Pigeon 生成コードがそのラッパーを使う以上、適用できない。
//
// ## 破棄と「投函済みタスク」の扱い(Issue #59 / CodeRabbit 指摘対応)
// このディスパッチャが配送するタスクは、`StreamCallbackSender` を経由して
// 最終的に Pigeon 生成の `OfflineSttStreamCallbackApi`(= Flutter の
// `BinaryMessenger`)を叩く。`BinaryMessenger` はプラグイン(= エンジン)の
// 破棄後には触れてはならないため、**破棄後にタスクが1件でも走る余地を
// 残してはならない**。
// そのため `Shutdown()` を用意し、
//   1. 以後の `Post()` を受け付けなくする
//   2. 未実行タスクをその場で破棄する
//   3. メッセージ専用ウィンドウを破棄する(以後 `WndProc` は呼ばれない)
// の3つを一括で行う。プラグインのデストラクタ(プラットフォームスレッド)
// から呼ぶ。
//
// 未実行タスクをその場で破棄するのは、寿命の循環を断つためでもある。
// タスクは `StreamCallbackSender` の `shared_ptr` を握り、その
// `StreamCallbackSender` はこのディスパッチャの `shared_ptr` を握る。
// キューを空にしない限りこの循環で両者が解放されない。
//
// **未検証**: Windows 実機が無いため、この仕組みが実際に動作することは
// 確認できていない(Issue #58)。
#ifndef OFFLINE_STT_WINDOWS_PLATFORM_THREAD_DISPATCHER_H_
#define OFFLINE_STT_WINDOWS_PLATFORM_THREAD_DISPATCHER_H_

// `<windows.h>` は既定で min/max マクロを定義し、`std::min`/`std::max` を
// 使う標準ヘッダー(Flutter の C++ ラッパーが間接的に取り込む)を壊す。
// Flutter の Windows ランナーテンプレートと同じく NOMINMAX と
// WIN32_LEAN_AND_MEAN を先に定義してから取り込む。
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <deque>
#include <functional>
#include <mutex>
#include <utility>

namespace offline_stt_windows {

class PlatformThreadDispatcher {
 public:
  // **必ずプラットフォームスレッド上で構築すること**(プラグイン登録時)。
  // ウィンドウはそれを生成したスレッドに結び付くため、別スレッドで構築すると
  // タスクがそのスレッドで実行されてしまう。
  PlatformThreadDispatcher();
  ~PlatformThreadDispatcher();

  PlatformThreadDispatcher(const PlatformThreadDispatcher&) = delete;
  PlatformThreadDispatcher& operator=(const PlatformThreadDispatcher&) = delete;

  // 任意のスレッドから呼べる。`task` はプラットフォームスレッドで実行される。
  //
  // ウィンドウの生成に失敗していた場合、タスクは実行されない。黙って捨てると
  // 「文字起こし結果が来ない」という形でしか現れず原因が追えなくなるため、
  // 生成失敗は構築時に `IsValid()` で検出し、呼び出し側(プラグイン登録処理)
  // がその場で明確に失敗させる方針とする。
  void Post(std::function<void()> task);

  // **必ずプラットフォームスレッドから呼ぶこと**(プラグインのデストラクタ)。
  // 冪等。呼び出し後は `Post()` は何もせず、未実行タスクも実行されない。
  // デストラクタからも呼ばれるので、明示的に呼ばない経路でも安全側に倒れる。
  void Shutdown();

  bool IsValid() const;

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  void DrainTasks();

  // `window_` は `Post()`(任意のスレッド)と `Shutdown()`(プラットフォーム
  // スレッド)の双方から触られるため、`tasks_` と同じ `mutex_` で守る。
  // 以前は無保護で読んでおり、破棄と `Post()` が競合しうる状態だった。
  mutable std::mutex mutex_;
  HWND window_ = nullptr;
  bool stopped_ = false;
  std::deque<std::function<void()>> tasks_;
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_PLATFORM_THREAD_DISPATCHER_H_
