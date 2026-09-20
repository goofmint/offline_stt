// platform_thread_dispatcher.cpp
#include "platform_thread_dispatcher.h"

namespace offline_stt_windows {

namespace {

constexpr wchar_t kWindowClassName[] =
    L"OfflineSttWindowsPlatformThreadDispatcher";

// `WM_USER` 以降はアプリケーション定義のメッセージとして使ってよい
// (Win32 の標準規約)。message-only window を専有しているため衝突しない。
constexpr UINT kRunTasksMessage = WM_USER + 1;

}  // namespace

PlatformThreadDispatcher::PlatformThreadDispatcher() {
  const HINSTANCE instance = ::GetModuleHandle(nullptr);

  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = PlatformThreadDispatcher::WndProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClassName;
  // 同一プロセス内で2回登録されうる(ホットリスタート等でプラグインが
  // 作り直される場合)。既に登録済みなら `RegisterClassExW` は
  // `ERROR_CLASS_ALREADY_EXISTS` で失敗するが、その場合もクラス自体は
  // 使えるので続行する。
  ::RegisterClassExW(&window_class);

  window_ = ::CreateWindowExW(0, kWindowClassName, L"", 0, 0, 0, 0, 0,
                              HWND_MESSAGE, nullptr, instance, this);
  if (window_ != nullptr) {
    ::SetWindowLongPtr(window_, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(this));
  }
}

PlatformThreadDispatcher::~PlatformThreadDispatcher() {
  if (window_ != nullptr) {
    ::SetWindowLongPtr(window_, GWLP_USERDATA, 0);
    ::DestroyWindow(window_);
    window_ = nullptr;
  }
}

void PlatformThreadDispatcher::Post(std::function<void()> task) {
  if (window_ == nullptr) return;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    tasks_.push_back(std::move(task));
  }
  ::PostMessage(window_, kRunTasksMessage, 0, 0);
}

void PlatformThreadDispatcher::DrainTasks() {
  // タスク実行中に別スレッドから `Post` されても詰まらないよう、
  // キューごと取り出してからロックを解放して実行する。
  std::deque<std::function<void()>> pending;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    pending.swap(tasks_);
  }
  for (auto& task : pending) {
    task();
  }
}

LRESULT CALLBACK PlatformThreadDispatcher::WndProc(HWND hwnd, UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  if (message == kRunTasksMessage) {
    auto* self = reinterpret_cast<PlatformThreadDispatcher*>(
        ::GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (self != nullptr) {
      self->DrainTasks();
    }
    return 0;
  }
  return ::DefWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace offline_stt_windows
