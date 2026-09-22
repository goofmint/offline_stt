// Android 実機E2E(Issue #50)を自動化した integration_test。
//
// `packages/offline_stt_android/E2E_CHECKLIST.md` の手順1〜8を、example app の
// UI を人手で操作する代わりに **本番実装(packages/ 配下の Dart + Kotlin)を
// そのまま呼び出して** 実行する。UI 操作ではなく API 直叩きにしている理由は
// 次の2点である。
//
// - 手順3は基準音声8ファイル分の確定テキストと所要時間を、手順8はキーワード
//   一致の可否を **正確な文字列として** 記録する必要がある。UI をスクリーン
//   ショットで読む方式では確定テキストを取りこぼす。
// - 手順4(キャンセル)・手順5(セッション排他)は `StreamSubscription` の
//   操作そのものが検証対象であり、UI からは再現できない。
//
// example app の UI 経路(ファイルピッカー → 同意ダイアログ → 進行表示)は
// この test では通らない。UI 経路の確認は E2E_CHECKLIST.md の手順を人手で
// 実行して別途行うこと。
//
// ## 実行方法
//
// 1. 基準音声を端末のアプリ専用外部ストレージへ push する
//    (`tool/stage_baseline_audio.sh` が `assets/baseline-audio/` へ複製し、
//    `setUpAll` が `rootBundle` からアプリのテンポラリディレクトリへ書き出す)。
// 2. 次を実行する(JDK 17 が必要。既定JDKが 26 系だと Kotlin コンパイラが
//    バージョン文字列を解釈できずビルドが失敗する)。
//
//    ```
//    JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
//      flutter test integration_test/android_baseline_e2e_test.dart \
//      -d <device-id>
//    ```
//
// 3. 標準出力の `E2E|` 始まりの行が測定値である。確定テキストは
//    `E2E|FINAL|<clip>|<text>` の形式で1行に出る。
//
// 測定値の集計(キーワード包含率)は `test-assets/keyword_score.py` に渡す。
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_stt/offline_stt.dart';
import 'package:path_provider/path_provider.dart';

/// `setUpAll` が `rootBundle` から音声を書き出す先。アプリのテンポラリ
/// ディレクトリで
/// あり、Android 11 以降も追加の実行時権限なしで読める。
/// `setUpAll` が `getTemporaryDirectory()` から求めて設定する。
late final String deviceAssetDir;

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

/// E2E_CHECKLIST.md 手順3の3.(リサンプリング経路の確認)。基準音声は
/// 16kHz・モノラルで生成されているためリサンプラを通らない。
const List<(String clip, String locale)> resampleClips = <(String, String)>[
  ('jaJP_10s_48k_stereo.m4a', 'ja-JP'),
  ('enUS_10s_44k1_stereo.m4a', 'en-US'),
];

/// APKへ焼き込む音声。`tool/stage_baseline_audio.sh` が
/// `assets/baseline-audio/` へ複製したものと一致させること。
const List<String> bundledFiles = <String>[
  'jaJP_10s.wav',
  'jaJP_10s.m4a',
  'jaJP_3m.wav',
  'jaJP_3m.m4a',
  'enUS_10s.wav',
  'enUS_10s.m4a',
  'enUS_3m.wav',
  'enUS_3m.m4a',
  'jaJP_10s_48k_stereo.m4a',
  'enUS_10s_44k1_stereo.m4a',
  'not_audio.wav',
];

void log(String line) {
  // ignore: avoid_print
  print('E2E|$line');
}

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

/// 1本前のセッションの後片付けが終わるまで待つ間隔。
///
/// 実測(2026-09-21 の Pixel 6 実行)では `transcribeFile()` が
/// `ERROR_SERVER_DISCONNECTED(11)` / `ERROR_RECOGNIZER_BUSY(8)` で即座に
/// 失敗することが多い。**この間隔を10秒に広げても失敗率は下がらなかった**
/// ため、原因はセッション間隔ではない(詳細は E2E_RESULTS.md)。それでも
/// 1本前の後始末と次の開始が重ならないようにする意味はあるため、短い間隔を
/// 残している。
const Duration settleDelay = Duration(seconds: 3);

Future<TranscriptionRun> runTranscription(String clip, String locale) async {
  await Future<void>.delayed(settleDelay);
  final run = TranscriptionRun(clip);
  final stopwatch = Stopwatch()..start();
  final completer = Completer<void>();
  final subscription = const OfflineTranscriber()
      .transcribeFile(
        TranscribeRequest(path: '$deviceAssetDir/$clip', locale: locale),
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
  for (var i = 0; i < run.partials.length; i++) {
    log('PARTIAL|${run.clip}|$i|${run.partials[i]}');
  }
  for (final text in run.finals) {
    log('FINAL|${run.clip}|$text');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    log(
      'DEVICE|${Platform.operatingSystem}|${Platform.operatingSystemVersion}',
    );
    // **音声は Flutter アセットとしてAPKに焼き込み、起動時にアプリ自身の
    // テンポラリディレクトリへ書き出す。**
    //
    // 以前は `adb push` + 番兵ファイル待ちにしていたが、`flutter test` は
    // 実行のたびにアプリをインストールし直すため、push したディレクトリが
    // 消える。push するタイミングを待ち合わせる方式は競合し、実測で
    // 「全ファイル MISSING のまま空振りで成功」「セットアップで停止したまま
    // 90分経過」という2通りの壊れ方をした。アセット方式なら
    // インストールのタイミングに依存せず、Darwin 側の
    // `darwin_baseline_e2e_test.dart` とも経路が揃う。
    final tempDir = await getTemporaryDirectory();
    deviceAssetDir = '${tempDir.path}/baseline-audio';
    Directory(deviceAssetDir).createSync(recursive: true);
    for (final name in bundledFiles) {
      final data = await rootBundle.load('assets/baseline-audio/$name');
      final file = File('$deviceAssetDir/$name');
      file.writeAsBytesSync(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      log('ASSET|$name|bytes=${file.lengthSync()}');
    }
    log('ASSETS|dir=$deviceAssetDir');
  });

  testWidgets('手順1: checkModel', (tester) async {
    // E2E_CHECKLIST.md 手順1。本番実装は checkRecognitionSupport() の4リスト
    // そのものをログへ出さないため、ここではロケールごとの ModelState を
    // 記録する。
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
      // BCP-47 として妥当だが実在しないロケール。
      'zz-ZZ',
    ];
    for (final locale in locales) {
      // 手順1-b で判明した「連続呼び出し時に checkModel が偽の unavailable を
      // 返す」事象を避けるため、1秒あけて呼ぶ。
      await Future<void>.delayed(const Duration(seconds: 1));
      final stopwatch = Stopwatch()..start();
      try {
        final state = await const OfflineTranscriber()
            .checkModel(locale)
            .timeout(const Duration(seconds: 20));
        log(
          'CHECKMODEL|$locale|${state.name}'
          '|ms=${stopwatch.elapsedMilliseconds}',
        );
      } on TimeoutException {
        log(
          'CHECKMODEL|$locale|TIMEOUT'
          '|ms=${stopwatch.elapsedMilliseconds}',
        );
      }
    }
  });

  testWidgets('手順1-b: checkModel の連続呼び出し', (tester) async {
    // 手順1の実行中に、同一ロケールでも呼び出し回数によって結果が変わる/
    // 応答が返らなくなる事象が観測されたため、その再現条件を測るための
    // 追加測定である(E2E_CHECKLIST.md には無い項目)。
    for (var i = 0; i < 30; i++) {
      final stopwatch = Stopwatch()..start();
      try {
        final state = await const OfflineTranscriber()
            .checkModel('ja-JP')
            .timeout(const Duration(seconds: 20));
        log('REPEAT|$i|${state.name}|ms=${stopwatch.elapsedMilliseconds}');
      } on TimeoutException {
        log('REPEAT|$i|TIMEOUT|ms=${stopwatch.elapsedMilliseconds}');
      } catch (e) {
        // B-2 の修正後、照会の一時的な失敗は `unavailable` に畳まれず
        // 例外として上がる。偽の `unavailable` と区別して記録する。
        log(
          'REPEAT|$i|THREW:${e.runtimeType}:$e|ms=${stopwatch.elapsedMilliseconds}',
        );
      }
    }
    // 連続呼び出しではなく1秒間隔を空けた場合との対照。
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final stopwatch = Stopwatch()..start();
      try {
        final state = await const OfflineTranscriber()
            .checkModel('ja-JP')
            .timeout(const Duration(seconds: 20));
        log('SPACED|$i|${state.name}|ms=${stopwatch.elapsedMilliseconds}');
      } on TimeoutException {
        log('SPACED|$i|TIMEOUT|ms=${stopwatch.elapsedMilliseconds}');
      } catch (e) {
        log(
          'SPACED|$i|THREW:${e.runtimeType}:$e|ms=${stopwatch.elapsedMilliseconds}',
        );
      }
    }
  });

  testWidgets('手順2: downloadModel', (tester) async {
    // E2E_CHECKLIST.md 手順2。ja-JP は M0検証(spikes/android/RESULTS.md)で
    // 既に取得済みで available のため、downloadable のロケールで実施する。
    const target = String.fromEnvironment(
      'OFFLINE_STT_DOWNLOAD_LOCALE',
      defaultValue: 'fr-FR',
    );
    for (var attempt = 0; attempt < 6; attempt++) {
      await Future<void>.delayed(settleDelay);
      final before = await const OfflineTranscriber().checkModel(target);
      log(
        'DOWNLOAD|attempt=${attempt + 1}|locale=$target'
        '|before=${before.name}',
      );
      if (before != ModelState.downloadable) {
        log('DOWNLOAD|skipped|reason=downloadable以外のため手順2は対象外');
        continue;
      }
      final events = <DownloadProgress>[];
      Object? error;
      final stopwatch = Stopwatch()..start();
      await const OfflineTranscriber()
          .downloadModel(target)
          .listen(events.add, onError: (Object e) => error = e)
          .asFuture<void>()
          .catchError((Object e) {
            error = e;
          });
      stopwatch.stop();
      for (final event in events) {
        log(
          'DOWNLOAD|event|fraction=${event.fraction}'
          '|completed=${event.completed}',
        );
      }
      log('DOWNLOAD|elapsedMs=${stopwatch.elapsedMilliseconds}|error=$error');
      final after = await const OfflineTranscriber().checkModel(target);
      log('DOWNLOAD|after=${after.name}');
      if (events.isNotEmpty) break;
      log('DOWNLOAD|イベントが1件も届かずに完了した。再試行する');
    }
  });

  testWidgets('手順3: transcribeFile(基準音声8ファイル)', (tester) async {
    for (final (clip, locale) in baselineClips) {
      final path = '$deviceAssetDir/$clip';
      // アセットが無ければ測定そのものが成立しない。以前これを `continue` で
      // 見逃した結果、全ファイル MISSING のまま「成功」した実行があった。
      expect(File(path).existsSync(), isTrue, reason: '基準音声が配置されていない: $path');
      final run = await runTranscription(clip, locale);
      reportRun(run);
      // **エラーや「final 0件で正常終了」をテスト失敗にする。** 以前は
      // ログに出すだけだったため、`ERROR_SERVER_DISCONNECTED` で即座に
      // 失敗した実行も「成功」として通っていた(E2E_RESULTS.md の B-1)。
      // 包含率は合否ゲートではなく記録項目のままにする(design.md §7)。
      expect(run.error, isNull, reason: '$clip の文字起こしが失敗した');
      expect(run.completedNormally, isTrue, reason: '$clip が正常終了しなかった');
      expect(run.finals, isNotEmpty, reason: '$clip の確定結果が得られなかった');
    }
  });

  testWidgets('手順3-3: リサンプリング経路(48kHz/44.1kHz ステレオ)', (tester) async {
    for (final (clip, locale) in resampleClips) {
      final path = '$deviceAssetDir/$clip';
      expect(File(path).existsSync(), isTrue, reason: '基準音声が配置されていない: $path');
      final run = await runTranscription(clip, locale);
      reportRun(run);
      expect(run.error, isNull, reason: '$clip の文字起こしが失敗した');
      expect(run.completedNormally, isTrue, reason: '$clip が正常終了しなかった');
      expect(run.finals, isNotEmpty, reason: '$clip の確定結果が得られなかった');
    }
  });

  testWidgets('手順3-b: 失敗時リトライ付きの基準音声10秒クリップ', (tester) async {
    // 手順3の実測で `ERROR_SERVER_DISCONNECTED(11)` による即時失敗が多発した
    // ため、成功率と、成功したときの確定テキストを得るためにリトライする。
    // **これはテスト側の緩和であり、本番実装はリトライしない。**
    const maxAttempts = 15;
    for (final (clip, locale) in <(String, String)>[
      ('jaJP_10s.wav', 'ja-JP'),
      ('jaJP_10s.m4a', 'ja-JP'),
      ('enUS_10s.wav', 'en-US'),
      ('enUS_10s.m4a', 'en-US'),
      ('jaJP_10s_48k_stereo.m4a', 'ja-JP'),
      ('enUS_10s_44k1_stereo.m4a', 'en-US'),
    ]) {
      var attempts = 0;
      final errors = <String>[];
      for (var i = 0; i < maxAttempts; i++) {
        attempts++;
        final run = await runTranscription(clip, locale);
        if (run.finals.isNotEmpty) {
          log('RETRY|$clip|attempts=$attempts|errors=${errors.join(",")}');
          reportRun(run);
          break;
        }
        errors.add('${run.error}');
        if (i == maxAttempts - 1) {
          log(
            'RETRY|$clip|attempts=$attempts|FAILED_ALL'
            '|errors=${errors.join(",")}',
          );
        }
      }
    }
  });

  testWidgets('手順4: キャンセル', (tester) async {
    // E2E_CHECKLIST.md 手順4。3分クリップの実行中にキャンセルし、返る
    // Future の完了まで待つ。
    //
    // B-1(E2E_RESULTS.md)により `transcribeFile()` は即時失敗することが
    // 多いため、実際に partial が流れ始めるまでリトライする。
    var segmentsAfterCancel = 0;
    var cancelled = false;
    StreamSubscription<TranscriptSegment>? subscription;
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(settleDelay);
      final firstSegment = Completer<void>();
      Object? startError;
      final candidate = const OfflineTranscriber()
          .transcribeFile(
            TranscribeRequest(
              path: '$deviceAssetDir/jaJP_3m.wav',
              locale: 'ja-JP',
            ),
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
          );
      await firstSegment.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          startError = 'timeout';
        },
      );
      if (startError == null) {
        subscription = candidate;
        log('CANCEL|startedAfterAttempts=${attempt + 1}');
        break;
      }
      log('CANCEL|startAttempt=${attempt + 1}|error=$startError');
      await candidate.cancel();
    }
    if (subscription == null) {
      log('CANCEL|未実施|reason=B-1 により認識セッションを開始できなかった');
      return;
    }

    final stopwatch = Stopwatch()..start();
    cancelled = true;
    await subscription.cancel();
    stopwatch.stop();
    log('CANCEL|cancelFutureMs=${stopwatch.elapsedMilliseconds}');
    await Future<void>.delayed(const Duration(seconds: 3));
    log('CANCEL|segmentsAfterCancel=$segmentsAfterCancel');

    // キャンセル Future 完了後に次のセッションを開始できること。
    final next = await runTranscription('jaJP_10s.wav', 'ja-JP');
    log('CANCEL|nextRun|finals=${next.finals.length}|error=${next.error}');
    reportRun(next);
  });

  testWidgets('手順5: セッション排他', (tester) async {
    // 1本目が実際に開始できるまでリトライする(理由は手順4と同じ)。
    StreamSubscription<TranscriptSegment>? first;
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(settleDelay);
      final firstSegment = Completer<void>();
      Object? startError;
      final candidate = const OfflineTranscriber()
          .transcribeFile(
            TranscribeRequest(
              path: '$deviceAssetDir/jaJP_3m.wav',
              locale: 'ja-JP',
            ),
          )
          .listen(
            (_) {
              if (!firstSegment.isCompleted) firstSegment.complete();
            },
            onError: (Object e) {
              startError = e;
              if (!firstSegment.isCompleted) firstSegment.complete();
            },
          );
      await firstSegment.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          startError = 'timeout';
        },
      );
      if (startError == null) {
        first = candidate;
        log('EXCLUSIVE|firstStartedAfterAttempts=${attempt + 1}');
        break;
      }
      log('EXCLUSIVE|startAttempt=${attempt + 1}|error=$startError');
      await candidate.cancel();
    }
    if (first == null) {
      log('EXCLUSIVE|未実施|reason=B-1 により1本目を開始できなかった');
      return;
    }

    Object? secondError;
    final secondDone = Completer<void>();
    final second = const OfflineTranscriber()
        .transcribeFile(
          TranscribeRequest(
            path: '$deviceAssetDir/jaJP_10s.wav',
            locale: 'ja-JP',
          ),
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
    // ModelUnavailableException: 未取得(downloadable)のロケール。
    for (final locale in <String>['fr-FR', 'zz-ZZ']) {
      final state = await const OfflineTranscriber().checkModel(locale);
      final run = await runTranscription('jaJP_10s.wav', locale);
      log(
        'ERRORPATH|locale=$locale|checkModel=${state.name}'
        '|error=${run.error.runtimeType}|$run.error',
      );
    }
    // DecodeFailedException: テキストファイルを .wav として渡す。
    // B-1 による `platformError` に埋もれるため、それ以外が返るまで
    // リトライする。
    for (var i = 0; i < 15; i++) {
      final run = await runTranscription('not_audio.wav', 'ja-JP');
      log(
        'ERRORPATH|not_audio.wav|attempt=${i + 1}'
        '|error=${run.error.runtimeType}|${run.error}',
      );
      if (run.error is! PlatformException_) break;
    }
  });
}
