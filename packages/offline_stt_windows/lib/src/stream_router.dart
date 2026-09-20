import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

import 'error_code_mapping.dart';
import 'pigeon.g.dart' as pigeon;

/// 1本のストリーム購読者へ配送するコールバック束(Issue #53 / #55)。
///
/// `onSegment`は`transcribeFile()`のストリームだけが、
/// `onDownloadProgress`は`downloadModel()`のストリームだけが使う。
/// 使わない側は`null`のままにしておき、届いた場合は
/// [WindowsStreamRouter]が黙って捨てるのではなく無視した理由が分かるよう
/// にする(下記`onSegment`実装のコメント参照)。
class WindowsStreamRoute {
  WindowsStreamRoute({
    required this.onError,
    required this.onDone,
    this.onSegment,
    this.onDownloadProgress,
  });

  /// `transcribeFile()`用。
  final void Function(TranscriptSegment segment)? onSegment;

  /// `downloadModel()`用。
  final void Function(DownloadProgress progress)? onDownloadProgress;

  /// requirements.md FR-6。ストリームをエラー終了させる。
  final void Function(TranscribeException error) onError;

  /// ストリームを正常終了させる。
  final void Function() onDone;
}

/// Pigeon `@FlutterApi()` の`OfflineSttStreamCallbackApi`受け口
/// (design.md §2.3、Issue #52)。
///
/// ## なぜWindowsだけこのクラスが必要なのか
/// Android/Darwinは`segments` / `downloadProgress` の2本の
/// `@EventChannelApi`を持ち、Dart側は`pigeon.segments()` /
/// `pigeon.downloadProgress()`という独立したStreamをそれぞれ購読できる。
/// しかしPigeonのC++生成器はEventChannelに未対応であるため
/// (`pigeons/offline_stt_windows.dart`冒頭コメント参照)、Windowsは
/// `@FlutterApi()`のコールバック4本
/// (`onSegment` / `onDownloadProgress` / `onStreamError` / `onStreamDone`)
/// で代替している。このコールバックには**ストリーム識別子が無い**ため、
/// 「いまどの呼び出しのストリームに配送すべきか」をDart側で管理する必要が
/// ある。それが本クラスの役割である。
///
/// ## 同時に1本しか受け付けない理由
/// ネイティブ側(`windows/offline_stt_api_impl.cpp`)は
/// `OfflineSttStreamCallbackApi`のインスタンスを1つしか持たず、かつ
/// `OfflineSttHostApi.cancel()`は「実行中の1本」を対象とする契約である
/// (`pigeons/offline_stt_windows.dart`の`cancel`のdocコメント)。
/// したがってネイティブ側で同時に走れる操作は1本だけであり、Dart側の
/// 配送先も常に1本に定まる。2本目の[attach]は[StateError]で明確に
/// 失敗させる(design.md §3「2本目の開始は`StateError`」と同じ流儀)。
class WindowsStreamRouter implements pigeon.OfflineSttStreamCallbackApi {
  WindowsStreamRouter._();

  /// プロセス内で唯一のインスタンス。
  ///
  /// `OfflineSttStreamCallbackApi.setUp()`が張るのはプロセスグローバルな
  /// `BasicMessageChannel`のハンドラであり、複数インスタンスを登録すると
  /// 後勝ちで上書きされてしまうため、シングルトンにしている。
  static final WindowsStreamRouter instance = WindowsStreamRouter._();

  bool _registered = false;

  /// Pigeonのメッセージハンドラを(まだであれば)登録する。
  ///
  /// `OfflineSttWindows.registerWith()`から呼ぶ。冪等。
  void ensureRegistered() {
    if (_registered) return;
    _registered = true;
    pigeon.OfflineSttStreamCallbackApi.setUp(this);
  }

  WindowsStreamRoute? _active;

  /// 配送先を登録する。既に1本登録されている場合は[StateError]。
  void attach(WindowsStreamRoute route) {
    if (_active != null) {
      throw StateError(
        'offline_stt_windows: 既に実行中のストリームが存在する。'
        'Windowsネイティブ側(windows/offline_stt_api_impl.cpp)は'
        'ダウンロードと文字起こしを合わせて同時1本しか実行できず、'
        'Pigeonの@FlutterApiコールバックにもストリーム識別子が無いため、'
        '2本目を受け付けると配送先が一意に定まらない。1本目が終了'
        '(done/error/cancel)してから再度呼び出すこと。',
      );
    }
    _active = route;
  }

  /// 配送先の登録を解除する。既に別のrouteへ差し替わっている場合は何もしない。
  void detach(WindowsStreamRoute route) {
    if (identical(_active, route)) {
      _active = null;
    }
  }

  @override
  void onSegment(pigeon.TranscriptSegment segment) {
    final route = _active;
    // 配送先が無いのは「Dart側が既にキャンセル/終了処理を終えた後に、
    // ネイティブ側の最後のコールバックが到着した」場合である。既定値で
    // 埋める類のフォールバックではなく、宛先の無いイベントを捨てている
    // だけなので、ここでエラーにはしない(エラーにすると、正常な
    // キャンセル操作が毎回例外になってしまう)。
    if (route == null) return;
    final handler = route.onSegment;
    // `downloadModel()`のストリームに`onSegment`が届くことは設計上ありえず、
    // 届いたとすればネイティブ側の不具合である。握りつぶすと原因が
    // 分からなくなるためStateErrorとしてストリームをエラー終了させる。
    if (handler == null) {
      route.onError(
        PlatformException_(
          code: 'platformError',
          message:
              'offline_stt_windows: ダウンロード用のストリームに onSegment が'
              '届いた。ネイティブ側(windows/offline_stt_api_impl.cpp)の'
              '配送先取り違えである。',
        ),
      );
      return;
    }
    handler(TranscriptSegment(text: segment.text, isFinal: segment.isFinal));
  }

  @override
  void onDownloadProgress(pigeon.DownloadProgress progress) {
    final route = _active;
    if (route == null) return;
    final handler = route.onDownloadProgress;
    if (handler == null) {
      route.onError(
        PlatformException_(
          code: 'platformError',
          message:
              'offline_stt_windows: 文字起こし用のストリームに '
              'onDownloadProgress が届いた。ネイティブ側'
              '(windows/offline_stt_api_impl.cpp)の配送先取り違えである。',
        ),
      );
      return;
    }
    // design.md §4.4 のとおり、Windowsの進捗は不定進捗(fraction: null)で
    // 通知される。その判断の根拠はネイティブ側
    // `windows/model_acquisition.cpp` のコメントに記載している。
    // ここではネイティブから来た値をそのまま写すだけで丸めは行わない。
    handler(
      DownloadProgress(
        fraction: progress.fraction,
        completed: progress.completed,
      ),
    );
  }

  @override
  void onStreamError(pigeon.TranscribeErrorCode code, String? message) {
    final route = _active;
    if (route == null) return;
    route.onError(mapNativeErrorCode(code.name, message));
  }

  @override
  void onStreamDone() {
    final route = _active;
    if (route == null) return;
    route.onDone();
  }
}
