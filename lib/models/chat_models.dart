import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

/// A direct (one-to-one) or group conversation: chats/{chatId}.
class Chat {
  final String id;
  final bool isGroup;
  final List<String> members;
  final List<String> admins;
  final String name;
  final String description;
  final String? photoBase64;
  final String? createdBy;
  final String lastMessage;
  final String lastMessageType;
  final String lastSenderId;
  final DateTime? lastMessageAt;
  final Map<String, DateTime> typing;
  final Map<String, int> unread;
  final bool onlyAdminsCanSend;
  final bool onlyAdminsEditInfo;

  const Chat({
    required this.id,
    required this.isGroup,
    required this.members,
    this.admins = const [],
    this.name = '',
    this.description = '',
    this.photoBase64,
    this.createdBy,
    this.lastMessage = '',
    this.lastMessageType = 'text',
    this.lastSenderId = '',
    this.lastMessageAt,
    this.typing = const {},
    this.unread = const {},
    this.onlyAdminsCanSend = false,
    this.onlyAdminsEditInfo = false,
  });

  /// A direct chat that may not exist in Firestore yet.
  factory Chat.direct(String me, String other) {
    final ids = [me, other]..sort();
    return Chat(id: ids.join('_'), isGroup: false, members: ids);
  }

  factory Chat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final typingRaw = (d['typing'] as Map?) ?? const {};
    final unreadRaw = (d['unread'] as Map?) ?? const {};
    final photo = d['photoBase64'];
    return Chat(
      id: doc.id,
      isGroup: d['type'] == 'group',
      members: List<String>.from((d['members'] as List?) ?? const []),
      admins: List<String>.from((d['admins'] as List?) ?? const []),
      name: (d['name'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      photoBase64: photo is String && photo.isNotEmpty ? photo : null,
      createdBy: d['createdBy'] as String?,
      lastMessage: (d['lastMessage'] as String?) ?? '',
      lastMessageType: (d['lastMessageType'] as String?) ?? 'text',
      lastSenderId: (d['lastSenderId'] as String?) ?? '',
      lastMessageAt: _ts(d['lastMessageAt']),
      typing: {
        for (final e in typingRaw.entries)
          if (e.value is Timestamp) '${e.key}': (e.value as Timestamp).toDate(),
      },
      unread: {
        for (final e in unreadRaw.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      onlyAdminsCanSend: d['onlyAdminsCanSend'] == true,
      onlyAdminsEditInfo: d['onlyAdminsEditInfo'] == true,
    );
  }

  String otherMember(String me) =>
      members.firstWhere((m) => m != me, orElse: () => me);

  bool isAdmin(String uid) => admins.contains(uid);

  int unreadFor(String uid) => unread[uid] ?? 0;

  bool canSend(String uid) => !isGroup || !onlyAdminsCanSend || isAdmin(uid);

  bool canEditInfo(String uid) =>
      isGroup && (!onlyAdminsEditInfo || isAdmin(uid));

  /// Members (other than [me]) who typed within the last 6 seconds.
  List<String> typingUsers(String me) {
    final now = DateTime.now();
    return typing.entries
        .where(
            (e) => e.key != me && now.difference(e.value).inSeconds.abs() < 6)
        .map((e) => e.key)
        .toList();
  }
}

enum MessageType { text, image, video, audio, file, system }

MessageType messageTypeFrom(String? s) => MessageType.values
    .firstWhere((t) => t.name == s, orElse: () => MessageType.text);

enum MessageStatus { pending, sent, delivered, read, failed }

/// File attached to a message. Either stored inline in Firestore
/// ([blobId], free plan) or in Cloud Storage ([storagePath], Blaze plan).
class Attachment {
  final String? blobId;
  final String? storagePath;
  final String name;
  final String mime;
  final int size;
  final int? durationMs;
  final int? width;
  final int? height;

  const Attachment({
    this.blobId,
    this.storagePath,
    required this.name,
    required this.mime,
    required this.size,
    this.durationMs,
    this.width,
    this.height,
  });

  bool get isInline => blobId != null;

  factory Attachment.fromMap(Map<String, dynamic> m) => Attachment(
        blobId: m['blobId'] as String?,
        storagePath: m['storagePath'] as String?,
        name: (m['name'] as String?) ?? 'file',
        mime: (m['mime'] as String?) ?? 'application/octet-stream',
        size: (m['size'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt(),
        width: (m['width'] as num?)?.toInt(),
        height: (m['height'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        if (blobId != null) 'blobId': blobId,
        if (storagePath != null) 'storagePath': storagePath,
        'name': name,
        'mime': mime,
        'size': size,
        if (durationMs != null) 'durationMs': durationMs,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

class ReplyInfo {
  final String messageId;
  final String senderId;
  final String text;
  final MessageType type;

  const ReplyInfo({
    required this.messageId,
    required this.senderId,
    required this.text,
    required this.type,
  });

  factory ReplyInfo.fromMap(Map<String, dynamic> m) => ReplyInfo(
        messageId: (m['messageId'] as String?) ?? '',
        senderId: (m['senderId'] as String?) ?? '',
        text: (m['text'] as String?) ?? '',
        type: messageTypeFrom(m['type'] as String?),
      );

  Map<String, dynamic> toMap() => {
        'messageId': messageId,
        'senderId': senderId,
        'text': text.length > 140 ? '${text.substring(0, 140)}…' : text,
        'type': type.name,
      };
}

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String? receiverId;
  final MessageType type;
  final String text;
  final Attachment? attachment;
  final ReplyInfo? replyTo;
  final bool forwarded;
  final bool edited;
  final bool deleted;
  final MessageStatus status;
  final List<String> readBy;
  final List<String> hiddenFor;
  final DateTime createdAt;
  final bool fromServer;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.receiverId,
    required this.type,
    this.text = '',
    this.attachment,
    this.replyTo,
    this.forwarded = false,
    this.edited = false,
    this.deleted = false,
    this.status = MessageStatus.sent,
    this.readBy = const [],
    this.hiddenFor = const [],
    required this.createdAt,
    this.fromServer = true,
  });

  bool get isSystem => type == MessageType.system;

  /// Short text used in chat lists, notifications and reply previews.
  String get previewText => text;

  factory ChatMessage.fromDoc(
      String chatId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final created =
        _ts(d['createdAt']) ?? _ts(d['clientCreatedAt']) ?? DateTime.now();
    final pending = doc.metadata.hasPendingWrites;
    MessageStatus status;
    switch (d['status']) {
      case 'read':
        status = MessageStatus.read;
        break;
      case 'delivered':
        status = MessageStatus.delivered;
        break;
      default:
        status = MessageStatus.sent;
    }
    if (pending && status == MessageStatus.sent) status = MessageStatus.pending;
    final att = d['attachment'];
    final reply = d['replyTo'];
    return ChatMessage(
      id: doc.id,
      chatId: chatId,
      senderId: (d['senderId'] as String?) ?? '',
      receiverId: d['receiverId'] as String?,
      type: messageTypeFrom(d['type'] as String?),
      text: (d['text'] as String?) ?? '',
      attachment:
          att is Map ? Attachment.fromMap(att.cast<String, dynamic>()) : null,
      replyTo: reply is Map
          ? ReplyInfo.fromMap(reply.cast<String, dynamic>())
          : null,
      forwarded: d['forwarded'] == true,
      edited: d['edited'] == true,
      deleted: d['deleted'] == true,
      status: status,
      readBy: List<String>.from((d['readBy'] as List?) ?? const []),
      hiddenFor: List<String>.from((d['hiddenFor'] as List?) ?? const []),
      createdAt: created,
      fromServer: !doc.metadata.isFromCache,
    );
  }

  /// Status shown to the sender in a group: read when every other member
  /// has read it.
  MessageStatus groupStatus(int memberCount) {
    if (status == MessageStatus.pending) return MessageStatus.pending;
    final others = memberCount - 1;
    if (others > 0 && readBy.length >= others) return MessageStatus.read;
    return MessageStatus.sent;
  }
}

/// A message being prepared locally (uploading or failed to send).
class OutgoingMessage {
  final String id;
  final String chatId;
  final MessageType type;
  final String text;
  final String label;
  final double? progress;
  final bool failed;
  final String? error;
  final DateTime createdAt;
  final Future<void> Function() retry;

  const OutgoingMessage({
    required this.id,
    required this.chatId,
    required this.type,
    required this.text,
    required this.label,
    required this.createdAt,
    required this.retry,
    this.progress,
    this.failed = false,
    this.error,
  });

  OutgoingMessage copyWith({double? progress, bool? failed, String? error}) =>
      OutgoingMessage(
        id: id,
        chatId: chatId,
        type: type,
        text: text,
        label: label,
        createdAt: createdAt,
        retry: retry,
        progress: progress ?? this.progress,
        failed: failed ?? this.failed,
        error: error ?? this.error,
      );
}
