import 'package:country_picker/country_picker.dart';

import '../../services/user_service.dart';
import '../../utils/phone.dart';

/// Looks people up by username, name, or an exact phone number.
/// Phone lookups only find people who allow it in their privacy settings.
Future<List<String>> searchPeople(String query,
    {required String me, String? myPhone}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final ids = <String>{};
  final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
  final looksLikePhone =
      RegExp(r'^[+0-9 ()-]+$').hasMatch(q) && digits.length >= 7;
  if (looksLikePhone) {
    final codes = CountryService().getAll().map((c) => c.phoneCode).toSet();
    final myCode =
        (myPhone != null ? dialCodeOf(myPhone, codes) : null) ?? '252';
    final e164 = toE164(myCode, q);
    if (isPlausibleE164(e164)) {
      final uid = await UserService.instance.findUidByPhone(e164);
      if (uid != null) ids.add(uid);
    }
  } else {
    ids.addAll(await UserService.instance.searchDirectory(q));
  }
  ids.remove(me);
  return ids.toList();
}
