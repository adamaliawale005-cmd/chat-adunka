import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_models.dart';

/// Private one-to-one chats.
///
/// chats/{uidA_uidB}                 participants, lastMessage, lastSenderId, lastMessageAt
/// chats/{uidA_uidB}/messages/{id}   senderId, receiverId, text, status, timestamps
///
/// Message status: sent (stored on server) -> delivered (receiver's device
/// fetched it) -> read (receiver opened the chat). Only the receiver may move
/// the status forward; this is enforced in firestore.rules.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('chats');

  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  Stream<List<ChatSummary>> watchChats(String uid) => _chats
      .where('participants', arrayContains: uid)
      .snapshots()
      .map((s) {
        final list = s.docs.map(ChatSummary.fromDoc).toList();
        list.sort((a, b) => (b.updatedAt ?? DateTime(2100))
            .compareTo(a.updatedAt ?? DateTime(2100)));
        return list;
      });

  Stream<List<ChatMessage>> watchMessages(String chatId) => _chats
      .doc(chatId)
      .collection('messages')
      .orderBy('clientCreatedAt', descending: true)
      .limit(300)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String text,
  }) {
    final body = text.trim();
    if (body.isEmpty) return Future.value();
    final chatId = chatIdFor(senderId, receiverId);
    final chatRef = _chats.doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final now = Timestamp.now();
    final batch = _db.batch();
    batch.set(
      chatRef,
      {
        'participants': [senderId, receiverId]..sort(),
        'lastMessage': body.length > 200 ? '${body.substring(0, 200)}…' : body,
        'lastSenderId': senderId,
        'lastMessageAt': now,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(msgRef, {
      'senderId': senderId,
      'receiverId': receiverId,
      'text': body,
      'status': 'sent',
      'clientCreatedAt': now,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Not awaited by the UI: works offline and syncs when back online.
    return batch.commit();
  }

  /// Marks every message addressed to [uid] in [chatIds] that is still
  /// "sent" as "delivered".
  Future<void> markDeliveredInChats(String uid, Iterable<String> chatIds) async {
    for (final chatId in chatIds) {
      try {
        final s = await _chats
            .doc(chatId)
            .collection('messages')
            .where('receiverId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .limit(200)
            .get();
        if (s.docs.isEmpty) continue;
        final batch = _db.batch();
        for (final d in s.docs) {
          batch.update(d.reference, {
            'status': 'delivered',
            'deliveredAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      } on FirebaseException {
        // Try again on the next change.
      }
    }
  }

  Future<void> markRead(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final batch = _db.batch();
    for (final m in messages) {
      final update = <String, dynamic>{
        'status': 'read',
        'readAt': FieldValue.serverTimestamp(),
      };
      if (m.status == MessageStatus.sent) {
        update['deliveredAt'] = FieldValue.serverTimestamp();
      }
      batch.update(m.ref, update);
    }
    try {
      await batch.commit();
    } on FirebaseException {
      // Retried on the next snapshot.
    }
  }
}
