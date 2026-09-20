import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// バイト列からBlob URL(ObjectURL)を生成する(design.md §2.2)。
///
/// design.md §2.2 は「`TranscribeRequest.path` … Webでは Blob URL /
/// ObjectURL」と定める。`file_picker` はWeb上ではファイルシステムパスを
/// 返せない(`PlatformFile.path` は常に `null`)ため、代わりに取得した
/// バイト列(`PlatformFile.bytes`)から `Blob` を組み立て、
/// `URL.createObjectURL()` でObjectURLへ変換する。
String createObjectUrlFromBytes(Uint8List bytes, {required String mimeType}) {
  final blobParts = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  return web.URL.createObjectURL(blob);
}

/// [createObjectUrlFromBytes] が生成したURLを解放する。
///
/// `URL.createObjectURL()` が確保するメモリはタブを閉じるかページ自体が
/// 破棄されるまで解放されないため、使い終わったら明示的に
/// `revokeObjectURL()` を呼ぶことが推奨されている。example appでは
/// 新しいファイルを選び直すとき・画面破棄時に呼び出す。
void revokeObjectUrl(String url) {
  web.URL.revokeObjectURL(url);
}
