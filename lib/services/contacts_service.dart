import 'dart:convert';

import 'package:country_picker/country_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../state/app_settings.dart';
import '../utils/phone.dart';
import 'user_service.dart';

class ContactMatch {
  final String uid;
  final String contactName;
  final String phone;
  const ContactMatch(
      {required this.uid, required this.contactName, required this.phone});

  Map<String, String> toJson() =>
      {'uid': uid, 'name': contactName, 'phone': phone};
  factory ContactMatch.fromJson(Map<String, dynamic> j) => ContactMatch(
        uid: j['uid'] as String,
        contactName: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
      );
}

/// Optional contact discovery.
///
/// Privacy: the address book is never uploaded. Each number is looked up
/// one at a time in phoneIndex/{number}, which only contains people who
/// chose to be discoverable by phone. Matches are kept on this phone only.
class ContactsService {
  ContactsService._();
  static final ContactsService instance = ContactsService._();

  static const _cacheKey = 'contact_matches';
  static const maxNumbers = 800;

  List<ContactMatch> cached() {
    final raw = AppSettings.instance.prefs?.getString(_cacheKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ContactMatch.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clear() async {
    await AppSettings.instance.prefs?.remove(_cacheKey);
  }

  Future<bool> hasPermission() =>
      FlutterContacts.requestPermission(readonly: true);

  /// Reads contacts, looks them up, stores and returns the matches.
  Future<List<ContactMatch>> sync(
      {required String myUid, String? myPhone}) async {
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      throw const ContactsPermissionDenied();
    }
    final codes = CountryService().getAll().map((c) => c.phoneCode).toSet();
    final defaultCode =
        (myPhone != null ? dialCodeOf(myPhone, codes) : null) ?? '252';

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final numbers = <String, String>{}; // e164 -> contact name
    for (final c in contacts) {
      for (final p in c.phones) {
        final n = normalizeContactNumber(
            p.normalizedNumber.isNotEmpty ? p.normalizedNumber : p.number,
            defaultCode);
        if (n != null && n != myPhone)
          numbers.putIfAbsent(n, () => c.displayName);
        if (numbers.length >= maxNumbers) break;
      }
      if (numbers.length >= maxNumbers) break;
    }

    final matches = <ContactMatch>[];
    final entries = numbers.entries.toList();
    for (var i = 0; i < entries.length; i += 20) {
      final chunk =
          entries.sublist(i, i + 20 > entries.length ? entries.length : i + 20);
      final found = await Future.wait(
          chunk.map((e) => UserService.instance.findUidByPhone(e.key)));
      for (var j = 0; j < chunk.length; j++) {
        final uid = found[j];
        if (uid != null && uid != myUid) {
          matches.add(ContactMatch(
              uid: uid, contactName: chunk[j].value, phone: chunk[j].key));
        }
      }
    }
    matches.sort((a, b) =>
        a.contactName.toLowerCase().compareTo(b.contactName.toLowerCase()));
    await AppSettings.instance.prefs?.setString(
        _cacheKey, jsonEncode(matches.map((m) => m.toJson()).toList()));
    return matches;
  }
}

class ContactsPermissionDenied implements Exception {
  const ContactsPermissionDenied();
}
