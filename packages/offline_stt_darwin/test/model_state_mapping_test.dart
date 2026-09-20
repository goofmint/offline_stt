import 'package:offline_stt_darwin/src/model_state_mapping.dart';
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
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
  });
}
