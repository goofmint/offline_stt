# Example

```yaml
dependencies:
  offline_stt: ^0.1.1
```

```dart
import 'package:offline_stt/offline_stt.dart';

Future<String> transcribe(String path, String locale) async {
  const transcriber = OfflineTranscriber();

  // The library never downloads a model on its own. Ask the user first.
  var state = await transcriber.checkModel(locale);
  if (state == ModelState.downloadable) {
    await for (final progress in transcriber.downloadModel(locale)) {
      final fraction = progress.fraction;
      if (fraction != null) {
        print('${(fraction * 100).toStringAsFixed(0)}%');
      }
    }
    state = await transcriber.checkModel(locale);
  }

  if (state != ModelState.available) {
    throw StateError('Model is not available: $state');
  }

  // Segments arrive as the audio is processed. Keep the final ones.
  final buffer = StringBuffer();
  await for (final segment in transcriber.transcribeFile(
    TranscribeRequest(path: path, locale: locale),
  )) {
    if (segment.isFinal) buffer.write(segment.text);
  }
  return buffer.toString();
}
```

A complete app — file picker, consent dialog, progress UI — is in
[`apps/example`](https://github.com/goofmint/offline_stt/tree/main/apps/example).

## Worth knowing

- Only one transcription can run at a time. A second `transcribeFile` throws a
  `StateError`.
- Japanese accuracy is around 67% on our benchmark clip. Measure with your own
  audio before adopting this.
