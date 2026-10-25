import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_models.dart';

/// One-to-one and group messaging on Firestore.
///
/// chats/{chatId}                  type, members, admins, name, last message,
///                                 typing {uid: time}, unread {uid: count}
/// chats/{chatId}/messages/{id}    one document per message (client-generated
///                                 id, so retries never create duplicates)
/// chats/{chatId}/blobs/{id}       inline attachment bytes (free plan)
///
/// Direct chat ids are the two user ids sorted and joined with "_".
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const _uuid = Uuid();
  static String newId() => _uuid.v4().replaceAll('-', '');

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('chats');
  CollectionReference<Map<String, dynamic>> messagesOf(String chatId) =>
      _chats.doc(chatId).collection('messages');

  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  static bool isDirectId(String chatId) => chatId.split('_').length == 2;

  /// Chats currently open on screen (no notifications for these).
  final Set<String> openChats = {};

  /// Messages being uploaded or that failed, per chat.
  final ValueNotifier<Map<String, List<OutgoingMessage>>> outbox = ValueNotifier({});

  // ---------- reading ----------

  Stream<List<Chat>> watchChats(String uid) => _chats
      .where('members', arrayContains: uid)
      .snapshots()
      .map((s) {
        final list = s.docs.map(Chat.fromDoc).toList();
        list.sort((a, b) => (b.lastMessageAt ?? DateTime(2100)).compareTo(a.lastMessageAt ?? DateTime(2100)));
        return list;
      });

  Stream<Chat?> watchChat(String chatId) =>
      _chats.doc(chatId).snapshots().map((d) => d.exists ? Chat.fromDoc(d) : null);

  Future<Chat?> getChat(String chatId) async {
    final d = await _chats.doc(chatId).get();
    return d.exists ? Chat.fromDoc(d) : null;
  }

  /// Newest [limit] messages, newest first. Raise the limit to page back.
  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit = 40}) => messagesOf(chatId)
      .orderBy('clientCreatedAt', descending: true)
      .limit(limit)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map((d) => ChatMessage.fromDoc(chatId, d)).toList());

  /// Searches the latest 500 messages of a conversation.
  Future<List<ChatMessage>> search(String chatId, String query, String me) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final s = await messagesOf(chatId).orderBy('clientCreatedAt', descending: true).limit(500).get();
    return s.docs
        .map((d) => ChatMessage.fromDoc(chatId, d))
        .where((m) => !m.deleted && !m.hiddenFor.contains(me))
        .where((m) => m.text.toLowerCase().contains(q) ||
            (m.attachment?.name.toLowerCase().contains(q) ?? false))
        .toList();
  }

  // ---------- sending ----------

  static String summaryFor(MessageType type, String text) {
    switch (type) {
      case MessageType.image:
        return text.isEmpty ? '📷' : '📷 $text';
      case MessageType.video:
        return text.isEmpty ? '🎬' : '🎬 $text';
      case MessageType.audio:
        return '🎤';
      case MessageType.file:
        return text.isEmpty ? '📄' : '📄 $text';
      default:
        return text.length > 200 ? '${text.substring(0, 200)}…' : text;
    }
  }

  /// Writes a message and the chat summary in one batch.
  ///
  /// [extra] lets callers add more writes to the same batch (for example an
  /// inline attachment blob).
  Future<void> send({
    required Chat chat,
    required String senderId,
    required String id,
    required MessageType type,
    String text = '',
    Attachment? attachment,
    ReplyInfo? replyTo,
    bool forwarded = false,
    void Function(WriteBatch batch)? extra,
  }) {
    final now = Timestamp.now();
    final chatRef = _chats.doc(chat.id);
    final batch = _db.batch();
    extra?.call(batch);

    final others = chat.members.where((m) => m != senderId).toList();
    final summary = <String, dynamic>{
      'lastMessage': summaryFor(type, text),
      'lastMessageType': type.name,
      'lastSenderId': senderId,
      'lastMessageAt': now,
      'lastMessageId': id,
      'updatedAt': FieldValue.serverTimestamp(),
      'unread': {
        for (final o in others) o: FieldValue.increment(1),
        senderId: 0,
      },
      'typing': {senderId: FieldValue.delete()},
    };
    if (!chat.isGroup) {
      summary['type'] = 'direct';
      summary['members'] = chat.members;
    }
    batch.set(chatRef, summary, SetOptions(merge: true));

    final message = <String, dynamic>{
      'senderId': senderId,
      'type': type.name,
      'text': text,
      'clientCreatedAt': now,
      'createdAt': FieldValue.serverTimestamp(),
      if (attachment != null) 'attachment': attachment.toMap(),
      if (replyTo != null) 'replyTo': replyTo.toMap(),
      if (forwarded) 'forwarded': true,
    };
    if (chat.isGroup) {
      message['readBy'] = <String>[];
    } else {
      message['receiverId'] = chat.otherMember(senderId);
      message['status'] = 'sent';
    }
    batch.set(messagesOf(chat.id).doc(id), message);
    return batch.commit();
  }

  /// Sends a text message, tracking failures so the user can retry.
  Future<void> sendText({
    required Chat chat,
    required String senderId,
    required String text,
    ReplyInfo? replyTo,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final id = newId();
    Future<void> attempt() => send(
          chat: chat,
          senderId: senderId,
          id: id,
          type: MessageType.text,
          text: body,
          replyTo: replyTo,
        );
    await track(
      chat.id,
      OutgoingMessage(
        id: id,
        chatId: chat.id,
        type: MessageType.text,
        text: body,
        label: body,
        createdAt: DateTime.now(),
        retry: () => resend(chat.id, id, attempt),
      ),
      attempt,
      showWhilePending: false,
    );
  }

  /// Runs [attempt] and records a failed outgoing message if it throws.
  Future<void> track(
    String chatId,
    OutgoingMessage item,
    Future<void> Function() attempt, {
    bool showWhilePending = true,
  }) async {
    if (showWhilePending) _putOutbox(item);
    try {
      await attempt();
      _removeOutbox(chatId, item.id);
    } catch (e) {
      _putOutbox(item.copyWith(failed: true, error: '$e', progress: null));
    }
  }

  /// Retries a failed message. If the first attempt actually reached the
  /// server, nothing is sent again.
  Future<void> resend(String chatId, String id, Future<void> Function() attempt) async {
    final existing = outbox.value[chatId]?.where((o) => o.id == id).toList() ?? const [];
    try {
      final doc = await messagesOf(chatId).doc(id).get();
      if (doc.exists) {
        _removeOutbox(chatId, id);
        return;
      }
    } catch (_) {}
    if (existing.isNotEmpty) _putOutbox(existing.first.copyWith(failed: false));
    try {
      await attempt();
      _removeOutbox(chatId, id);
    } catch (e) {
      if (existing.isNotEmpty) _putOutbox(existing.first.copyWith(failed: true, error: '$e'));
    }
  }

  void updateProgress(String chatId, String id, double progress) {
    final list = outbox.value[chatId];
    if (list == null) return;
    final i = list.indexWhere((o) => o.id == id);
    if (i < 0) return;
    _putOutbox(list[i].copyWith(progress: progress));
  }

  void discardOutgoing(String chatId, String id) => _removeOutbox(chatId, id);

  void _putOutbox(OutgoingMessage item) {
    final map = Map<String, List<OutgoingMessage>>.from(outbox.value);
    final list = List<OutgoingMessage>.from(map[item.chatId] ?? const []);
    final i = list.indexWhere((o) => o.id == item.id);
    if (i >= 0) {
      list[i] = item;
    } else {
      list.add(item);
    }
    map[item.chatId] = list;
    outbox.value = map;
  }

  void _removeOutbox(String chatId, String id) {
    final list = outbox.value[chatId];
    if (list == null || !list.any((o) => o.id == id)) return;
    final map = Map<String, List<OutgoingMessage>>.from(outbox.value);
    map[chatId] = list.where((o) => o.id != id).toList();
    outbox.value = map;
  }

  // ---------- status ----------

  /// Confirms delivery of direct messages addressed to [uid] in [chatIds].
  Future<void> markDelivered(String uid, Iterable<String> chatIds) async {
    for (final chatId in chatIds) {
      if (!isDirectId(chatId)) continue;
      try {
        final s = await messagesOf(chatId)
            .where('receiverId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .limit(200)
            .get();
        if (s.docs.isEmpty) continue;
        final batch = _db.batch();
        for (final d in s.docs) {
          batch.update(d.reference, {'status': 'delivered', 'deliveredAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
      } on FirebaseException {
        // Retried on the next change.
      }
    }
  }

  /// Marks messages as read by [me] and clears the unread counter.
  /// With read receipts turned off, direct messages are only marked
  /// delivered.
  Future<void> markRead(Chat chat, String me, List<ChatMessage> messages, {required bool readReceipts}) async {
    final batch = _db.batch();
    var writes = 0;
    for (final m in messages) {
      if (m.senderId == me || m.isSystem || writes > 400) continue;
      if (chat.isGroup) {
        if (!readReceipts || m.readBy.contains(me)) continue;
        batch.update(messagesOf(chat.id).doc(m.id), {
          'readBy': FieldValue.arrayUnion([me]),
        });
        writes++;
      } else if (m.receiverId == me) {
        if (readReceipts && m.status != MessageStatus.read) {
          batch.update(messagesOf(chat.id).doc(m.id), {
            'status': 'read',
            'readAt': FieldValue.serverTimestamp(),
            if (m.status == MessageStatus.sent || m.status == MessageStatus.pending)
              'deliveredAt': FieldValue.serverTimestamp(),
          });
          writes++;
        } else if (!readReceipts && (m.status == MessageStatus.sent || m.status == MessageStatus.pending)) {
          batch.update(messagesOf(chat.id).doc(m.id), {
            'status': 'delivered',
            'deliveredAt': FieldValue.serverTimestamp(),
          });
          writes++;
        }
      }
    }
    if (chat.unreadFor(me) > 0) {
      batch.set(_chats.doc(chat.id), {
        'unread': {me: 0},
      }, SetOptions(merge: true));
      writes++;
    }
    if (writes == 0) return;
    try {
      await batch.commit();
    } on FirebaseException {
      // Retried on the next snapshot.
    }
  }

  // ---------- editing ----------

  Future<void> edit(ChatMessage m, String newText) => messagesOf(m.chatId).doc(m.id).update({
        'text': newText.trim(),
        'edited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteForEveryone(ChatMessage m) async {
    await messagesOf(m.chatId).doc(m.id).update({
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'text': '',
      'attachment': FieldValue.delete(),
      'replyTo': FieldValue.delete(),
    });
    final blobId = m.attachment?.blobId;
    if (blobId != null) {
      try {
        await _chats.doc(m.chatId).collection('blobs').doc(blobId).delete();
      } catch (_) {}
    }
  }

  Future<void> hideForMe(ChatMessage m, String me) => messagesOf(m.chatId).doc(m.id).update({
        'hiddenFor': FieldValue.arrayUnion([me]),
      });

  static bool canEdit(ChatMessage m, String me) =>
      m.senderId == me &&
      m.type == MessageType.text &&
      !m.deleted &&
      DateTime.now().difference(m.createdAt).inHours < 47;

  // ---------- typing ----------

  final Map<String, DateTime> _lastTyping = {};

  /// Throttled to one write every 3 seconds per chat.
  Future<void> setTyping(String chatId, String me, bool typing) async {
    final last = _lastTyping[chatId];
    final now = DateTime.now();
    if (typing && last != null && now.difference(last).inSeconds < 3) return;
    if (!typing && last == null) return;
    _lastTyping[chatId] = typing ? now : DateTime.fromMillisecondsSinceEpoch(0);
    if (!typing) _lastTyping.remove(chatId);
    try {
      await _chats.doc(chatId).update({
        'typing.$me': typing ? FieldValue.serverTimestamp() : FieldValue.delete(),
      });
    } on FirebaseException {
      // The chat may not exist yet; typing is best-effort.
    }
  }

  // ---------- groups ----------

  Future<String> createGroup({
    required String creator,
    required String name,
    required List<String> memberIds,
    String? photoBase64,
    String description = '',
  }) async {
    final ref = _chats.doc();
    final members = {creator, ...memberIds}.toList();
    final now = Timestamp.now();
    final batch = _db.batch();
    batch.set(ref, {
      'type': 'group',
      'name': name.trim(),
      'description': description.trim(),
      if (photoBase64 != null) 'photoBase64': photoBase64,
      'createdBy': creator,
      'members': members,
      'admins': [creator],
      'onlyAdminsCanSend': false,
      'onlyAdminsEditInfo': false,
      'lastMessage': '',
      'lastMessageType': 'system',
      'lastSenderId': creator,
      'lastMessageAt': now,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('messages').doc(newId()), _system(creator, 'created', now: now));
    await batch.commit();
    return ref.id;
  }

  Map<String, dynamic> _system(String actor, String event, {List<String> targets = const [], Timestamp? now}) => {
        'senderId': actor,
        'type': 'system',
        // Machine-readable event; the app shows it in the reader's language.
        'text': [event, ...targets].join(':'),
        'readBy': <String>[],
        'clientCreatedAt': now ?? Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
      };

  Future<void> _groupUpdate(String chatId, String actor, Map<String, dynamic> update,
      {String? event, List<String> targets = const []}) {
    final batch = _db.batch();
    batch.update(_chats.doc(chatId), {...update, 'updatedAt': FieldValue.serverTimestamp()});
    if (event != null) {
      batch.set(messagesOf(chatId).doc(newId()), _system(actor, event, targets: targets));
    }
    return batch.commit();
  }

  Future<void> addMembers(Chat chat, String admin, List<String> uids) => _groupUpdate(
        chat.id,
        admin,
        {'members': FieldValue.arrayUnion(uids)},
        event: 'added',
        targets: uids,
      );

  Future<void> removeMember(Chat chat, String admin, String uid) => _groupUpdate(
        chat.id,
        admin,
        {
          'members': FieldValue.arrayRemove([uid]),
          'admins': FieldValue.arrayRemove([uid]),
        },
        event: 'removed',
        targets: [uid],
      );

  Future<void> setAdmin(Chat chat, String admin, String uid, bool makeAdmin) => _groupUpdate(
        chat.id,
        admin,
        {'admins': makeAdmin ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid])},
        event: makeAdmin ? 'admin_added' : 'admin_removed',
        targets: [uid],
      );

  Future<void> updateGroupInfo(Chat chat, String actor,
      {String? name, String? description, String? photoBase64, bool removePhoto = false}) {
    final update = <String, dynamic>{};
    if (name != null) update['name'] = name.trim();
    if (description != null) update['description'] = description.trim();
    if (photoBase64 != null) update['photoBase64'] = photoBase64;
    if (removePhoto) update['photoBase64'] = FieldValue.delete();
    return _groupUpdate(chat.id, actor, update, event: name != null && name.trim() != chat.name ? 'renamed' : null,
        targets: name != null ? [name.trim()] : const []);
  }

  Future<void> setGroupPermissions(Chat chat, String admin, {bool? onlyAdminsCanSend, bool? onlyAdminsEditInfo}) =>
      _groupUpdate(chat.id, admin, {
        if (onlyAdminsCanSend != null) 'onlyAdminsCanSend': onlyAdminsCanSend,
        if (onlyAdminsEditInfo != null) 'onlyAdminsEditInfo': onlyAdminsEditInfo,
      });

  /// Leaves a group. If the last admin leaves, the longest-standing member
  /// becomes admin so the group is never left without one.
  Future<void> leaveGroup(Chat chat, String me) async {
    final remaining = chat.members.where((m) => m != me).toList();
    final remainingAdmins = chat.admins.where((a) => a != me).toList();
    // The system message is written first, while still a member.
    await messagesOf(chat.id).doc(newId()).set(_system(me, 'left'));
    if (remainingAdmins.isEmpty && remaining.isNotEmpty && chat.isAdmin(me)) {
      await _chats.doc(chat.id).update({
        'admins': [remaining.first],
        'members': remaining,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _chats.doc(chat.id).update({
        'members': FieldValue.arrayRemove([me]),
        'admins': FieldValue.arrayRemove([me]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Deletes a group with all its messages (admins only).
  Future<void> deleteGroup(Chat chat) async {
    for (final sub in ['messages', 'blobs']) {
      while (true) {
        final page = await _chats.doc(chat.id).collection(sub).limit(300).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }
    await _chats.doc(chat.id).delete();
  }
}
