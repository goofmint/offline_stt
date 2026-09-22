import '../common.dart';

/// ネイティブ側(`darwin/Classes/DarwinTranscribeError.swift`の
/// `TranscribeErrorCode.wireCode`)が`FlutterError`/EventChannelのエラー
/// シンクへ渡す`code`文字列を[TranscribeException]へ写像する
/// (design.md §5 エラーマッピング表 Darwin列、Issue #39)。
///
/// EventChannelの組み込みエラーシンク、および同期HostApiメソッド
/// (`checkModel`等)の失敗は、いずれもFlutter側で自動的に
/// `package:flutter/services.dart`の`PlatformException`としてDartへ届く
/// (design.md §2.3「Android/DarwinではEventChannelの組み込みエラーシンクを
/// 使うため、スキーマ上は定義のみとする」)。`PlatformException`からの
/// 変換は`platform_exception_mapping.dart`の`mapPlatformException`が担う
/// (本ファイルは`flutter`パッケージに依存しない純粋ロジックのみに保ち、
/// `dart test`でネイティブに依存せず単体テストできるようにするため、
/// あえて分けている)。
///
/// ネイティブ側が返す`code`文字列は、Pigeon生成の`TranscribeErrorCode`の
/// enum名の文字列表現(`modelUnavailable`/`localeUnsupported`/
/// `decodeFailed`/`deviceUnsupported`/`cancelled`/`platformError`)と
/// 完全一致させている。両者の対応が崩れないよう、どちらかを変更する場合は
/// 必ずもう一方も同時に更新すること。
///
/// ネイティブAPIに依存しない純粋な文字列分岐のみであるため単体テストが
/// 書ける(`test/error_code_mapping_test.dart`参照)。
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
