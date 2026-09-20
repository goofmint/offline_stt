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

  bool IsValid() const { return window_ != nullptr; }

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  void DrainTasks();

  HWND window_ = nullptr;
  std::mutex mutex_;
  std::deque<std::function<void()>> tasks_;
};

}  // namespace offline_stt_windows

#endif  // OFFLINE_STT_WINDOWS_PLATFORM_THREAD_DISPATCHER_H_
