// ブラウザAPIに依存しない純粋な文字列整形のみを検証する。切り分け方針は
// lib/src/final_text_formatting.dart 冒頭コメントを参照。

import 'package:offline_stt_web/src/final_text_formatting.dart';
import 'package:test/test.dart';

void main() {
  group('stripChromeSegmentationWhitespace (CJKロケール)', () {
    test('形態素単位の半角スペースを除去する(spikes/web/RESULTS.md実測例)', () {
      const input =
          '東京 都 渋谷 で 2024 年 11 月 3 日 午後 3 時 株式会社 ムーン ギフト が 新 製品 '
          'を 発表 し まし た 来場 者 は 128 名 でし た';
      final result = stripChromeSegmentationWhitespace(input, 'ja-JP');
      expect(result, isNot(contains(' ')));
      expect(result, contains('東京都渋谷で2024年11月3日'));
    });

    test('全角スペース・タブ・改行も除去する', () {
      const input = 'a　b\tc\nd';
      expect(stripChromeSegmentationWhitespace(input, 'ja-JP'), 'abcd');
    });

    test('空白の無い文字列はそのまま返す', () {
      expect(stripChromeSegmentationWhitespace('hello', 'ja-JP'), 'hello');
    });

    test('空文字列は空文字列のまま', () {
      expect(stripChromeSegmentationWhitespace('', 'ja-JP'), '');
    });

    test('zh / ko も除去対象である', () {
      expect(stripChromeSegmentationWhitespace('北 京', 'zh-CN'), '北京');
      expect(stripChromeSegmentationWhitespace('서 울', 'ko-KR'), '서울');
    });
  });

  group('stripChromeSegmentationWhitespace (非CJKロケール)', () {
    test('en-US では語間の空白を保持する', () {
      // 語間の空白を除去すると認識結果が壊れるため、除去してはならない。
      expect(
        stripChromeSegmentationWhitespace('hello world', 'en-US'),
        'hello world',
      );
    });

    test('他の非CJKロケールでも保持する', () {
      expect(
        stripChromeSegmentationWhitespace('bonjour le monde', 'fr-FR'),
        'bonjour le monde',
      );
      expect(
        stripChromeSegmentationWhitespace('hallo welt', 'de-DE'),
        'hallo welt',
      );
    });

    test('判定は言語サブタグのみで行い、地域サブタグは見ない', () {
      expect(stripChromeSegmentationWhitespace('あ い', 'ja'), 'あい');
      expect(stripChromeSegmentationWhitespace('a b', 'en'), 'a b');
    });
  });
}
