import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String?> writeTempFile(String name, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final f = File('${dir.path}/$safe');
  if (!await f.exists() || await f.length() != bytes.length) {
    await f.writeAsBytes(bytes, flush: true);
  }
  return f.path;
}
