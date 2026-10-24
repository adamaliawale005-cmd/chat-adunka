import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String phoneNumber;
  final String about;
  final String? photoBase64;
  final DateTime? lastSeen;

  const AppUser({
    required this.uid,
    required this.displayName,
    required this.phoneNumber,
    this.about = '',
    this.photoBase64,
    this.lastSeen,
  });

  bool get hasProfile => displayName.trim().isNotEmpty;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final photo = d['photoBase64'];
    final seen = d['lastSeen'];
    return AppUser(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? '',
      phoneNumber: (d['phoneNumber'] as String?) ?? '',
      about: (d['about'] as String?) ?? '',
      photoBase64: photo is String && photo.isNotEmpty ? photo : null,
      lastSeen: seen is Timestamp ? seen.toDate() : null,
    );
  }
}
