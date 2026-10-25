import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class UsernameTakenException implements Exception {
  const UsernameTakenException();
}

/// A profile-save step that Firestore refused, with the document path.
class ProfileSaveException implements Exception {
  final String step;
  final String code;
  final Object error;
  const ProfileSaveException(this.step, this.code, this.error);

  bool get permissionDenied => code == 'permission-denied';

  @override
  String toString() => 'ProfileSaveException($step, $code): $error';
}

/// Version of firestore.rules this app expects (see rulesVersion in the rules).
const expectedRulesVersion = '2026-10-25';

/// Profiles, usernames, privacy settings, presence, blocking, reports and
/// account deletion.
///
/// Profile pictures are compressed (about 256 px) and stored inside the
/// profile document, so no Cloud Storage (Blaze plan) is needed for them.
class UserService {
  UserService._();
  static final UserService instance = UserService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  DocumentReference<Map<String, dynamic>> _private(String uid) =>
      _users.doc(uid).collection('private').doc('account');

  final Map<String, Stream<AppUser>> _userStreams = {};
  final Map<String, AppUser> _latest = {};

  /// Shared stream of a public profile. Pair it with [cachedUser] as the
  /// StreamBuilder's initialData, because a shared stream does not replay
  /// its last value to new listeners.
  Stream<AppUser> watchUser(String uid) => _userStreams.putIfAbsent(
        uid,
        () => _users
            .doc(uid)
            .snapshots()
            .map((d) => _latest[uid] = AppUser.fromDoc(d))
            .handleError((_) {})
            .asBroadcastStream(),
      );

  /// Last known profile for [uid], if any.
  AppUser? cachedUser(String uid) => _latest[uid];

  /// Profile stream that reports errors (used by the sign-in gate).
  Stream<AppUser> watchUserStrict(String uid) =>
      _users.doc(uid).snapshots().map((d) => _latest[uid] = AppUser.fromDoc(d));

  Future<AppUser> getUser(String uid) async {
    final cached = _latest[uid];
    if (cached != null) return cached;
    try {
      return _latest[uid] = AppUser.fromDoc(await _users.doc(uid).get());
    } on FirebaseException {
      return AppUser.missing(uid);
    }
  }

  Stream<AccountPrivate> watchPrivate(String uid) =>
      _private(uid).snapshots().map((s) => AccountPrivate.fromMap(s.data()));

  Future<AccountPrivate> getPrivate(String uid) async {
    try {
      return AccountPrivate.fromMap((await _private(uid).get()).data());
    } on FirebaseException {
      return AccountPrivate.defaults;
    }
  }

  // ---------- usernames ----------

  Future<bool> isUsernameAvailable(String username, {String? forUid}) async {
    final doc = await _db.collection('usernames').doc(username).get();
    if (!doc.exists) return true;
    return forUid != null && doc.data()?['uid'] == forUid;
  }

  // ---------- profile ----------

  /// Creates or updates the profile. Claims the username atomically, so two
  /// people can never end up with the same one.
  Future<void> saveProfile({
    required User authUser,
    required String displayName,
    required String username,
    required String about,
    String? photoBase64,
    bool removePhoto = false,
  }) async {
    final uid = authUser.uid;
    final name = displayName.trim();
    final uname = normalizeUsername(username);
    final userRef = _users.doc(uid);
    final privateBefore = await getPrivate(uid);

    await _step('users/$uid + usernames/$uname', () => _db.runTransaction((tx) async {
      final current = await tx.get(userRef);
      final oldUsername = current.data()?['username'] as String?;
      if (uname != oldUsername) {
        final claim = await tx.get(_db.collection('usernames').doc(uname));
        if (claim.exists && claim.data()?['uid'] != uid) {
          throw const UsernameTakenException();
        }
        tx.set(_db.collection('usernames').doc(uname), {
          'uid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (oldUsername != null && oldUsername.isNotEmpty) {
          tx.delete(_db.collection('usernames').doc(oldUsername));
        }
      }
      final data = <String, dynamic>{
        'uid': uid,
        'displayName': name,
        'displayNameLower': name.toLowerCase(),
        'username': uname,
        'usernameLower': uname,
        'about': about.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!current.exists) data['createdAt'] = FieldValue.serverTimestamp();
      if (photoBase64 != null) {
        data['photoBase64'] = photoBase64;
      } else if (removePhoto) {
        data['photoBase64'] = FieldValue.delete();
      }
      tx.set(userRef, data, SetOptions(merge: true));
    }));

    // Private account record (phone/email) and opt-in indexes.
    final private = AccountPrivate(
      phoneNumber: authUser.phoneNumber,
      email: authUser.email,
      discoverableByPhone: privateBefore.discoverableByPhone,
      showInDirectory: privateBefore.showInDirectory,
      showLastSeen: privateBefore.showLastSeen,
      readReceipts: privateBefore.readReceipts,
      contactSync: privateBefore.contactSync,
      notifyMessages: privateBefore.notifyMessages,
      notifyGroups: privateBefore.notifyGroups,
      notifyCalls: privateBefore.notifyCalls,
      notificationPreview: privateBefore.notificationPreview,
    );
    await _step('users/$uid/private/account',
        () => _private(uid).set(private.toMap(), SetOptions(merge: true)));
    await _applyIndexes(authUser, private, name, uname);
  }

  Future<T> _step<T>(String path, Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw ProfileSaveException(path, e.code, e);
    }
  }

  /// False when the rules published in Firebase are older than this app
  /// expects (the probe read is refused).
  Future<bool> rulesUpToDate() async {
    try {
      await _db.collection('rulesVersion').doc(expectedRulesVersion).get();
      return true;
    } on FirebaseException catch (e) {
      return e.code != 'permission-denied';
    }
  }

  Future<void> _applyIndexes(
      User authUser, AccountPrivate p, String name, String username) async {
    final uid = authUser.uid;
    final phone = authUser.phoneNumber;
    if (phone != null && phone.isNotEmpty) {
      final ref = _db.collection('phoneIndex').doc(phone);
      if (p.discoverableByPhone) {
        await _step('phoneIndex/$phone',
            () => ref.set({'uid': uid, 'updatedAt': FieldValue.serverTimestamp()}));
      } else {
        await _ignoreErrors(ref.delete());
      }
    }
    final dir = _db.collection('directory').doc(uid);
    if (p.showInDirectory) {
      await _step('directory/$uid', () => dir.set({
        'uid': uid,
        'displayName': name,
        'displayNameLower': name.toLowerCase(),
        'username': username,
        'usernameLower': username,
        'updatedAt': FieldValue.serverTimestamp(),
      }));
    } else {
      await _ignoreErrors(dir.delete());
    }
  }

  // ---------- privacy & notification settings ----------

  Future<void> updatePrivate(User authUser, AccountPrivate settings) async {
    await _private(authUser.uid).set(settings.toMap(), SetOptions(merge: true));
    final me = await getUser(authUser.uid);
    if (me.hasProfile) {
      await _applyIndexes(
          authUser, settings, me.displayName, me.username ?? '');
    }
    if (!settings.showLastSeen) {
      await _ignoreErrors(_users.doc(authUser.uid).update({
        'online': FieldValue.delete(),
        'lastSeen': FieldValue.delete(),
      }));
    }
  }

  // ---------- presence ----------

  bool _showLastSeen = true;

  void setShowLastSeen(bool value) => _showLastSeen = value;

  Future<void> setPresence(String uid, {required bool online}) async {
    if (!_showLastSeen) return;
    await _ignoreErrors(_users.doc(uid).update({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    }));
  }

  // ---------- search ----------

  /// Exact phone lookup (only finds people who allow it).
  Future<String?> findUidByPhone(String e164) async {
    try {
      final doc = await _db.collection('phoneIndex').doc(e164).get();
      return doc.data()?['uid'] as String?;
    } on FirebaseException {
      return null;
    }
  }

  /// Prefix search on username and name among people who are listed in the
  /// directory. Returns user ids.
  Future<List<String>> searchDirectory(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase().replaceAll('@', '');
    if (q.length < 2) return const [];
    final end = '$q';
    final dir = _db.collection('directory');
    final results = await Future.wait([
      dir
          .where('usernameLower', isGreaterThanOrEqualTo: q)
          .where('usernameLower', isLessThan: end)
          .limit(limit)
          .get(),
      dir
          .where('displayNameLower', isGreaterThanOrEqualTo: q)
          .where('displayNameLower', isLessThan: end)
          .limit(limit)
          .get(),
    ]);
    final ids = <String>{};
    for (final r in results) {
      for (final d in r.docs) {
        ids.add(d.id);
      }
    }
    return ids.toList();
  }

  // ---------- blocking & reports ----------

  Stream<Set<String>> watchBlocked(String uid) => _users
      .doc(uid)
      .collection('blocked')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());

  Future<void> block(String me, String other) =>
      _users.doc(me).collection('blocked').doc(other).set({
        'uid': other,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> unblock(String me, String other) =>
      _users.doc(me).collection('blocked').doc(other).delete();

  Future<void> report({
    required String reporterId,
    required String reportedUid,
    required String reason,
    String details = '',
    String? chatId,
    String? messageId,
  }) =>
      _db.collection('reports').add({
        'reporterId': reporterId,
        'reportedUid': reportedUid,
        'reason': reason,
        'details': details.length > 1000 ? details.substring(0, 1000) : details,
        if (chatId != null) 'chatId': chatId,
        if (messageId != null) 'messageId': messageId,
        'createdAt': FieldValue.serverTimestamp(),
      });

  // ---------- account deletion ----------

  /// Deletes the user's profile, indexes, settings, devices, block list and
  /// call history, then the Firebase Auth account. Messages already
  /// delivered to other people remain in their chats and are shown as sent
  /// by a deleted account.
  Future<void> deleteAccount(User authUser) async {
    final uid = authUser.uid;
    final userRef = _users.doc(uid);
    final profile = await userRef.get();
    final username = profile.data()?['username'] as String?;

    Future<void> deleteCollection(
        CollectionReference<Map<String, dynamic>> col) async {
      while (true) {
        final page = await col.limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (page.docs.length < 200) break;
      }
    }

    await deleteCollection(userRef.collection('devices'));
    await deleteCollection(userRef.collection('blocked'));
    await deleteCollection(userRef.collection('calls'));
    await deleteCollection(userRef.collection('private'));
    if (authUser.phoneNumber != null) {
      await _ignoreErrors(
          _db.collection('phoneIndex').doc(authUser.phoneNumber).delete());
    }
    if (username != null && username.isNotEmpty) {
      await _ignoreErrors(_db.collection('usernames').doc(username).delete());
    }
    await _ignoreErrors(_db.collection('directory').doc(uid).delete());
    await userRef.delete();
    await authUser.delete();
  }

  Future<void> _ignoreErrors(Future<void> f) async {
    try {
      await f;
    } on FirebaseException {
      // Missing documents or offline: nothing to do.
    }
  }
}
