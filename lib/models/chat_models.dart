import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageStatus { pending, sent, delivered, read }

class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime createdAt;
  final MessageStatus status;
  final DocumentReference<Map<String, dynamic>> ref;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
    required this.status,
    required this.ref,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final client = d['clientCreatedAt'];
    final server = d['createdAt'];
    final DateTime created = server is Timestamp
        ? server.toDate()
        : (client is Timestamp ? client.toDate() : DateTime.now());
    MessageStatus status;
    if (doc.metadata.hasPendingWrites && d['status'] == 'sent') {
      status = MessageStatus.pending;
    } else {
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
    }
    return ChatMessage(
      id: doc.id,
      senderId: (d['senderId'] as String?) ?? '',
      receiverId: (d['receiverId'] as String?) ?? '',
      text: (d['text'] as String?) ?? '',
      createdAt: created,
      status: status,
      ref: doc.reference,
    );
  }
}

class ChatSummary {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final String lastSenderId;
  final DateTime? updatedAt;

  const ChatSummary({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastSenderId,
    this.updatedAt,
  });

  String otherParticipant(String me) =>
      participants.firstWhere((p) => p != me, orElse: () => me);

  factory ChatSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final at = d['lastMessageAt'];
    return ChatSummary(
      id: doc.id,
      participants: List<String>.from((d['participants'] as List?) ?? const []),
      lastMessage: (d['lastMessage'] as String?) ?? '',
      lastSenderId: (d['lastSenderId'] as String?) ?? '',
      updatedAt: at is Timestamp ? at.toDate() : null,
    );
  }
}
