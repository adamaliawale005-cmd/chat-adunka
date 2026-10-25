import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

/// Signed-in user's live settings, shared across screens.
class Session {
  Session._();

  static String? uid;

  /// Private account settings (privacy and notification preferences).
  static final ValueNotifier<AccountPrivate> settings = ValueNotifier(AccountPrivate.defaults);

  /// People this user has blocked.
  static final ValueNotifier<Set<String>> blocked = ValueNotifier(<String>{});

  static void clear() {
    uid = null;
    settings.value = AccountPrivate.defaults;
    blocked.value = <String>{};
  }
}
