# Changelog

## 0.2.0

- Added `supportedLocales()`, which lists the BCP 47 locales the platform can
  handle. It is not a list of what is downloaded — check a locale with
  `checkModel()` before transcribing. It never returns an empty list; when the
  platform has no way to enumerate locales it throws
  `DeviceUnsupportedException`.

## 0.1.1

- Rewrote the README in English, aimed at people reading it for the first time.

## 0.1.0

First release.

- `OfflineTranscriber` with three methods: `checkModel`, `downloadModel`,
  `transcribeFile`.
- Android, iOS, macOS and Web, in one package. Add `offline_stt` and the right
  implementation is picked for you.
- Audio never leaves the device. No model files are bundled — the OS downloads
  and manages them.

### Known limits

Japanese accuracy is below what we consider shippable: around 67% keyword
coverage on our benchmark clip, on every platform we measured. English is
better but inconsistent on longer audio. Measure with your own audio before
adopting this.
