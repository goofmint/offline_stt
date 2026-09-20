// ネイティブ(windows/model_availability.cpp の AIFeatureReadyState → 4値
// 写像)に依存しない、Pigeon enum名 -> ModelState の純粋写像のみを検証する。
// 切り分け方針は lib/src/model_state_mapping.dart 冒頭コメントを参照。

import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:offline_stt_windows/src/model_state_mapping.dart';
import 'package:test/test.dart';

void main() {
  group('mapPigeonModelState', () {
    test('available を写像する', () {
      expect(mapPigeonModelState('available'), ModelState.available);
    });

    test('downloadable を写像する', () {
      expect(mapPigeonModelState('downloadable'), ModelState.downloadable);
    });

    test('downloading を写像する', () {
      expect(mapPigeonModelState('downloading'), ModelState.downloading);
    });

    test('unavailable を写像する', () {
      expect(mapPigeonModelState('unavailable'), ModelState.unavailable);
    });

    test('未知の値はフォールバックで丸めず StateError を投げる', () {
      expect(() => mapPigeonModelState('bogus'), throwsStateError);
    });

    test('AIFeatureReadyState の生の名前をそのまま渡すことはできない', () {
      // FR-1の4値への写像はネイティブ側(windows/model_availability.cpp)の
      // 責務であり、Dart側は4値しか受け取らない契約であることを固定する。
      // `NotReady` 等がDartまで漏れてきたら写像漏れなので StateError。
      expect(() => mapPigeonModelState('NotReady'), throwsStateError);
      expect(
        () => mapPigeonModelState('NotSupportedOnCurrentSystem'),
        throwsStateError,
      );
    });
  });
}
