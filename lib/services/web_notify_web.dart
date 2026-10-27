import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web builds: calls window.aduchatNotify from web/notify.js.
class WebNotify {
  WebNotify._();

  static JSObject? get _api {
    if (!globalContext.has('aduchatNotify')) return null;
    final api = globalContext['aduchatNotify'];
    return api == null ? null : api as JSObject;
  }

  static T? _call<T extends JSAny?>(String name,
      [JSAny? a, JSAny? b, JSAny? c, JSAny? d, JSAny? e]) {
    final api = _api;
    if (api == null) return null;
    try {
      return api.callMethodVarArgs<T>(
          name.toJS, [a, b, c, d, e].takeWhile((x) => x != null).toList());
    } catch (_) {
      return null;
    }
  }

  static bool get supported => _call<JSBoolean>('supported')?.toDart ?? false;

  /// 'granted', 'denied', 'default' or 'unsupported'.
  static String get permission =>
      _call<JSString>('permission')?.toDart ?? 'unsupported';

  static Future<String> requestPermission() async {
    final p = _call<JSPromise<JSString>>('request');
    if (p == null) return 'unsupported';
    try {
      return (await p.toDart).toDart;
    } catch (_) {
      return permission;
    }
  }

  /// Whether the person is looking at the app right now.
  static bool get pageVisible => _call<JSBoolean>('visible')?.toDart ?? true;

  static Future<bool> show({
    required String title,
    required String body,
    String? tag,
    String? payload,
    bool urgent = false,
  }) async {
    final p = _call<JSPromise<JSBoolean>>('show', title.toJS, body.toJS,
        (tag ?? '').toJS, (payload ?? '').toJS, urgent.toJS);
    if (p == null) return false;
    try {
      return (await p.toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  static void close(String tag) => _call<JSAny?>('close', tag.toJS);

  static void setBadge(int count) => _call<JSAny?>('setBadge', count.toJS);

  static void listen(void Function(String payload) onOpen) {
    _call<JSAny?>(
        'listen', ((JSString p) => onOpen(p.toDart)).toJS);
  }
}
