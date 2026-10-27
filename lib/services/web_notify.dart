/// Browser notifications for the web app (see web/notify.js).
///
/// On Android, iOS and desktop builds every function is a harmless no-op.
library;

export 'web_notify_stub.dart'
    if (dart.library.js_interop) 'web_notify_web.dart';
