// audio_conversion.cpp
//
// Issue #54。設計上の判断と未検証事項は audio_conversion.h のコメントを参照。
#include "audio_conversion.h"

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

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <objbase.h>

#include <cstdint>
#include <cstdio>
#include <vector>

#include "string_conversion.h"

namespace offline_stt_windows {

namespace {

// COM/MFのスマートポインタ代わり。WRL/ATLへの依存を増やさないための最小実装。
template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  ~ComPtr() { Reset(); }
  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  T** GetAddressOf() { return &ptr_; }
  T* Get() const { return ptr_; }
  T* operator->() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }

  void Reset() {
    if (ptr_ != nullptr) {
      ptr_->Release();
      ptr_ = nullptr;
    }
  }

 private:
  T* ptr_ = nullptr;
};

TranscribeError DecodeFailed(const std::string& context, HRESULT hr) {
  // Media Foundation 由来の失敗は design.md §5 Windows列の
  // 「DecodeFailed <- Media Foundation失敗」に該当する。
  // `ClassifyHResult` は MF のHRESULT帯を DecodeFailed へ寄せるが、
  // 帯に入らない汎用エラー(E_INVALIDARG 等)も MF の呼び出しで起きうる。
  // 本関数の呼び出し元はすべて MF の API なので、ここでは分類を
  // DecodeFailed に固定し、生のHRESULTはメッセージに残す。
  TranscribeError classified = ClassifyHResult(hr, context);
  classified.code = TranscribeErrorCode::kDecodeFailed;
  return classified;
}

// 一時ファイルのパスを作る。`GetTempFileNameW` は拡張子 `.tmp` を強制する
// ため使わず、GUID で一意な `.wav` 名を作る。
bool MakeTemporaryWavPath(std::wstring* out_path) {
  wchar_t temp_dir[MAX_PATH + 1] = {};
  const DWORD length = ::GetTempPathW(MAX_PATH + 1, temp_dir);
  if (length == 0 || length > MAX_PATH) return false;

  GUID guid = {};
  if (FAILED(::CoCreateGuid(&guid))) return false;
  wchar_t guid_text[40] = {};
  if (::StringFromGUID2(guid, guid_text, 40) == 0) return false;

  *out_path = std::wstring(temp_dir) + L"offline_stt_" + guid_text + L".wav";
  return true;
}

// RIFF/WAVE ヘッダーを書く。`data_size` が確定してから呼ぶ必要があるため、
// 先に 44 バイトのプレースホルダを書いておき、最後に巻き戻して書き直す。
void WriteWavHeader(std::FILE* file, uint32_t data_size) {
  const uint16_t channels = static_cast<uint16_t>(kOutputChannels);
  const uint32_t sample_rate = kOutputSampleRate;
  const uint16_t bits = static_cast<uint16_t>(kOutputBitsPerSample);
  const uint16_t block_align = static_cast<uint16_t>(channels * bits / 8);
  const uint32_t byte_rate = sample_rate * block_align;
  const uint32_t riff_size = 36 + data_size;
  const uint32_t fmt_size = 16;
  const uint16_t format_tag = 1;  // WAVE_FORMAT_PCM

  std::fwrite("RIFF", 1, 4, file);
  std::fwrite(&riff_size, sizeof(riff_size), 1, file);
  std::fwrite("WAVE", 1, 4, file);
  std::fwrite("fmt ", 1, 4, file);
  std::fwrite(&fmt_size, sizeof(fmt_size), 1, file);
  std::fwrite(&format_tag, sizeof(format_tag), 1, file);
  std::fwrite(&channels, sizeof(channels), 1, file);
  std::fwrite(&sample_rate, sizeof(sample_rate), 1, file);
  std::fwrite(&byte_rate, sizeof(byte_rate), 1, file);
  std::fwrite(&block_align, sizeof(block_align), 1, file);
  std::fwrite(&bits, sizeof(bits), 1, file);
  std::fwrite("data", 1, 4, file);
  std::fwrite(&data_size, sizeof(data_size), 1, file);
}

}  // namespace

AudioConversionResult ConvertToPcmWav(const std::string& input_path_utf8) {
  AudioConversionResult result;

  std::wstring input_path;
  if (!Utf8ToWide(input_path_utf8, &input_path) || input_path.empty()) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kDecodeFailed;
    error.message =
        "offline_stt_windows: 入力パスをUTF-16へ変換できなかった(不正な"
        "UTF-8、または空のパス)。";
    result.error = error;
    return result;
  }

  // Media Foundation は使用前に `MFStartup` が必要。対になる `MFShutdown` は
  // スコープを抜けるときに必ず呼ぶ。
  HRESULT hr = ::MFStartup(MF_VERSION, MFSTARTUP_LITE);
  if (FAILED(hr)) {
    result.error = DecodeFailed("MFStartup", hr);
    return result;
  }
  struct MfShutdownGuard {
    ~MfShutdownGuard() { ::MFShutdown(); }
  } mf_shutdown_guard;

  ComPtr<IMFSourceReader> reader;
  hr = ::MFCreateSourceReaderFromURL(input_path.c_str(), nullptr,
                                     reader.GetAddressOf());
  if (FAILED(hr)) {
    // ファイルが開けない・対応するデマルチプレクサ/デコーダが無い場合は
    // ここで失敗する。requirements.md FR-4「デコード不能なファイルは明確な
    // エラー型で通知」に相当する。
    result.error = DecodeFailed("MFCreateSourceReaderFromURL", hr);
    return result;
  }

  // 音声ストリームだけを有効にする。
  hr = reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE);
  if (SUCCEEDED(hr)) {
    hr = reader->SetStreamSelection(MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE);
  }
  if (FAILED(hr)) {
    result.error = DecodeFailed("SetStreamSelection", hr);
    return result;
  }

  // 出力メディアタイプに PCM を要求すると、Source Reader が必要なデコーダと
  // リサンプラーを内部に挿し込む(Source Reader の標準的な使い方)。
  ComPtr<IMFMediaType> output_type;
  hr = ::MFCreateMediaType(output_type.GetAddressOf());
  if (SUCCEEDED(hr)) {
    hr = output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  }
  if (SUCCEEDED(hr)) {
    hr = output_type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  }
  if (SUCCEEDED(hr)) {
    hr = output_type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,
                                kOutputBitsPerSample);
  }
  if (SUCCEEDED(hr)) {
    hr = output_type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,
                                kOutputSampleRate);
  }
  if (SUCCEEDED(hr)) {
    hr = output_type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kOutputChannels);
  }
  if (FAILED(hr)) {
    result.error = DecodeFailed("MFCreateMediaType", hr);
    return result;
  }
  hr = reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, nullptr,
                                   output_type.Get());
  if (FAILED(hr)) {
    // 要求した 16kHz モノラル 16-bit へ変換できない場合(入力に音声ストリーム
    // が無い等)もここで失敗する。
    result.error = DecodeFailed("SetCurrentMediaType(PCM 16k mono)", hr);
    return result;
  }

  std::wstring output_path;
  if (!MakeTemporaryWavPath(&output_path)) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kDecodeFailed;
    error.message =
        "offline_stt_windows: 一時ファイルのパスを作成できなかった"
        "(GetTempPathW / CoCreateGuid の失敗)。";
    result.error = error;
    return result;
  }

  std::FILE* file = nullptr;
  if (::_wfopen_s(&file, output_path.c_str(), L"wb") != 0 || file == nullptr) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kDecodeFailed;
    error.message =
        "offline_stt_windows: 一時wavファイルを作成できなかった。";
    result.error = error;
    return result;
  }
  // 途中でエラー終了した場合、書きかけの一時ファイルを残さない
  // (`committed` が立つのは最後まで成功したときだけ)。
  struct FileGuard {
    std::FILE* f;
    std::wstring path;
    bool committed = false;
    ~FileGuard() {
      if (f != nullptr) std::fclose(f);
      if (!committed) DeleteTemporaryFile(path);
    }
  } file_guard{file, output_path};

  // データ長が確定するまでヘッダーは書けないので、同じサイズの
  // プレースホルダを先に書いておき、最後に巻き戻して上書きする。
  WriteWavHeader(file, 0);

  uint64_t total_bytes = 0;
  for (;;) {
    DWORD stream_flags = 0;
    ComPtr<IMFSample> sample;
    hr = reader->ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, nullptr,
                            &stream_flags, nullptr, sample.GetAddressOf());
    if (FAILED(hr)) {
      result.error = DecodeFailed("ReadSample", hr);
      return result;
    }
    if ((stream_flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0) {
      break;
    }
    if ((stream_flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) != 0) {
      // 出力タイプを固定しているため本来起きない。起きた場合、以降の
      // サンプルが要求と違う形式になり、黙って続けると壊れたwavができる。
      // 取り繕わずエラーにする。
      TranscribeError error;
      error.code = TranscribeErrorCode::kDecodeFailed;
      error.message =
          "offline_stt_windows: デコード中に出力メディアタイプが変化した。"
          "要求した 16kHz モノラル 16-bit PCM を維持できないため中断する。";
      result.error = error;
      return result;
    }
    if (!sample) {
      // ギャップ等でサンプルが返らないことがある(ストリーム終端ではない)。
      continue;
    }

    ComPtr<IMFMediaBuffer> buffer;
    hr = sample->ConvertToContiguousBuffer(buffer.GetAddressOf());
    if (FAILED(hr)) {
      result.error = DecodeFailed("ConvertToContiguousBuffer", hr);
      return result;
    }

    BYTE* data = nullptr;
    DWORD current_length = 0;
    hr = buffer->Lock(&data, nullptr, &current_length);
    if (FAILED(hr)) {
      result.error = DecodeFailed("IMFMediaBuffer::Lock", hr);
      return result;
    }
    const size_t written = std::fwrite(data, 1, current_length, file);
    buffer->Unlock();
    if (written != current_length) {
      TranscribeError error;
      error.code = TranscribeErrorCode::kDecodeFailed;
      error.message =
          "offline_stt_windows: 一時wavファイルへの書き込みに失敗した"
          "(ディスク空き容量不足の可能性)。";
      result.error = error;
      return result;
    }
    total_bytes += current_length;

    // RIFF は 32bit のサイズフィールドしか持たない。4GiB を超える音声は
    // 表現できないため、黙って切り詰めずエラーにする。
    if (total_bytes > 0xFFFFFFFFULL - 36ULL) {
      TranscribeError error;
      error.code = TranscribeErrorCode::kDecodeFailed;
      error.message =
          "offline_stt_windows: 変換後のPCMがRIFF WAVEの上限(4GiB)を超えた。"
          "音声が長すぎる。";
      result.error = error;
      return result;
    }
  }

  if (total_bytes == 0) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kDecodeFailed;
    error.message =
        "offline_stt_windows: 入力から音声サンプルを1つも取り出せなかった。";
    result.error = error;
    return result;
  }

  // 先頭へ巻き戻して本物のヘッダーを書き直す。
  if (std::fseek(file, 0, SEEK_SET) != 0) {
    TranscribeError error;
    error.code = TranscribeErrorCode::kDecodeFailed;
    error.message =
        "offline_stt_windows: 一時wavファイルのヘッダーを書き直せなかった。";
    result.error = error;
    return result;
  }
  WriteWavHeader(file, static_cast<uint32_t>(total_bytes));

  file_guard.committed = true;
  result.output_path = output_path;
  return result;
}

void DeleteTemporaryFile(const std::wstring& path) {
  if (path.empty()) return;
  ::DeleteFileW(path.c_str());
}

}  // namespace offline_stt_windows
