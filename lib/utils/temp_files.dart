// Writes bytes to a temporary file on phones and desktops. Browsers have no
// file system, so the web version returns null and callers use the bytes.
export 'temp_files_io.dart' if (dart.library.js_interop) 'temp_files_web.dart';
