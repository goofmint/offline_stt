import 'package:flutter/services.dart' show PlatformException;
import '../common.dart';

import 'error_code_mapping.dart';

/// `package:flutter/services.dart`の[PlatformException]から
/// [TranscribeException]への変換(Issue #49)。EventChannelのエラー、
/// および同期HostApiメソッド呼び出し失敗はいずれもこの型でDartへ届く
/// (design.md §2.3参照)。
///
/// このファイルを`error_code_mapping.dart`から分けている理由:
/// `error_code_mapping.dart`は`flutter`パッケージに依存しない純粋な文字列
/// 分岐のみで構成しており、`dart test`(melos run test)でネイティブ・
/// Flutterウィジェット層に依存せず単体テストできる(`test/
/// error_code_mapping_test.dart`参照)。`PlatformException`は
/// `package:flutter/services.dart`のシンボルであり、これをimportする
/// ファイルを`dart test`のテストツリーから辿らせると、Flutter SDKが提供
/// する`dart:ui`パッチが無い素のDart SDKでのコンパイルに失敗する
/// (`flutter test`が必要になる)。model_management.dart/
/// recognition_session.dartはいずれもPigeonのHostApi/EventChannelを
/// 直接叩く層であり単体テスト対象外(各ファイル冒頭コメント参照)のため、
/// この変換ロジックをそちら専用の本ファイルへ切り出した
/// (Darwin実装と同じ切り分け方針)。
TranscribeException mapPlatformException(PlatformException exception) {
  return mapNativeErrorCode(exception.code, exception.message);
}
