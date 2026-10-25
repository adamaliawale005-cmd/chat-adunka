import 'package:cloud_firestore/cloud_firestore.dart';

/// Public profile, stored in users/{uid}. Contains no phone number.
class AppUser {
  final String uid;
  final String displayName;
  final String? username;
  final String about;
  final String? photoBase64;
  final DateTime? lastSeen;
  final bool online;
  final bool exists;

  const AppUser({
    required this.uid,
    required this.displayName,
    this.username,
    this.about = '',
    this.photoBase64,
    this.lastSeen,
    this.online = false,
    this.exists = true,
  });

  /// Placeholder for an account that has been deleted.
  factory AppUser.missing(String uid) =>
      AppUser(uid: uid, displayName: '', exists: false);

  bool get hasProfile => exists && displayName.trim().isNotEmpty;

  /// "Online" is trusted for 2 minutes after the last heartbeat, because a
  /// phone that loses its connection cannot report going offline.
  bool get isOnlineNow =>
      online && lastSeen != null && DateTime.now().difference(lastSeen!).inMinutes < 2;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) return AppUser.missing(doc.id);
    final d = doc.data() ?? const <String, dynamic>{};
    final photo = d['photoBase64'];
    final seen = d['lastSeen'];
    final username = d['username'];
    return AppUser(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? '',
      username: username is String && username.isNotEmpty ? username : null,
      about: (d['about'] as String?) ?? '',
      photoBase64: photo is String && photo.isNotEmpty ? photo : null,
      lastSeen: seen is Timestamp ? seen.toDate() : null,
      online: d['online'] == true,
    );
  }
}

/// Private account settings, stored in users/{uid}/private/account and
/// readable only by the owner.
class AccountPrivate {
  final String? phoneNumber;
  final String? email;
  final bool discoverableByPhone;
  final bool showInDirectory;
  final bool showLastSeen;
  final bool readReceipts;
  final bool contactSync;
  final bool notifyMessages;
  final bool notifyGroups;
  final bool notifyCalls;
  final bool notificationPreview;

  const AccountPrivate({
    this.phoneNumber,
    this.email,
    this.discoverableByPhone = true,
    this.showInDirectory = true,
    this.showLastSeen = true,
    this.readReceipts = true,
    this.contactSync = false,
    this.notifyMessages = true,
    this.notifyGroups = true,
    this.notifyCalls = true,
    this.notificationPreview = true,
  });

  static const defaults = AccountPrivate();

  factory AccountPrivate.fromMap(Map<String, dynamic>? d) {
    if (d == null) return defaults;
    bool b(String k, bool def) => d[k] is bool ? d[k] as bool : def;
    final n = (d['notifications'] as Map?)?.cast<String, dynamic>() ?? const {};
    bool nb(String k) => n[k] is bool ? n[k] as bool : true;
    return AccountPrivate(
      phoneNumber: d['phoneNumber'] as String?,
      email: d['email'] as String?,
      discoverableByPhone: b('discoverableByPhone', true),
      showInDirectory: b('showInDirectory', true),
      showLastSeen: b('showLastSeen', true),
      readReceipts: b('readReceipts', true),
      contactSync: b('contactSync', false),
      notifyMessages: nb('messages'),
      notifyGroups: nb('groups'),
      notifyCalls: nb('calls'),
      notificationPreview: nb('preview'),
    );
  }

  Map<String, dynamic> toMap() => {
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (email != null) 'email': email,
        'discoverableByPhone': discoverableByPhone,
        'showInDirectory': showInDirectory,
        'showLastSeen': showLastSeen,
        'readReceipts': readReceipts,
        'contactSync': contactSync,
        'notifications': {
          'messages': notifyMessages,
          'groups': notifyGroups,
          'calls': notifyCalls,
          'preview': notificationPreview,
        },
      };

  AccountPrivate copyWith({
    bool? discoverableByPhone,
    bool? showInDirectory,
    bool? showLastSeen,
    bool? readReceipts,
    bool? contactSync,
    bool? notifyMessages,
    bool? notifyGroups,
    bool? notifyCalls,
    bool? notificationPreview,
  }) =>
      AccountPrivate(
        phoneNumber: phoneNumber,
        email: email,
        discoverableByPhone: discoverableByPhone ?? this.discoverableByPhone,
        showInDirectory: showInDirectory ?? this.showInDirectory,
        showLastSeen: showLastSeen ?? this.showLastSeen,
        readReceipts: readReceipts ?? this.readReceipts,
        contactSync: contactSync ?? this.contactSync,
        notifyMessages: notifyMessages ?? this.notifyMessages,
        notifyGroups: notifyGroups ?? this.notifyGroups,
        notifyCalls: notifyCalls ?? this.notifyCalls,
        notificationPreview: notificationPreview ?? this.notificationPreview,
      );
}

/// Username rules shared by the app and firestore.rules:
/// 3-20 characters, lowercase letters, digits and "_", starting with a letter.
final RegExp usernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

String normalizeUsername(String input) => input.trim().toLowerCase().replaceAll('@', '');
