import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

void saveFileOnWeb(String filename, Uint8List bytes) {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
}
