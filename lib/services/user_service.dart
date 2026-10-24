import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

/// Profiles live in `users/{uid}`. Profile pictures are stored as a small
/// compressed JPEG (base64) inside the document, so no Cloud Storage bucket
/// (which needs the paid Blaze plan) is required.
class UserService {
  UserService._();
  static final UserService instance = UserService._();

  CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  Stream<AppUser?> watchUser(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);

  Future<void> saveProfile({
    required String uid,
    required String phoneNumber,
    required String displayName,
    required String about,
    String? photoBase64,
    bool removePhoto = false,
  }) async {
    final ref = _users.doc(uid);
    final existing = await ref.get();
    final name = displayName.trim();
    final data = <String, dynamic>{
      'uid': uid,
      'phoneNumber': phoneNumber,
      'displayName': name,
      'displayNameLower': name.toLowerCase(),
      'about': about.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    if (photoBase64 != null) {
      data['photoBase64'] = photoBase64;
    } else if (removePhoto) {
      data['photoBase64'] = FieldValue.delete();
    }
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> touchLastSeen(String uid) async {
    try {
      await _users.doc(uid).update({'lastSeen': FieldValue.serverTimestamp()});
    } on FirebaseException {
      // Profile may not exist yet; ignore.
    }
  }

  /// All registered users, sorted by name. Suitable for small/test user
  /// bases; for large audiences replace with paged search.
  Stream<List<AppUser>> watchDirectory() => _users
      .orderBy('displayNameLower')
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).where((u) => u.hasProfile).toList());

  Future<AppUser?> findByPhone(String e164) async {
    final s = await _users.where('phoneNumber', isEqualTo: e164).limit(1).get();
    if (s.docs.isEmpty) return null;
    return AppUser.fromDoc(s.docs.first);
  }
}
