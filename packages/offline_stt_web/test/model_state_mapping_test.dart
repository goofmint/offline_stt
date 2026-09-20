// このテストはブラウザAPIに依存しない純粋な文字列->ModelState写像のみを
// 検証する。ブラウザAPI(SpeechRecognition等)を直接叩く部分は単体テスト
// できないため、`packages/offline_stt_web/E2E_CHECKLIST.md`(Issue #31)の
// 手動チェックリストでカバーする方針である(切り分け方針の詳細は
// lib/src/model_state_mapping.dart 冒頭コメント参照)。

import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:offline_stt_web/src/model_state_mapping.dart';
import 'package:test/test.dart';

void main() {
  group('mapAvailabilityToModelState', () {
    test('available を ModelState.available へ写像する', () {
      expect(mapAvailabilityToModelState('available'), ModelState.available);
    });

    test('downloadable を ModelState.downloadable へ写像する', () {
      expect(
        mapAvailabilityToModelState('downloadable'),
        ModelState.downloadable,
      );
    });

    test('downloading を ModelState.downloading へ写像する', () {
      expect(
        mapAvailabilityToModelState('downloading'),
        ModelState.downloading,
      );
    });

    test('unavailable を ModelState.unavailable へ写像する', () {
      expect(
        mapAvailabilityToModelState('unavailable'),
        ModelState.unavailable,
      );
    });

    test('未知の値はフォールバックせずStateErrorを投げる', () {
      expect(
        () => mapAvailabilityToModelState('something-unexpected'),
        throwsStateError,
      );
    });
  });
}
