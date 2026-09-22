# offline_stt

Transcribe audio files offline, using only the speech recognition built into the operating system.

Nothing is sent over the network. No model files ship with this package — the OS downloads and manages them.

## Install

```yaml
dependencies:
  offline_stt: ^0.1.1
```

## Use

```dart
import 'package:offline_stt/offline_stt.dart';

const transcriber = OfflineTranscriber();

// 1. Is the language model ready?
var state = await transcriber.checkModel('en-US');

// 2. If not, ask the user, then download it.
if (state == ModelState.downloadable) {
  await for (final progress in transcriber.downloadModel('en-US')) {
    print(progress.fraction); // null when the OS reports no percentage
  }
  state = await transcriber.checkModel('en-US');
}

// 3. Transcribe.
await for (final segment in transcriber.transcribeFile(
  TranscribeRequest(path: '/path/to/audio.m4a', locale: 'en-US'),
)) {
  if (segment.isFinal) print(segment.text);
}
```

That's the whole API: `checkModel`, `downloadModel`, `transcribeFile`.

### Model states

| State | Meaning |
|---|---|
| `available` | Ready. Call `transcribeFile`. |
| `downloadable` | Ask the user, then call `downloadModel`. |
| `downloading` | Already in progress. Wait. |
| `unavailable` | This device or browser can't do it. |

**The library never downloads anything on its own.** Show your own consent dialog first — models can be large and the connection may be metered.

### Partial results

`transcribeFile` returns a stream. Segments with `isFinal: false` are live guesses that may change; `isFinal: true` segments are settled. Show partials for feedback, keep the finals.

## Supported platforms

| Platform | Minimum version |
|---|---|
| Android | Android 13 (API 33) |
| iOS | iOS 26 |
| macOS | macOS 26 |
| Web | Chrome 142+, desktop, served over https or localhost |

Android 12 (API 31) compiles, but `checkModel` always returns `unavailable` — the API it needs arrived in API 33.

Linux and Windows are not supported. Neither ships an on-device speech API this package can use.

## Before you adopt this

- **Japanese accuracy is not good enough yet.** On our benchmark clip, iOS, macOS, Android and Chrome all land around 67%, and every one of them misheard the company name in the recording. English does better — 100% on a 10-second clip on Android — but is also inconsistent on longer audio. Measure with your own audio before committing.
- **The minimum OS versions are high.** iOS 26 and macOS 26 rule out most devices in use today.
- **Audio files only.** No live microphone input.
- **One transcription at a time.** Starting a second one while the first is running throws a `StateError`.
- **Accuracy follows the OS.** The recognition model belongs to the platform and is updated by it, so the same audio may transcribe differently after a system update.

This is a 0.x release because the underlying OS APIs are themselves new.

## Errors

Everything throws a subclass of `TranscribeException`:

| Exception | When |
|---|---|
| `ModelUnavailableException` | The model isn't ready |
| `LocaleUnsupportedException` | The OS doesn't have that language |
| `DecodeFailedException` | The file isn't audio, or the codec isn't supported |
| `DeviceUnsupportedException` | The device or browser can't do on-device recognition |
| `CancelledException` | You cancelled the stream |
| `PlatformException_` | Anything else the OS reported |

## Setup

Nothing beyond the dependency. No permissions to declare — the library reads files you hand it and never touches the microphone.

On the web, serve over https or localhost. Chrome requires it for on-device recognition.

## Example

A complete app with a file picker, consent dialog and progress UI lives in
[`apps/example`](https://github.com/goofmint/offline_stt/tree/main/apps/example).

## License

MIT
