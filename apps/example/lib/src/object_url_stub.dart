import 'dart:typed_data';

/// `object_url.dart` の非Webプラットフォーム向け実装(条件付きexportの
/// 既定側)。
///
/// ObjectURL(Blob URL)はWeb専用の概念であり(design.md §2.2「Webでは
/// Blob URL / ObjectURL」)、非Webプラットフォームではファイルシステム
/// パスをそのまま使う。呼び出し側は `kIsWeb` で分岐したうえでのみこちらの
/// 関数を呼ぶ想定であり、誤って呼ばれた場合は「とりあえず動く」フォール
/// バックではなく明確な失敗にする(CLAUDE.mdのフォールバック禁止方針)。
String createObjectUrlFromBytes(Uint8List bytes, {required String mimeType}) {
  throw UnsupportedError(
    'createObjectUrlFromBytes() はWeb専用である。kIsWebで分岐してから'
    '呼び出すこと。',
  );
}

/// [createObjectUrlFromBytes] が生成したURLを解放する(非Web版)。
void revokeObjectUrl(String url) {
  throw UnsupportedError('revokeObjectUrl() はWeb専用である。kIsWebで分岐してから呼び出すこと。');
}
