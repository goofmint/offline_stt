import 'dart:async';
import 'dart:developer' as developer;
import 'dart:js_interop';

import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'audio_decoding.dart';
import 'final_text_formatting.dart';
import 'model_state_mapping.dart';
import 'speech_error_mapping.dart';
import 'speech_recognition_js.dart';

/// `onstart` が発火しなかった場合に諦めるまでの猶予(design.md未指定。
/// spikes/web/spike.jsの `onstartTimer`(5000ms)を踏襲。理由は
/// [runTranscriptionSession] のdartdoc参照)。
const _onstartTimeout = Duration(seconds: 5);

/// `source.onended` 後、明示的な `recognition.stop()` を呼んでもなお
/// `onend` が発火しなかった場合に諦めるまでの猶予。spikes/web/spike.jsは
/// タイムアウト後さらに `abort()` を試みて二段階で待つが、ここでは
/// ライブラリとしての単純さを優先し一段階のみとする(design.md未指定の
/// 安全策であり、design.md自体が要求する挙動ではない点に注意)。
const _onendTimeout = Duration(seconds: 10);

/// 認識セッション本体(design.md §4.1、Issue #28・#29)。
///
/// 呼び出し側(`OfflineSttWeb.transcribeFile()`)が
/// `offline_stt_platform_interface` の `TranscribeSessionGuard` でこの
/// Streamをラップし、design.md §3のセッション排他規則
/// (同時1本まで・2本目はStreamErrorでStateError)を満たす前提である。
///
/// ## このファイルの責務と単体テストの切り分け
/// ブラウザAPI(`AudioContext` / `SpeechRecognition`)を直接叩く層のため、
/// このファイル自体の単体テストは書かない。純粋ロジック(状態写像・
/// エラー写像・テキスト整形)は別ファイルへ切り出し、そちらを単体テスト
/// する。ブラウザ依存部分はIssue #31の手動E2Eチェックリストでカバーする。
///
/// ## onstart/onendタイムアウトについて
/// design.md自体はタイムアウトを要求していないが、`onstart` /
/// `onend` が来ない限りStreamが永遠に完了しないのは、design.md §3
/// 「終了は正常終了/エラー終了/購読キャンセルのいずれかの時点とする。
/// いずれの経路でも確実に解放すること」という原則に反する。そのため
/// 実装上の安全策として最小限のタイムアウトを設けている。
Stream<TranscriptSegment> runTranscriptionSession(TranscribeRequest request) {
  late final StreamController<TranscriptSegment> controller;

  web.AudioContext? audioContext;
  DecodedAudioTrack? decoded;
  web.SpeechRecognition? recognition;

  var finished = false;
  var sourceStarted = false;
  Timer? onstartTimer;
  Timer? onendTimer;

  void finish({Object? error}) {
    if (finished) return;
    finished = true;
    onstartTimer?.cancel();
    onendTimer?.cancel();
    if (error != null) {
      controller.addError(error);
    }
    unawaited(controller.close());
  }

  /// 下層リソースの後始末。以下のいずれの経路からも同じ手順で呼ばれる:
  /// - 再生開始前の失敗(Issue #29「再生開始前に失敗した経路でも
  ///   recognition.abort()とaudioTrack.stop()を行ってから終了すること」)
  /// - 購読キャンセル(Issue #29「source.stop()とrecognition.abort()」)
  /// - onstart/onendタイムアウト
  ///
  /// `source.stop()` は再生開始前に呼ぶと仕様上例外を投げるが、個々の
  /// 呼び出しをtry/catchで独立させているため、いずれかが失敗しても他の
  /// 後始末は継続する(spikes/web/spike.jsの `failBeforePlayback` と
  /// 同じ考え方)。
  Future<void> teardown() async {
    try {
      decoded?.source.stop();
    } on Object {
      // 再生開始前だった場合、仕様上ここで例外が飛ぶ。想定内なので握りつぶす。
    }
    try {
      recognition?.abort();
    } on Object {
      // 同上。
    }
    try {
      decoded?.audioTrack.stop();
    } on Object {
      // 同上。
    }
    try {
      await audioContext?.close().toDart;
    } on Object {
      // 同上。
    }
  }

  controller = StreamController<TranscriptSegment>(
    onListen: () {
      unawaited(() async {
        try {
          // design.md §3: transcribeFile()はcheckModel()相当がavailable
          // 以外なら即座にModelUnavailableExceptionをStreamエラーで返す。
          // 内部で暗黙ダウンロードしない。これを行わないと、言語パック
          // 未取得のままstart()を呼んでしまい、ja-JPでは"aborted"、
          // en-USでは"language-not-supported"という原因の分かりにくい
          // エラーになる(design.md §4.1、Chrome 153実機確認済み)。
          final ctor = findSpeechRecognitionConstructor();
          if (ctor == null) {
            // 非Chrome等。checkModel()相当がunavailableを返す状況
            // (design.md §4.1、Issue #30)と同じ扱い。
            finish(error: const ModelUnavailableException());
            return;
          }
          final availability = await callAvailable(ctor, request.locale);
          final state = mapAvailabilityToModelState(availability);
          if (state != ModelState.available) {
            // design.md §3の規則により、available以外は一律で
            // ModelUnavailableExceptionとする(downloadable/downloading/
            // unavailableを区別しない)。
            finish(error: const ModelUnavailableException());
            return;
          }
          if (finished) return; // 上記await中にキャンセルされた場合。

          audioContext = web.AudioContext();
          final audioBuffer = await fetchAndDecode(audioContext!, request.path);
          if (finished) return;

          decoded = buildAudioTrack(
            audioContext!,
            audioBuffer,
            request.playbackRate,
          );

          recognition = createRecognition(ctor)
            ..lang = request.locale
            ..continuous = true
            ..interimResults = true;

          if (!setAndVerifyProcessLocally(recognition!)) {
            // NFR-2: フォールバック禁止。processLocallyの読み戻しが
            // trueにならなければ、ここで明確にエラー終了する。design.mdの
            // 例外階層には専用の型が無いため、PlatformException_で理由を
            // 明示して伝える。
            await teardown();
            finish(
              error: const PlatformException_(
                code: 'process-locally-verification-failed',
                message:
                    'processLocally を true に設定したが読み戻し値が '
                    'true にならなかった(NFR-2により処理を停止する)',
              ),
            );
            return;
          }

          final finalBuffer = StringBuffer();
          var lastInterimText = '';
          TranscribeException? recognitionError;

          recognition!.onresult = ((web.SpeechRecognitionEvent event) {
            if (finished) return;
            for (var i = event.resultIndex; i < event.results.length; i++) {
              final result = event.results.item(i);
              final transcript = result.length > 0
                  ? result.item(0).transcript
                  : '';
              if (result.isFinal) {
                finalBuffer.write(transcript);
                controller.add(
                  TranscriptSegment(
                    text: stripChromeSegmentationWhitespace(
                      transcript,
                      request.locale,
                    ),
                    isFinal: true,
                  ),
                );
              } else {
                lastInterimText = transcript;
                controller.add(
                  TranscriptSegment(text: transcript, isFinal: false),
                );
              }
            }
          }).toJS;

          recognition!.onerror = ((web.SpeechRecognitionErrorEvent event) {
            // 最初のエラーのみ保持し、onendで使ってセッションをエラー
            // 終了させる(onerror単体では即終了しない。ブラウザによっては
            // onerrorの後に続けてonendが発火するため)。
            recognitionError ??= mapSpeechErrorCode(event.error, event.message);
          }).toJS;

          recognition!.onend = ((web.Event _) {
            if (finished) return;
            if (recognitionError != null) {
              finish(error: recognitionError);
              return;
            }
            if (finalBuffer.isEmpty && lastInterimText.isNotEmpty) {
              // isFinal=trueが一度も発火しないままonendに到達した場合
              // (design.md §4.1、1.1x/1.25xの再生速度で実機観測済み)。
              // 末尾のinterim結果を確定結果として採用する。
              //
              // フォールバックで隠さない対応として、TranscriptSegmentには
              // design.mdにないフィールドを追加できない(design.mdにない
              // 公開APIを追加しない方針)ため、公開APIとしてはisFinal=true
              // のセグメントとして返しつつ、この採用が起きたこと自体は
              // developer.log で明示的に記録する。呼び出し側アプリは
              // 通常のログ経路(DevTools等)からこの挙動に気づける。
              developer.log(
                'isFinal=true を一度も観測しないまま onend に到達したため、'
                '最後の interim 結果を確定結果として採用した。',
                name: 'offline_stt_web',
                level: 900,
              );
              controller.add(
                TranscriptSegment(
                  text: stripChromeSegmentationWhitespace(
                    lastInterimText,
                    request.locale,
                  ),
                  isFinal: true,
                ),
              );
            }
            finish();
          }).toJS;

          recognition!.onstart = ((web.Event _) {
            onstartTimer?.cancel();
            if (finished || sourceStarted) return;
            sourceStarted = true;
            try {
              // recognition.start(audioTrack)を先に呼び、onstartを待って
              // からsource.start()する。逆順だと冒頭が欠落する
              // (design.md §4.1)。
              decoded!.source.start();
            } on Object catch (err) {
              unawaited(() async {
                await teardown();
                finish(
                  error: PlatformException_(
                    code: 'source-start-failed',
                    message: '$err',
                  ),
                );
              }());
            }
          }).toJS;

          decoded!.source.onended = ((web.Event _) {
            if (finished) return;
            // continuous=trueではsource再生終了後もMediaStreamTrackはlive
            // のまま無音を流し続けるため、明示的にrecognition.stop()を
            // 呼んで入力終了を通知しない限りonendは発火しない
            // (design.md §4.1、Chrome 153実機確認済み)。この呼び出しは
            // 必須である。
            try {
              recognition!.stop();
            } on Object {
              // ここで例外を投げ直しても受け手はいない(onendを待つだけの
              // 状態のため)。以降はonendTimerがタイムアウトを保証する。
            }
            onendTimer = Timer(_onendTimeout, () {
              unawaited(() async {
                await teardown();
                finish(
                  error: const PlatformException_(
                    code: 'onend-timeout',
                    message:
                        'recognition.stop() 呼び出し後、一定時間内に '
                        'onend が発火しなかった',
                  ),
                );
              }());
            });
          }).toJS;

          onstartTimer = Timer(_onstartTimeout, () {
            if (finished || sourceStarted) return;
            unawaited(() async {
              await teardown();
              finish(
                error: const PlatformException_(
                  code: 'onstart-timeout',
                  message:
                      'recognition.start(audioTrack) 後、一定時間内に '
                      'onstart が発火しなかった',
                ),
              );
            }());
          });

          try {
            startWithAudioTrack(recognition!, decoded!.audioTrack);
          } on Object catch (err) {
            // start()自体が同期的に失敗した経路。Issue #29
            // 「再生開始前に失敗した経路でもrecognition.abort()と
            // audioTrack.stop()を行ってから終了すること」に対応する。
            onstartTimer?.cancel();
            await teardown();
            finish(
              error: PlatformException_(code: 'start-failed', message: '$err'),
            );
          }
        } on Object catch (e) {
          // ここまでの経路(availability確認・decode・上記catchで
          // 拾いきれない同期例外)をまとめて捕捉する。DecodeFailedException
          // もここを通る。
          //
          // finish() はStreamを終えるだけで teardown() を呼ばない。
          // AudioContext の生成後に fetchAndDecode() や buildAudioTrack() が
          // 例外を投げると AudioContext が開いたまま残るため、ここで明示的に
          // 解放する。
          await teardown();
          finish(error: e);
        }
      }());
    },
    onCancel: () {
      // design.md §5・Issue #29: キャンセル。
      //
      // ## CancelledExceptionを使わない判断とその理由
      // design.md §5の表には「Cancelled: stop/abort」という対応が
      // 挙げられている。しかしDartの `Stream` の `cancel()` は、購読者
      // 自身がこれ以上イベントを受け取らないと決めた結果であり、cancel()
      // が返った時点で当のStreamにはもはや誰もlistenしていない。
      // つまり `CancelledException` を addError() しても、それを受け取る
      // 相手が存在しない(以後のadd/addErrorは単に無視される)。そのため
      // このWeb実装ではCancelledExceptionを送出する経路を持たず、
      // onCancelでは下層リソースの解放のみを行う。
      if (finished) return null;
      finished = true;
      onstartTimer?.cancel();
      onendTimer?.cancel();
      return teardown();
    },
  );

  return controller.stream;
}
