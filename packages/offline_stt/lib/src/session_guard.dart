import 'dart:async';

import 'package:meta/meta.dart';

import 'transcript_segment.dart';

/// セッション排他ガード(design.md §3)。
///
/// design.md §3 は次のように定める: 「同時セッションはv1では1本に制限
/// (プラットフォーム側の並行動作が未検証のため)。2本目の開始は
/// `StateError`」。
///
/// ## この共有層に置く理由(Issue #23)
/// 各プラットフォーム実装(`src/android/` / `src/darwin/` / `src/web/`)が
/// 個別にこの排他ロジックを実装すると、実装が重複するうえ実装漏れも
/// 起きやすい。そのため共有層である `lib/src/` 直下にガードを置き、各実装は
/// [TranscribeSessionGuard] を `with` したうえで、`transcribeFile()` の
/// 実装内で [guardSession] にネイティブセッションを開始するコールバックを
/// 渡す形で利用する。
///
/// ## 公開バレル(lib/offline_stt.dart)からエクスポートしない理由
/// design.md §2.1 の公開契約(`OfflineTranscriberPlatform` の抽象メソッド
/// シグネチャ)にこのガードは登場しない。アプリ開発者向けの公開APIに
/// design.md にない型を追加しないという方針に従い、公開バレルには含めない。
/// パッケージ内部の実装詳細としてのみ参照する。
///
/// ## 「セッション開始/終了」をどの時点とみなすか
/// `transcribeFile()` はStreamベースのAPI(design.md §2.1)である。Dartの
/// `Stream` は本来「購読されるまでリソースを確保しない」のが自然な
/// セマンティクスであり、もし呼び出し(Streamの生成)そのものの時点で
/// ネイティブの認識APIを叩き始めてしまうと、呼び出し元が購読する前に
/// Streamを破棄した場合でもセッション枠を1本消費してしまい、実際には
/// 何も認識していないのに2本目が `StateError` になるという不自然な挙動に
/// なる。そのため本ガードは次の方針を採る:
/// - セッション**開始** = [guardSession] が返すStreamが実際に
///   **購読(listen)** された時点(`StreamController.onListen`)
/// - セッション**終了** = [startSession] が返すネイティブ側Streamが
///   **正常終了(done)** **エラー終了(error)** **購読キャンセル(cancel)**
///   のいずれかを迎えた時点
///
/// 3経路のいずれから終了しても確実に解放されるよう、内部の解放処理は
/// べき等にしてある(複数回呼ばれても2回目以降は何もしない)。
mixin TranscribeSessionGuard {
  bool _sessionActive = false;

  /// [startSession] が返すStreamをセッション排他ガード付きでラップする。
  ///
  /// 返り値のStreamが購読された時点で、既に1本のセッションが実行中で
  /// あれば [startSession] は一切呼び出されず、購読者へ [StateError] が
  /// Streamエラーとして通知される(design.md §3)。実行中でなければ
  /// [startSession] を呼び出してセッションを開始し、そのStreamのイベントを
  /// そのまま中継する。
  @protected
  Stream<TranscriptSegment> guardSession(
    Stream<TranscriptSegment> Function() startSession,
  ) {
    late final StreamController<TranscriptSegment> controller;
    StreamSubscription<TranscriptSegment>? sourceSubscription;
    // この呼び出しがセッション枠を取得したかどうか。2本目として拒否された
    // 場合は取得していないため、解放してはならない。拒否経路でも
    // controller.close() により購読が終了し onCancel が呼ばれるため、
    // これを見ないと1本目が実行中にもかかわらず枠が解放されてしまう。
    var owned = false;
    var released = false;

    void release() {
      // 正常終了(onDone)・エラー終了(onError)・キャンセル(onCancel)の
      // いずれの経路からも呼ばれ得るため、二重解放を防ぐためべき等にして
      // ある。枠を取得していない(拒否された)呼び出しは解放しない。
      if (!owned || released) return;
      released = true;
      _sessionActive = false;
    }

    controller = StreamController<TranscriptSegment>(
      onListen: () {
        if (_sessionActive) {
          controller.addError(
            StateError(
              '既に実行中のセッションが存在する。design.md §3のとおり、'
              '同時セッションはv1では1本に制限される。1本目のセッションが'
              '終了(done/error/cancelled)してから再度呼び出すこと。',
            ),
          );
          unawaited(controller.close());
          return;
        }
        _sessionActive = true;
        owned = true;
        sourceSubscription = startSession().listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            // startSession() が返す Stream は onError の後に done になるとは
            // 限らない。解放だけして購読を残すと、source が後続イベントを
            // 送り続けたまま2本目が開始できてしまう。最初のエラーで購読を
            // 打ち切り、出力側も閉じる。
            release();
            controller.addError(error, stackTrace);
            final sub = sourceSubscription;
            sourceSubscription = null;
            unawaited(sub?.cancel() ?? Future<void>.value());
            unawaited(controller.close());
          },
          onDone: () {
            release();
            unawaited(controller.close());
          },
        );
      },
      onCancel: () {
        release();
        return sourceSubscription?.cancel();
      },
    );
    return controller.stream;
  }
}
