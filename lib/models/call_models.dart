import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

enum CallKind { audio, video }

/// Entry in users/{uid}/calls — the user's own call history.
class CallLogEntry {
  final String callId;
  final String peerId;
  final CallKind kind;
  final bool incoming;
  final String
      status; // ringing, answered, missed, rejected, cancelled, busy, ended
  final DateTime createdAt;
  final int durationSec;
  final bool seen;

  const CallLogEntry({
    required this.callId,
    required this.peerId,
    required this.kind,
    required this.incoming,
    required this.status,
    required this.createdAt,
    this.durationSec = 0,
    this.seen = true,
  });

  bool get isMissed => incoming && (status == 'missed' || status == 'ringing');

  factory CallLogEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CallLogEntry(
      callId: doc.id,
      peerId: (d['peerId'] as String?) ?? '',
      kind: d['type'] == 'video' ? CallKind.video : CallKind.audio,
      incoming: d['direction'] == 'incoming',
      status: (d['status'] as String?) ?? 'ended',
      createdAt: _ts(d['createdAt']) ?? DateTime.now(),
      durationSec: (d['durationSec'] as num?)?.toInt() ?? 0,
      seen: d['seen'] != false,
    );
  }
}

/// calls/{callId} — signaling document shared by both participants.
class CallDoc {
  final String id;
  final String callerId;
  final String calleeId;
  final CallKind kind;
  final String status;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final int offerVersion;
  final int answerVersion;
  final DateTime? createdAt;

  const CallDoc({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.kind,
    required this.status,
    this.offer,
    this.answer,
    this.offerVersion = 0,
    this.answerVersion = 0,
    this.createdAt,
  });

  factory CallDoc.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CallDoc(
      id: doc.id,
      callerId: (d['callerId'] as String?) ?? '',
      calleeId: (d['calleeId'] as String?) ?? '',
      kind: d['type'] == 'video' ? CallKind.video : CallKind.audio,
      status: (d['status'] as String?) ?? 'ended',
      offer: (d['offer'] as Map?)?.cast<String, dynamic>(),
      answer: (d['answer'] as Map?)?.cast<String, dynamic>(),
      offerVersion: (d['offerVersion'] as num?)?.toInt() ?? 0,
      answerVersion: (d['answerVersion'] as num?)?.toInt() ?? 0,
      createdAt: _ts(d['createdAt']),
    );
  }
}
