/// Non-web builds: browser notifications do not exist here.
class WebNotify {
  WebNotify._();

  static bool get supported => false;

  /// 'granted', 'denied', 'default' or 'unsupported'.
  static String get permission => 'unsupported';

  static Future<String> requestPermission() async => 'unsupported';

  /// Whether the person is looking at the app right now.
  static bool get pageVisible => true;

  static Future<bool> show({
    required String title,
    required String body,
    String? tag,
    String? payload,
    bool urgent = false,
  }) async =>
      false;

  static void close(String tag) {}

  static void setBadge(int count) {}

  static void listen(void Function(String payload) onOpen) {}
}
