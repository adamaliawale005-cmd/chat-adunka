import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../config/app_config.dart';
import '../models/chat_models.dart';
import 'chat_service.dart';

class AttachmentTooLargeException implements Exception {
  final int size;
  final int limit;
  const AttachmentTooLargeException(this.size, this.limit);
}

class StorageNotEnabledException implements Exception {
  const StorageNotEnabledException();
}

/// Sends and loads message attachments.
///
/// * Free plan (STORAGE_ENABLED=false): photos and voice notes up to about
///   690 KB are stored inline in chats/{chatId}/blobs/{id}. Videos and
///   documents are not available.
/// * Blaze plan (STORAGE_ENABLED=true): files up to 50 MB go to Cloud Storage
///   under chats/{chatId}/{senderUid}/, readable only by chat members. Files
///   are downloaded through the Storage SDK, so the security rules are
///   checked on every access; no public links are stored in messages.
class AttachmentService {
  AttachmentService._();
  static final AttachmentService instance = AttachmentService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  bool get storageEnabled => AppConfig.storageEnabled;

  /// Whether a file of this type and size can be sent with the current plan.
  bool canSend(MessageType type, int size) {
    if (storageEnabled) return size <= AppConfig.storageAttachmentLimit;
    if (type == MessageType.image || type == MessageType.audio) {
      return size <= AppConfig.inlineAttachmentLimit;
    }
    return false;
  }

  Future<void> sendFile({
    required Chat chat,
    required String senderId,
    required MessageType type,
    required File file,
    required String name,
    required String mime,
    String caption = '',
    int? durationMs,
    int? width,
    int? height,
    ReplyInfo? replyTo,
  }) async {
    final size = await file.length();
    final chats = ChatService.instance;
    final id = ChatService.newId();
    final label = caption.isNotEmpty ? caption : name;

    Future<void> attempt() async {
      final bytes = await file.readAsBytes();
      await _sendBytes(
        chat: chat,
        senderId: senderId,
        id: id,
        type: type,
        bytes: bytes,
        name: name,
        mime: mime,
        caption: caption,
        durationMs: durationMs,
        width: width,
        height: height,
        replyTo: replyTo,
      );
    }

    if (!storageEnabled &&
        type != MessageType.image &&
        type != MessageType.audio) {
      throw const StorageNotEnabledException();
    }
    final limit = storageEnabled
        ? AppConfig.storageAttachmentLimit
        : AppConfig.inlineAttachmentLimit;
    if (size > limit) throw AttachmentTooLargeException(size, limit);

    await chats.track(
      chat.id,
      OutgoingMessage(
        id: id,
        chatId: chat.id,
        type: type,
        text: caption,
        label: label,
        createdAt: DateTime.now(),
        progress: 0,
        retry: () => chats.resend(chat.id, id, attempt),
      ),
      attempt,
    );
  }

  Future<void> _sendBytes({
    required Chat chat,
    required String senderId,
    required String id,
    required MessageType type,
    required Uint8List bytes,
    required String name,
    required String mime,
    String caption = '',
    int? durationMs,
    int? width,
    int? height,
    ReplyInfo? replyTo,
    bool forwarded = false,
  }) async {
    final chats = ChatService.instance;
    if (storageEnabled) {
      final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = 'chats/${chat.id}/$senderId/${id}_$safeName';
      final task = FirebaseStorage.instance
          .ref(path)
          .putData(bytes, SettableMetadata(contentType: mime));
      final sub = task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0)
          chats.updateProgress(chat.id, id, s.bytesTransferred / s.totalBytes);
      });
      try {
        await task;
      } finally {
        await sub.cancel();
      }
      await chats.send(
        chat: chat,
        senderId: senderId,
        id: id,
        type: type,
        text: caption,
        replyTo: replyTo,
        forwarded: forwarded,
        attachment: Attachment(
          storagePath: path,
          name: name,
          mime: mime,
          size: bytes.length,
          durationMs: durationMs,
          width: width,
          height: height,
        ),
      );
    } else {
      final blobRef =
          _db.collection('chats').doc(chat.id).collection('blobs').doc(id);
      await chats.send(
        chat: chat,
        senderId: senderId,
        id: id,
        type: type,
        text: caption,
        replyTo: replyTo,
        forwarded: forwarded,
        attachment: Attachment(
          blobId: id,
          name: name,
          mime: mime,
          size: bytes.length,
          durationMs: durationMs,
          width: width,
          height: height,
        ),
        extra: (batch) => batch.set(blobRef, {
          'senderId': senderId,
          'data': base64Encode(bytes),
          'mime': mime,
          'size': bytes.length,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );
    }
  }

  // ---------- loading ----------

  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  int _cacheBytes = 0;

  /// Loads attachment bytes (members only; enforced by the security rules).
  Future<Uint8List?> load(String chatId, Attachment a) {
    final key =
        a.blobId != null ? 'b:$chatId/${a.blobId}' : 's:${a.storagePath}';
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    return _inflight.putIfAbsent(key, () async {
      try {
        Uint8List? bytes;
        if (a.blobId != null) {
          final doc = await _db
              .collection('chats')
              .doc(chatId)
              .collection('blobs')
              .doc(a.blobId)
              .get();
          final data = doc.data()?['data'];
          if (data is String) bytes = base64Decode(data);
        } else if (a.storagePath != null) {
          bytes = await FirebaseStorage.instance
              .ref(a.storagePath)
              .getData(AppConfig.storageAttachmentLimit);
        }
        if (bytes != null) _remember(key, bytes);
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  void _remember(String key, Uint8List bytes) {
    if (bytes.length > 8 * 1024 * 1024) return;
    _cache[key] = bytes;
    _cacheBytes += bytes.length;
    while (_cacheBytes > 60 * 1024 * 1024 && _cache.isNotEmpty) {
      final first = _cache.keys.first;
      _cacheBytes -= _cache.remove(first)!.length;
    }
  }

  /// Writes the attachment to a temporary file (for playback or opening).
  Future<File?> toTempFile(String chatId, Attachment a, String dir) async {
    final bytes = await load(chatId, a);
    if (bytes == null) return null;
    final safe = a.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final f = File('$dir/${a.blobId ?? a.storagePath.hashCode}_$safe');
    if (!await f.exists() || await f.length() != bytes.length) {
      await f.writeAsBytes(bytes, flush: true);
    }
    return f;
  }

  /// Short-lived download link for streaming a video. Only members can get
  /// it, because creating the link is checked by the Storage rules.
  Future<String?> streamUrl(Attachment a) async {
    if (a.storagePath == null) return null;
    try {
      return await FirebaseStorage.instance.ref(a.storagePath).getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  // ---------- forwarding ----------

  /// Forwards a message to another chat. Attachment bytes are copied into
  /// the target chat, because files are only readable by members of the
  /// chat they were sent in.
  Future<void> forward(ChatMessage m, Chat target, String senderId) async {
    final chats = ChatService.instance;
    final id = ChatService.newId();
    final a = m.attachment;
    if (a == null) {
      await chats.send(
        chat: target,
        senderId: senderId,
        id: id,
        type: m.type,
        text: m.text,
        forwarded: true,
      );
      return;
    }
    final bytes = await load(m.chatId, a);
    if (bytes == null) throw Exception('attachment unavailable');
    await _sendBytes(
      chat: target,
      senderId: senderId,
      id: id,
      type: m.type,
      bytes: bytes,
      name: a.name,
      mime: a.mime,
      caption: m.text,
      durationMs: a.durationMs,
      width: a.width,
      height: a.height,
      forwarded: true,
    );
  }
}
