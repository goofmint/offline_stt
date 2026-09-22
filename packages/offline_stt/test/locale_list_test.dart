// `supportedLocales()`(requirements.md FR-5)の純粋ロジックの単体テスト。
//
// 実際の列挙はネイティブAPI(`RecognitionSupport` の3リスト、
// `SpeechTranscriber.supportedLocales`)とブラウザAPI
// (`speechSynthesis.getVoices()` + `SpeechRecognition.available()`)が
// 行うため単体テストできない。本パッケージの方針どおり、それらに依存
// しない判断部分だけを `lib/src/locale_list.dart` へ切り出して検証する。
// ネイティブ・ブラウザ込みの確認は実機E2E
// (`apps/example/integration_test/`)と `docs/e2e/` の手動チェックリストで
// 行う。

import 'package:offline_stt/src/common.dart';
import 'package:offline_stt/src/locale_list.dart';
import 'package:test/test.dart';

import 'fakes/fake_offline_transcriber_platform.dart';

void main() {
  group('dedupeLocaleTags', () {
    test('重複が無ければ順序も綴りもそのまま返す', () {
      expect(dedupeLocaleTags(<String>['ja-JP', 'en-US', 'fr-FR']), <String>[
        'ja-JP',
        'en-US',
        'fr-FR',
      ]);
    });

    test('完全に同じタグの重複を除く', () {
      expect(dedupeLocaleTags(<String>['ja-JP', 'en-US', 'ja-JP']), <String>[
        'ja-JP',
        'en-US',
      ]);
    });

    test('大文字小文字だけが違うタグは同一とみなし、最初の綴りを残す', () {
      // BCP-47のサブタグは大文字小文字を区別しない(RFC 5646 §2.1)。
      // `getVoices()` の `lang` には綴り違いの重複が混ざり得る。
      expect(dedupeLocaleTags(<String>['en-US', 'en-us', 'EN-US']), <String>[
        'en-US',
      ]);
    });

    test('前後の空白を取り除いたうえで比較する', () {
      expect(dedupeLocaleTags(<String>[' ja-JP ', 'ja-JP']), <String>['ja-JP']);
    });

    test('空文字・空白のみのタグは候補にしない', () {
      expect(dedupeLocaleTags(<String>['', '   ', 'ja-JP']), <String>['ja-JP']);
    });

    test('候補が1つも無ければ空リストを返す(判断は呼び出し側)', () {
      // この関数は重複除去だけを担う。空を例外にするかどうかは
      // [requireNonEmptyLocales] の責務である。
      expect(dedupeLocaleTags(<String>[]), isEmpty);
    });
  });

  group('requireNonEmptyLocales', () {
    test('空でなければそのまま返す', () {
      final locales = <String>['ja-JP', 'en-US'];
      expect(requireNonEmptyLocales(locales), same(locales));
    });

    test('空リストはフォールバックせず DeviceUnsupportedException を投げる', () {
      // 「1つも扱えない端末」と「そもそも列挙できなかった」を空リストで
      // 区別できないため、空リストを返すことを禁じている。
      expect(
        () => requireNonEmptyLocales(<String>[]),
        throwsA(isA<DeviceUnsupportedException>()),
      );
    });
  });

  group('OfflineTranscriberPlatform.supportedLocales の契約', () {
    test('一覧を返す', () async {
      final platform = FakeOfflineTranscriberPlatform()
        ..localeCatalog = <String>['ja-JP', 'en-US', 'fr-FR'];
      expect(await platform.supportedLocales(), <String>[
        'ja-JP',
        'en-US',
        'fr-FR',
      ]);
    });

    test('checkModel が unavailable でも一覧は返る', () async {
      // `supportedLocales()` は「available なロケールの一覧」ではなく
      // 「このプラットフォームが扱えるロケールの集合」である。モデルが
      // 未ダウンロードでも一覧には出る。
      final platform = FakeOfflineTranscriberPlatform();
      expect(await platform.checkModel('ja-JP'), ModelState.unavailable);
      expect(await platform.supportedLocales(), contains('ja-JP'));
    });

    test('列挙できない場合は空リストではなく例外になる', () async {
      final platform = FakeOfflineTranscriberPlatform()
        ..localeCatalog = <String>[];
      await expectLater(
        platform.supportedLocales(),
        throwsA(isA<DeviceUnsupportedException>()),
      );
    });
  });
}
