/// `offline_stt` のWindows実装パッケージ。
///
/// **利用者がこのパッケージへ直接依存することはない**(requirements.md §6)。
/// アプリは `offline_stt` にのみ依存すれば、エントリパッケージの
/// `flutter.plugin.platforms.windows.default_package` によってこの実装が
/// 自動的に選択される(design.md §1 のfederated plugin構成)。
///
/// **ただしWindowsだけは依存関係を書くだけでは動かない。** アプリを MSIX で
/// パッケージ化して `systemAIModels` capability を宣言し、`winapp init` で
/// WinAppSDK の C++/WinRT プロジェクションヘッダーを配置する必要がある。
/// 手順とその未検証箇所は本パッケージの `README.md` にある。
///
/// **本パッケージのネイティブ実装は一度も実行されていない。** Windows実機が
/// 無いため、WinRT実装のコンパイル・MSIX化・認識のいずれも未実施である
/// (CIはWinRTバックエンドを除外した構成のみをコンパイルする)。実機での
/// 確認はIssue #58に委ねている。
///
/// 公開APIは [OfflineSttWindows] のみである。`src/stream_router.dart` の
/// `WindowsStreamRouter` は本バレルから export しておらず、内部実装として
/// `registerWith()` から使う。詳細は [OfflineSttWindows] のdocコメントを
/// 参照すること。
library;

import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';
// offline_stt_platform_interfaceのdocコメント(lib/src/session_guard.dart)が
// 明記するとおり、TranscribeSessionGuardはネイティブ実装パッケージ間だけの
// 共有実装であり、公開バレルには意図的に含まれていない。そのためsrc/への
// 直接importが必要であり、implementation_importsのlintは意図的に抑止する。
// ignore: implementation_imports
import 'package:offline_stt_platform_interface/src/session_guard.dart';

import 'src/model_management.dart' as model_management;
import 'src/pigeon.g.dart' as pigeon;
import 'src/recognition_session.dart';
import 'src/stream_router.dart';

/// `offline_stt`のWindows実装(design.md §4.4、Issue #52〜#56)。
///
/// Pigeon生成コード(`pigeons/offline_stt_windows.dart`から生成、Issue #24)
/// のHostApi(MethodChannel)/FlutterApiコールバックを介して、C++/WinRT
/// 実装本体(`windows/`。`Microsoft.Windows.AI.Speech`の
/// `SpeechRecognitionModel` + `BatchRecognition`、およびMedia Foundationに
/// よるwav変換)と通信する。`spikes/windows/`のドキュメント調査結果
/// (spikes/windows/RESULTS.md)を移植の出発点とした。
///
/// design.md §1・§4.4が定める3モジュール境界をそのまま維持している:
/// - モデル管理: `src/model_management.dart`(Issue #53)
/// - デコード・認識セッション・キャンセル: `src/recognition_session.dart`
///   (Issue #54〜#56)
///
/// セッション排他(design.md §3、同時1本まで)は
/// `offline_stt_platform_interface`の`TranscribeSessionGuard`を`with`して
/// 満たす(`offline_stt_darwin`/`offline_stt_web`と同じ構成)。
///
/// ## Windows固有の事情(Android/Darwinとの差分)
/// PigeonのC++生成器が`@EventChannelApi`に未対応であるため、Windowsだけは
/// ストリームを`@FlutterApi()`のコールバック4本で代替している
/// (`pigeons/offline_stt_windows.dart`冒頭コメント参照)。コールバックに
/// ストリーム識別子が無いため、配送先の管理は`src/stream_router.dart`の
/// [WindowsStreamRouter]が担う。
///
/// ## 未検証であること(重要)
/// 本パッケージのネイティブ実装(`windows/`)は、Windows実機が無いため
/// **一度もビルド・実行されていない**。`Microsoft.Windows.AI.Speech`の
/// プロジェクションヘッダーを得るためのWinAppSDK配線も未確定であり、
/// `windows/CMakeLists.txt`では既定で無効化してある(同ファイルの
/// コメント参照)。実機での確認はIssue #58で行う。
class OfflineSttWindows extends OfflineTranscriberPlatform
    with TranscribeSessionGuard {
  /// `dartPluginClass`からFlutterに自動登録されるエントリポイント。
  static void registerWith() {
    // ネイティブ→Dartのストリームコールバック受け口を先に張っておく
    // (登録前にネイティブから呼ばれることは無いが、`instance`の差し替え
    // より先に済ませておくほうが順序依存が無い)。
    WindowsStreamRouter.instance.ensureRegistered();
    OfflineTranscriberPlatform.instance = OfflineSttWindows();
  }

  /// Pigeon生成のMethodチャネルAPI(design.md §2.3)。
  final pigeon.OfflineSttHostApi _hostApi = pigeon.OfflineSttHostApi();

  @override
  Future<ModelState> checkModel(String locale) =>
      model_management.checkModel(_hostApi, locale);

  @override
  Stream<DownloadProgress> downloadModel(String locale) =>
      model_management.downloadModel(_hostApi, locale);

  @override
  Stream<TranscriptSegment> transcribeFile(TranscribeRequest request) =>
      guardSession(() => runTranscriptionSession(_hostApi, request));
}
