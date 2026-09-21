// Darwin(iOS実機 / macOS実機)実機E2E(Issue #40)を自動化した
// integration_test。
//
// `packages/offline_stt_darwin/E2E_CHECKLIST.md` の手順1〜7を、example app の
// UI を人手で操作する代わりに **本番実装(packages/ 配下の Dart + Swift)を
// そのまま呼び出して** 実行する。方針は
// `android_baseline_e2e_test.dart` と同じで、理由も同じである。
//
// - 手順3は基準音声8ファイル分の確定テキストと所要時間を、手順7はキーワード
//   一致の可否を **正確な文字列として** 記録する必要がある。UI をスクリーン
//   ショットで読む方式では確定テキストを取りこぼす。
// - 手順4(キャンセル)・手順5(セッション排他)は `StreamSubscription` の
//   操作そのものが検証対象であり、UI からは再現できない。
//
// example app の UI 経路(ファイルピッカー → 同意ダイアログ → 進行表示)は
// この test では通らない。UI 経路の確認は E2E_CHECKLIST.md の手順を人手で
// 実行して別途行うこと。
//
// ## 基準音声の与え方
//
// Flutter アセット(`assets/baseline-audio/`)として .app へ焼き込み、
// 起動時に `rootBundle` から読み出して**アプリのテンポラリディレクトリへ
// 実ファイルとして書き出す**。本番実装は `AVAudioFile(forReading:)` に実
// パスを渡すため、アセットのままでは読めない。この方式を選んだ理由は
// `tool/stage_baseline_audio.sh` の冒頭に書いた(macOS は App Sandbox、
// iOS 実機はホストのファイルシステムが見えない)。
//
// ## 実行方法
//
// ```
// apps/example/tool/stage_baseline_audio.sh
// cd apps/example
// flutter test integration_test/darwin_baseline_e2e_test.dart -d macos
// flutter test integration_test/darwin_baseline_e2e_test.dart -d <iOS実機のid>
// ```
//
// 標準出力の `E2E|` 始まりの行が測定値である。確定テキストは
// `E2E|FINAL|<clip>|<text>` の形式で1行に出る(改行は `\n` へ畳む)。
//
// 測定値の集計(キーワード包含率)は `test-assets/keyword_score.py` に渡す。
@Timeout(Duration(minutes: 40))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// `setUpAll` がアセットを書き出した先。
late final String assetDir;

/// 基準音声(E2E_CHECKLIST.md 手順3の8ファイル)。
const List<(String clip, String locale)> baselineClips = <(String, String)>[
  ('jaJP_10s.wav', 'ja-JP'),
  ('jaJP_10s.m4a', 'ja-JP'),
  ('enUS_10s.wav', 'en-US'),
  ('enUS_10s.m4a', 'en-US'),
  ('jaJP_3m.wav', 'ja-JP'),
  ('jaJP_3m.m4a', 'ja-JP'),
  ('enUS_3m.wav', 'en-US'),
  ('enUS_3m.m4a', 'en-US'),
];

/// アセットとして焼き込んである全ファイル(手順6の `not_audio.wav` を含む)。
const List<String> bundledFiles = <String>[
  'jaJP_10s.wav',
  'jaJP_10s.m4a',
  'jaJP_3m.wav',
  'jaJP_3m.m4a',
  'enUS_10s.wav',
  'enUS_10s.m4a',
  'enUS_3m.wav',
  'enUS_3m.m4a',
  'not_audio.wav',
];

void log(String line) {
  // ignore: avoid_print
  print('E2E|$line');
}

/// 確定テキスト等を1行のログに載せるため、改行を畳む。
String oneLine(String text) =>
    text.replaceAll('\r', ' ').replaceAll('\n', r'\n');

/// 1本の文字起こしセッションの実測値。
class TranscriptionRun {
  TranscriptionRun(this.clip);

  final String clip;
  final List<String> partials = <String>[];
  final List<String> finals = <String>[];
  Object? error;
  late Duration elapsed;
  var completedNormally = false;
}

Future<TranscriptionRun> runTranscription(
  String clip,
  String locale, {
  double playbackRate = 1.0,
}) async {
  final run = TranscriptionRun(clip);
  final stopwatch = Stopwatch()..start();
  final completer = Completer<void>();
  final subscription = OfflineTranscriberPlatform.instance
      .transcribeFile(
        TranscribeRequest(
          path: '$assetDir/$clip',
          locale: locale,
          playbackRate: playbackRate,
        ),
      )
      .listen(
        (segment) {
          if (segment.isFinal) {
            run.finals.add(segment.text);
          } else {
            run.partials.add(segment.text);
          }
        },
        onError: (Object e) {
          run.error = e;
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          run.completedNormally = true;
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: false,
      );
  await completer.future;
  await subscription.cancel();
  stopwatch.stop();
  run.elapsed = stopwatch.elapsed;
  return run;
}

void reportRun(TranscriptionRun run) {
  log(
    'CLIP|${run.clip}|elapsedMs=${run.elapsed.inMilliseconds}'
    '|partials=${run.partials.length}|finals=${run.finals.length}'
    '|done=${run.completedNormally}|error=${run.error}',
  );
  // partial は3分クリップで数百件出るため、本文は先頭と末尾だけ残す。
  // 件数そのもの(手順3の確認項目)は上の CLIP 行に出ている。
  if (run.partials.isNotEmpty) {
    log('PARTIAL_FIRST|${run.clip}|${oneLine(run.partials.first)}');
    log('PARTIAL_LAST|${run.clip}|${oneLine(run.partials.last)}');
  }
  for (final text in run.finals) {
    log('FINAL|${run.clip}|${oneLine(text)}');
  }
  log('FINAL_JOINED|${run.clip}|${oneLine(run.finals.join(''))}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    log(
      'DEVICE|${Platform.operatingSystem}|${Platform.operatingSystemVersion}',
    );
    final tempDir = await getTemporaryDirectory();
    assetDir = '${tempDir.path}/baseline-audio';
    Directory(assetDir).createSync(recursive: true);
    for (final name in bundledFiles) {
      final data = await rootBundle.load('assets/baseline-audio/$name');
      final file = File('$assetDir/$name');
      file.writeAsBytesSync(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      log('ASSET|$name|bytes=${file.lengthSync()}');
    }
    log('ASSETS|dir=$assetDir');
  });

  testWidgets('手順1: checkModel', (tester) async {
    // E2E_CHECKLIST.md 手順1。本番実装は `SpeechTranscriber.supportedLocales` /
    // `installedLocales` / `AssetInventory.status` の生の値を Dart へ公開
    // しない(公開APIは `ModelState` の4値のみ)。したがって手順1の3.
    // 「`AssetInventory.status` と `installedLocales` の不整合」そのものは
    // この test からは観測できず、**その不整合下でも `checkModel()` が
    // `available` を返すこと**(判定規則6が効いていること)だけを確認できる。
    // 生の値は spikes/darwin/ios-probe で別途取得済みである
    // (spikes/darwin/RESULTS.md)。
    const locales = <String>[
      'ja-JP',
      'ja',
      'en-US',
      'en',
      'en-GB',
      'en-AU',
      'en-IN',
      'en-CA',
      'fr-FR',
      'de-DE',
      'es-ES',
      'it-IT',
      'ko-KR',
      'zh-CN',
      'zh-TW',
      'pt-BR',
      'ru-RU',
      'hi-IN',
      // BCP-47 として妥当だが実在しないロケール(手順1の2.)。
      'xx-XX',
      'zz-ZZ',
    ];
    for (final locale in locales) {
      final stopwatch = Stopwatch()..start();
      try {
        final state = await OfflineTranscriberPlatform.instance
            .checkModel(locale)
            .timeout(const Duration(seconds: 30));
        log(
          'CHECKMODEL|$locale|${state.name}'
          '|ms=${stopwatch.elapsedMilliseconds}',
        );
      } on TimeoutException {
        log('CHECKMODEL|$locale|TIMEOUT|ms=${stopwatch.elapsedMilliseconds}');
      } catch (e) {
        log(
          'CHECKMODEL|$locale|THREW:${e.runtimeType}:$e'
          '|ms=${stopwatch.elapsedMilliseconds}',
        );
      }
    }
  });

  testWidgets('手順1-b: checkModel の連続呼び出し', (tester) async {
    // Android 実機E2E(E2E_RESULTS.md B-2)で「連続呼び出し時に checkModel が
    // 偽の unavailable を返す」事象が出たため、Darwin でも同じ測定を行う。
    // チェックリストには無い追加項目である。
    for (var i = 0; i < 30; i++) {
      final stopwatch = Stopwatch()..start();
      try {
        final state = await OfflineTranscriberPlatform.instance
            .checkModel('ja-JP')
            .timeout(const Duration(seconds: 30));
        log('REPEAT|$i|${state.name}|ms=${stopwatch.elapsedMilliseconds}');
      } on TimeoutException {
        log('REPEAT|$i|TIMEOUT|ms=${stopwatch.elapsedMilliseconds}');
      } catch (e) {
        log(
          'REPEAT|$i|THREW:${e.runtimeType}:$e'
          '|ms=${stopwatch.elapsedMilliseconds}',
        );
      }
    }
  });

  testWidgets('手順3: transcribeFile(基準音声8ファイル)', (tester) async {
    for (final (clip, locale) in baselineClips) {
      final path = '$assetDir/$clip';
      if (!File(path).existsSync()) {
        log('CLIP|$clip|MISSING|$path');
        continue;
      }
      final run = await runTranscription(clip, locale);
      reportRun(run);
    }
  });

  testWidgets('手順3-3: playbackRate は Darwin では無視される', (tester) async {
    // E2E_CHECKLIST.md 手順3の3.。`TranscribeRequest.playbackRate` は
    // Web 専用オプションであり(design.md §2.2)、Darwin では無視される。
    // `packages/offline_stt_darwin/lib/src/recognition_session.dart` は
    // Pigeon の `TranscribeRequest` へ `path` / `locale` しか渡さないため
    // **ネイティブへは届かない**。同一クリップを 1.0 / 2.0 / 0.5 で流し、
    // 所要時間と確定テキストが変わらないことを実測で確認する。
    for (final rate in <double>[1.0, 2.0, 0.5]) {
      final run = await runTranscription(
        'jaJP_10s.wav',
        'ja-JP',
        playbackRate: rate,
      );
      log(
        'PLAYBACKRATE|rate=$rate|elapsedMs=${run.elapsed.inMilliseconds}'
        '|finals=${run.finals.length}|error=${run.error}',
      );
      log('PLAYBACKRATE|rate=$rate|text=${oneLine(run.finals.join(''))}');
    }
  });

  testWidgets('手順4: キャンセル', (tester) async {
    // E2E_CHECKLIST.md 手順4。3分クリップの実行中、最初のセグメントが
    // 届いた時点で購読を cancel() する。
    var segmentsAfterCancel = 0;
    var cancelled = false;
    final firstSegment = Completer<void>();
    Object? startError;
    final subscription = OfflineTranscriberPlatform.instance
        .transcribeFile(
          TranscribeRequest(path: '$assetDir/jaJP_3m.wav', locale: 'ja-JP'),
        )
        .listen(
          (segment) {
            if (cancelled) {
              segmentsAfterCancel++;
            } else if (!firstSegment.isCompleted) {
              firstSegment.complete();
            }
          },
          onError: (Object e) {
            startError = e;
            if (!firstSegment.isCompleted) firstSegment.complete();
          },
          onDone: () {
            if (!firstSegment.isCompleted) firstSegment.complete();
          },
        );
    await firstSegment.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        startError = 'timeout';
      },
    );
    log('CANCEL|startError=$startError');
    if (startError != null) {
      await subscription.cancel();
      log('CANCEL|未実施|reason=セッションを開始できなかった');
      return;
    }

    final stopwatch = Stopwatch()..start();
    cancelled = true;
    await subscription.cancel();
    stopwatch.stop();
    log('CANCEL|cancelFutureMs=${stopwatch.elapsedMilliseconds}');
    await Future<void>.delayed(const Duration(seconds: 5));
    log('CANCEL|segmentsAfterCancel=$segmentsAfterCancel');

    // キャンセル直後に別の transcribeFile() を開始でき、StateError
    // (セッション排他違反)にならないこと。
    final next = await runTranscription('jaJP_10s.wav', 'ja-JP');
    log(
      'CANCEL|nextRun|finals=${next.finals.length}'
      '|error=${next.error.runtimeType}:${next.error}',
    );
    reportRun(next);
  });

  testWidgets('手順5: セッション排他', (tester) async {
    // E2E_CHECKLIST.md 手順5。1本目を購読したまま2本目を購読し、2本目が
    // StateError で即座に終了することを確認する。
    final firstSegment = Completer<void>();
    Object? firstError;
    final first = OfflineTranscriberPlatform.instance
        .transcribeFile(
          TranscribeRequest(path: '$assetDir/jaJP_3m.wav', locale: 'ja-JP'),
        )
        .listen(
          (_) {
            if (!firstSegment.isCompleted) firstSegment.complete();
          },
          onError: (Object e) {
            firstError = e;
            if (!firstSegment.isCompleted) firstSegment.complete();
          },
        );
    await firstSegment.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        firstError = 'timeout';
      },
    );
    log('EXCLUSIVE|firstError=$firstError');
    if (firstError != null) {
      await first.cancel();
      log('EXCLUSIVE|未実施|reason=1本目を開始できなかった');
      return;
    }

    Object? secondError;
    final secondDone = Completer<void>();
    final second = OfflineTranscriberPlatform.instance
        .transcribeFile(
          TranscribeRequest(path: '$assetDir/jaJP_10s.wav', locale: 'ja-JP'),
        )
        .listen(
          (_) {},
          onError: (Object e) {
            secondError = e;
            if (!secondDone.isCompleted) secondDone.complete();
          },
          onDone: () {
            if (!secondDone.isCompleted) secondDone.complete();
          },
        );
    await secondDone.future.timeout(const Duration(seconds: 30));
    log('EXCLUSIVE|secondError=${secondError.runtimeType}|$secondError');
    await second.cancel();
    await first.cancel();
  });

  testWidgets('手順6: エラーパス', (tester) async {
    // E2E_CHECKLIST.md 手順6。
    // DecodeFailedException: テキストファイルを .wav として渡す。
    final decode = await runTranscription('not_audio.wav', 'ja-JP');
    log(
      'ERRORPATH|decodeFailed|error=${decode.error.runtimeType}'
      '|${oneLine('${decode.error}')}',
    );
    // LocaleUnsupportedException: supportedLocales に無いロケール。
    for (final locale in <String>['xx-XX', 'zz-ZZ']) {
      final state = await OfflineTranscriberPlatform.instance.checkModel(
        locale,
      );
      final run = await runTranscription('jaJP_10s.wav', locale);
      log(
        'ERRORPATH|localeUnsupported|locale=$locale|checkModel=${state.name}'
        '|error=${run.error.runtimeType}|${oneLine('${run.error}')}',
      );
    }
    // ModelUnavailableException: モデル未取得(downloadable)のロケール。
    for (final locale in <String>['fr-FR', 'de-DE', 'ko-KR']) {
      final state = await OfflineTranscriberPlatform.instance.checkModel(
        locale,
      );
      if (state != ModelState.downloadable) {
        log(
          'ERRORPATH|modelUnavailable|locale=$locale|skip'
          '|checkModel=${state.name}',
        );
        continue;
      }
      final run = await runTranscription('jaJP_10s.wav', locale);
      log(
        'ERRORPATH|modelUnavailable|locale=$locale|checkModel=${state.name}'
        '|error=${run.error.runtimeType}|${oneLine('${run.error}')}',
      );
    }
    // DeviceUnsupportedException は requirements.md NFR-4 未満の OS でしか
    // 発火しない。検証機は macOS 26 / iOS 26 以上であるため発火させられない。
    log('ERRORPATH|deviceUnsupported|未実施|reason=OS26未満の実機が無い');
  });

  testWidgets('追加: ダウンロード中の文字起こしキャンセルが巻き添えにしないこと', (tester) async {
    // チェックリストには無い追加項目である。M0 以降に本番実装へ入った次の
    // 2つの修正は、**どちらも実機で一度も走っていない**。両方ともこの
    // シナリオ(ダウンロードと文字起こしが同時に走っている状態)でしか
    // 効かないため、専用の項目を置く。
    //
    // 1. `recognition_session.dart` の `startedNativeTranscription`。
    //    `hostApi.cancel()` は文字起こしとダウンロードの**両方**を止める。
    //    ネイティブの文字起こしを開始する前に購読がキャンセルされたときに
    //    これを呼ぶと、同時に走っている無関係なダウンロードまで止まる。
    // 2. `OfflineSttDarwinPlugin.swift` の EventChannel ごとのキャンセル
    //    分離(`cancelTranscriptionFromEventChannel` /
    //    `cancelDownloadFromEventChannel`)。文字起こしが正常終了すると
    //    Dart 側が segments の EventChannel 購読を解除するため、分離が
    //    無いとそこでダウンロードまで止まる。
    //
    // 期待する結果: 下の(a)(b)のどちらを行っても、ダウンロードの Stream は
    // `completed: true` で正常に完了する。
    const candidates = <String>[
      'ko-KR',
      'es-ES',
      'it-IT',
      'zh-CN',
      'zh-TW',
      'pt-BR',
      'fr-FR',
      'de-DE',
    ];
    String? target;
    for (final locale in candidates) {
      final state = await OfflineTranscriberPlatform.instance.checkModel(
        locale,
      );
      if (state == ModelState.downloadable) {
        target = locale;
        break;
      }
    }
    if (target == null) {
      log('COEXIST|未実施|reason=downloadable のロケールが見つからなかった');
      return;
    }
    log('COEXIST|downloadLocale=$target');

    final events = <DownloadProgress>[];
    Object? downloadError;
    var downloadDone = false;
    final downloadCompleter = Completer<void>();
    final download = OfflineTranscriberPlatform.instance
        .downloadModel(target)
        .listen(
          events.add,
          onError: (Object e) {
            downloadError = e;
            if (!downloadCompleter.isCompleted) downloadCompleter.complete();
          },
          onDone: () {
            downloadDone = true;
            if (!downloadCompleter.isCompleted) downloadCompleter.complete();
          },
          cancelOnError: false,
        );

    // (a) ネイティブの文字起こしを開始する前にキャンセルする。
    // `listen()` の直後に同期的に `cancel()` を呼ぶため、
    // `recognition_session.dart` の `onListen` クロージャは最初の await
    // (checkModel)で止まっており、`startedNativeTranscription` は必ず
    // false である。
    final early = OfflineTranscriberPlatform.instance
        .transcribeFile(
          TranscribeRequest(path: '$assetDir/jaJP_3m.wav', locale: 'ja-JP'),
        )
        .listen((_) {}, onError: (Object _) {});
    await early.cancel();
    log('COEXIST|a|開始前キャンセル済み|downloadEvents=${events.length}');

    // (b) 文字起こしを最後まで流す(正常終了時に segments EventChannel の
    // 購読解除が走る)。
    final run = await runTranscription('jaJP_10s.wav', 'ja-JP');
    log(
      'COEXIST|b|finals=${run.finals.length}|done=${run.completedNormally}'
      '|error=${run.error}',
    );

    var timedOut = false;
    await downloadCompleter.future.timeout(
      const Duration(minutes: 15),
      onTimeout: () {
        timedOut = true;
      },
    );
    await download.cancel();
    for (final event in events) {
      log(
        'COEXIST|downloadEvent|fraction=${event.fraction}'
        '|completed=${event.completed}',
      );
    }
    final after = await OfflineTranscriberPlatform.instance.checkModel(target);
    log(
      'COEXIST|result|locale=$target|events=${events.length}'
      '|done=$downloadDone|timedOut=$timedOut'
      '|error=${downloadError.runtimeType}:$downloadError'
      '|after=${after.name}',
    );
  });

  testWidgets('手順2: downloadModel', (tester) async {
    // E2E_CHECKLIST.md 手順2。ja-JP / en-US は取得済みのことが多いため、
    // `downloadable` のロケールを探して実行する。
    //
    // **この test は意図的に最後に置いている。** ダウンロードはネットワーク
    // 次第で数分〜かかり、失敗したりハングしたりすると後続の測定
    // (手順3〜6)がまとめて失われるためである。
    // en-US を先頭に置いているのは、iPad Pro (iOS 26.6.2) 実機で en-US が
    // `downloadable`(未取得)であり、取得しない限り手順3の基準音声8
    // ファイルのうち en-US 側4本を一度も流せないためである。既に
    // `available` な端末(macOS 検証機)では次の候補へ進む。
    const candidates = <String>[
      'en-US',
      'fr-FR',
      'de-DE',
      'ko-KR',
      'es-ES',
      'it-IT',
    ];
    String? target;
    for (final locale in candidates) {
      final state = await OfflineTranscriberPlatform.instance.checkModel(
        locale,
      );
      log('DOWNLOAD|probe|locale=$locale|state=${state.name}');
      if (state == ModelState.downloadable) {
        target = locale;
        break;
      }
    }
    if (target == null) {
      log('DOWNLOAD|未実施|reason=downloadable のロケールが見つからなかった');
      return;
    }

    final events = <DownloadProgress>[];
    Object? error;
    var done = false;
    final stopwatch = Stopwatch()..start();
    final completer = Completer<void>();
    final subscription = OfflineTranscriberPlatform.instance
        .downloadModel(target)
        .listen(
          events.add,
          onError: (Object e) {
            error = e;
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            done = true;
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: false,
        );
    var timedOut = false;
    await completer.future.timeout(
      const Duration(minutes: 15),
      onTimeout: () {
        timedOut = true;
      },
    );
    stopwatch.stop();
    await subscription.cancel();
    for (final event in events) {
      log(
        'DOWNLOAD|event|fraction=${event.fraction}|completed=${event.completed}',
      );
    }
    log(
      'DOWNLOAD|locale=$target|elapsedMs=${stopwatch.elapsedMilliseconds}'
      '|events=${events.length}|done=$done|timedOut=$timedOut'
      '|error=${error.runtimeType}:$error',
    );
    final after = await OfflineTranscriberPlatform.instance.checkModel(target);
    log('DOWNLOAD|after=${after.name}');
  });
}
