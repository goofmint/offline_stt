import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

/// ネイティブ側(`windows/windows_transcribe_error.cpp`の`WireCode()`)が
/// `FlutterError.code`、および`OfflineSttStreamCallbackApi.onStreamError`の
/// `TranscribeErrorCode`として渡す文字列を[TranscribeException]へ写像する
/// (design.md §5 エラーマッピング表 Windows列、Issue #56)。
///
/// ## Windowsだけ経路が2本ある理由
/// Android/Darwinは`@EventChannelApi`の組み込みエラーシンクを使うため、
/// ストリームのエラーは`PlatformException`としてDartへ届く。しかし
/// PigeonのC++生成器はEventChannelに未対応であり
/// (`pigeons/offline_stt_windows.dart`冒頭コメント参照)、Windowsは
/// `@FlutterApi()`の`onStreamError(TranscribeErrorCode, String?)`で
/// エラーを受け取る。そのため本ファイルの写像関数は、
/// - `hostApi.checkModel()`等の失敗 → `PlatformException.code`
///   (`platform_exception_mapping.dart`経由)
/// - ストリームのエラー → `pigeon.TranscribeErrorCode.name`
///   (`stream_router.dart`経由)
/// の2経路から、いずれも「enum名の文字列」として呼ばれる。両者が同じ
/// 文字列集合になるよう、ネイティブ側は`FlutterError.code`にも
/// `TranscribeErrorCode`のenum名をそのまま入れる。
///
/// ネイティブAPIに依存しない純粋な文字列分岐のみであるため単体テストが
/// 書ける(`test/error_code_mapping_test.dart`参照)。
///
/// ## Windowsでは`localeUnsupported`が発生しない
/// design.md §4.4・§8 未決事項2のとおり、`Microsoft.Windows.AI.Speech`
/// にはロケール・言語を指定するAPIが存在しないことがドキュメント調査で
/// 確定している。したがってWindowsネイティブ実装はこのcodeを発生させない。
/// それでも分岐を残しているのは、writeとreadの対応表を
/// `offline_stt_darwin`/`offline_stt_android`と完全に揃えておくためで
/// ある(将来ロケール指定APIが追加された場合に写像側の変更が不要になる)。
TranscribeException mapNativeErrorCode(String code, String? message) {
  switch (code) {
    case 'modelUnavailable':
      return const ModelUnavailableException();
    case 'localeUnsupported':
      return const LocaleUnsupportedException();
    case 'decodeFailed':
      return const DecodeFailedException();
    case 'deviceUnsupported':
      return const DeviceUnsupportedException();
    case 'cancelled':
      return const CancelledException();
    default:
      // `platformError`、および design.md にない未知のcodeはいずれも
      // ここに落ちる。[PlatformException_]は design.md §2.2 で
      // 「上記のいずれにも分類できないプラットフォーム固有のエラー」を
      // 表す型として定義されており、この分岐は本来の役割どおりの使い方
      // であって、方針で禁止されたフォールバックではない
      // (未知の値を無言で「動く」既定値へ丸めているわけではなく、
      // codeをそのまま保持して呼び出し元へ伝えている)。
      return PlatformException_(code: code, message: message);
  }
}
