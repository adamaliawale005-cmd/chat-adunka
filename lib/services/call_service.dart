import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';
import '../models/call_models.dart';

enum CallPhase { outgoing, incoming, connecting, connected, reconnecting, ended }

class CallPermissionDenied implements Exception {
  final bool permanently;
  const CallPermissionDenied({this.permanently = false});
}

class CallBusyException implements Exception {
  const CallBusyException();
}

/// State of the call on screen.
class ActiveCall extends ChangeNotifier {
  final String callId;
  final String me;
  final String peerId;
  final CallKind kind;
  final bool outgoing;

  ActiveCall({
    required this.callId,
    required this.me,
    required this.peerId,
    required this.kind,
    required this.outgoing,
    required CallPhase phase,
  }) : _phase = phase;

  CallPhase _phase;
  CallPhase get phase => _phase;

  bool micMuted = false;
  bool speakerOn = false;
  bool cameraOff = false;
  bool remoteVideo = false;
  DateTime? connectedAt;

  /// Why the call ended: ended, cancelled, rejected, busy, no_answer,
  /// failed, permission.
  String? endReason;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  bool _renderersDisposed = false;

  MediaStream? localStream;
  RTCPeerConnection? pc;

  bool get isVideo => kind == CallKind.video;
  bool get isOver => _phase == CallPhase.ended;

  Duration get duration =>
      connectedAt == null ? Duration.zero : DateTime.now().difference(connectedAt!);

  void setPhase(CallPhase p) {
    if (_phase == CallPhase.ended) return;
    _phase = p;
    if (p == CallPhase.connected) connectedAt ??= DateTime.now();
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<void> initRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> disposeRenderers() async {
    if (!_renderersReady || _renderersDisposed) return;
    _renderersDisposed = true;
    try {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}

/// One-to-one voice and video calls with WebRTC.
///
/// Signaling goes through Firestore: calls/{callId} holds the offer/answer,
/// calls/{callId}/candidates holds ICE candidates. Media flows directly
/// between phones when possible; behind strict networks it needs the TURN
/// relay configured with TURN_URLS / TURN_USERNAME / TURN_CREDENTIAL.
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _calls => _db.collection('calls');
  DocumentReference<Map<String, dynamic>> _history(String uid, String callId) =>
      _db.collection('users').doc(uid).collection('calls').doc(callId);

  final ValueNotifier<ActiveCall?> active = ValueNotifier(null);
  final StreamController<CallDoc> _incoming = StreamController.broadcast();

  /// Ringing calls addressed to this user.
  Stream<CallDoc> get incomingCalls => _incoming.stream;

  /// Called when a ringing call ended without being answered.
  void Function(CallDoc call)? onMissedCall;

  StreamSubscription? _incomingSub;
  StreamSubscription? _docSub;
  StreamSubscription? _candSub;
  Timer? _ringTimer;
  Timer? _reconnectTimer;
  final List<RTCIceCandidate> _pendingRemote = [];
  final List<RTCIceCandidate> _pendingLocal = [];
  bool _signalingReady = false;
  bool _remoteSet = false;
  int _appliedOffer = 0;
  int _appliedAnswer = 0;
  int _restarts = 0;
  final Set<String> _seenIncoming = {};

  Map<String, dynamic> get _rtcConfig => {
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': AppConfig.stunUrls},
          if (AppConfig.turnConfigured)
            {
              'urls': AppConfig.turnUrls,
              'username': AppConfig.turnUsername,
              'credential': AppConfig.turnCredential,
            },
        ],
      };

  // ---------- incoming ----------

  void listenForIncoming(String me) {
    _incomingSub?.cancel();
    _incomingSub = _calls
        .where('calleeId', isEqualTo: me)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((s) {
      for (final change in s.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final call = CallDoc.fromDoc(change.doc);
        if (_seenIncoming.contains(call.id)) continue;
        final created = call.createdAt;
        if (created != null && DateTime.now().difference(created).inSeconds.abs() > 60) continue;
        _seenIncoming.add(call.id);
        if (active.value != null && !active.value!.isOver) {
          _calls.doc(call.id).update({'status': 'busy', 'updatedAt': FieldValue.serverTimestamp()}).catchError((_) {});
          continue;
        }
        _watchUnanswered(call, me);
        _incoming.add(call);
      }
    }, onError: (_) {});
  }

  void stopListening() {
    _incomingSub?.cancel();
    _incomingSub = null;
  }

  /// Reports a missed call if a ringing call ends without being answered.
  void _watchUnanswered(CallDoc call, String me) {
    late StreamSubscription sub;
    sub = _calls.doc(call.id).snapshots().listen((d) {
      final status = d.data()?['status'];
      if (status == 'ringing') return;
      if (status == 'missed' || status == 'cancelled') onMissedCall?.call(call);
      sub.cancel();
    }, onError: (_) => sub.cancel());
  }

  Stream<CallDoc?> watchCall(String callId) =>
      _calls.doc(callId).snapshots().map((d) => d.exists ? CallDoc.fromDoc(d) : null);

  Stream<List<CallLogEntry>> watchHistory(String me) => _db
      .collection('users')
      .doc(me)
      .collection('calls')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(CallLogEntry.fromDoc).toList());

  Future<void> markHistorySeen(String me, List<CallLogEntry> entries) async {
    final unseen = entries.where((e) => !e.seen).toList();
    if (unseen.isEmpty) return;
    final batch = _db.batch();
    for (final e in unseen) {
      batch.update(_history(me, e.callId), {'seen': true});
    }
    try {
      await batch.commit();
    } catch (_) {}
  }

  Future<void> deleteHistoryEntry(String me, String callId) => _history(me, callId).delete();

  // ---------- permissions & media ----------

  Future<void> _ensurePermissions(CallKind kind) async {
    final perms = [Permission.microphone, if (kind == CallKind.video) Permission.camera];
    final result = await perms.request();
    final denied = result.values.where((s) => !s.isGranted).toList();
    if (denied.isNotEmpty) {
      throw CallPermissionDenied(permanently: denied.any((s) => s.isPermanentlyDenied));
    }
  }

  Future<MediaStream> _openMedia(CallKind kind) => navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': kind == CallKind.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 24},
              }
            : false,
      });

  Future<RTCPeerConnection> _createPeer(ActiveCall call) async {
    final pc = await createPeerConnection(_rtcConfig);
    call.pc = pc;
    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      if (_signalingReady) {
        _sendCandidate(call, c);
      } else {
        _pendingLocal.add(c);
      }
    };
    pc.onTrack = (RTCTrackEvent e) {
      if (e.streams.isNotEmpty) {
        call.remoteRenderer.srcObject = e.streams.first;
      }
      if (e.track.kind == 'video') call.remoteVideo = true;
      call.changed();
    };
    pc.onIceConnectionState = (RTCIceConnectionState s) => _onIceState(call, s);
    return pc;
  }

  void _sendCandidate(ActiveCall call, RTCIceCandidate c) {
    _calls.doc(call.callId).collection('candidates').add({
      'from': call.me,
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
      'createdAt': FieldValue.serverTimestamp(),
    }).then((_) {}, onError: (_) {});
  }

  void _flushLocalCandidates(ActiveCall call) {
    _signalingReady = true;
    for (final c in _pendingLocal) {
      _sendCandidate(call, c);
    }
    _pendingLocal.clear();
  }

  void _listenRemoteCandidates(ActiveCall call) {
    _candSub?.cancel();
    _candSub = _calls
        .doc(call.callId)
        .collection('candidates')
        .where('from', isEqualTo: call.peerId)
        .snapshots()
        .listen((s) {
      for (final ch in s.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final d = ch.doc.data();
        if (d == null) continue;
        final c = RTCIceCandidate(
          d['candidate'] as String?,
          d['sdpMid'] as String?,
          (d['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteSet) {
          call.pc?.addCandidate(c).catchError((_) {});
        } else {
          _pendingRemote.add(c);
        }
      }
    }, onError: (_) {});
  }

  Future<void> _setRemote(ActiveCall call, Map<String, dynamic> desc) async {
    await call.pc?.setRemoteDescription(
      RTCSessionDescription(desc['sdp'] as String?, desc['type'] as String?),
    );
    _remoteSet = true;
    for (final c in _pendingRemote) {
      await call.pc?.addCandidate(c).catchError((_) {});
    }
    _pendingRemote.clear();
  }

  void _onIceState(ActiveCall call, RTCIceConnectionState s) {
    switch (s) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _reconnectTimer?.cancel();
        _restarts = 0;
        call.setPhase(CallPhase.connected);
        if (call.outgoing) {
          _history(call.me, call.callId).update({'status': 'answered'}).catchError((_) {});
        }
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        if (call.connectedAt != null) call.setPhase(CallPhase.reconnecting);
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(seconds: 5), () => _restartIce(call));
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        if (call.connectedAt != null) call.setPhase(CallPhase.reconnecting);
        _restartIce(call);
        break;
      default:
        break;
    }
  }

  /// Network changed (Wi-Fi to mobile data, signal loss): the caller
  /// renegotiates with a new ICE session. Gives up after three attempts.
  Future<void> _restartIce(ActiveCall call) async {
    if (call.isOver || !call.outgoing) return;
    if (_restarts >= 3) {
      await hangUp(reason: 'failed');
      return;
    }
    _restarts++;
    try {
      final offer = await call.pc!.createOffer({'iceRestart': true});
      await call.pc!.setLocalDescription(offer);
      _appliedOffer++;
      await _calls.doc(call.callId).update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'offerVersion': _appliedOffer,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Try again on the next state change.
    }
  }

  // ---------- outgoing ----------

  Future<ActiveCall> startCall({required String me, required String peer, required CallKind kind}) async {
    if (active.value != null && !active.value!.isOver) throw const CallBusyException();
    await _ensurePermissions(kind);
    _reset();
    final ref = _calls.doc();
    final call = ActiveCall(
      callId: ref.id,
      me: me,
      peerId: peer,
      kind: kind,
      outgoing: true,
      phase: CallPhase.outgoing,
    );
    call.speakerOn = kind == CallKind.video;
    active.value = call;
    try {
      await call.initRenderers();
      final stream = await _openMedia(kind);
      call.localStream = stream;
      call.localRenderer.srcObject = stream;
      final pc = await _createPeer(call);
      for (final t in stream.getTracks()) {
        await pc.addTrack(t, stream);
      }
      await Helper.setSpeakerphoneOn(call.speakerOn);
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': kind == CallKind.video ? 1 : 0,
      });
      await pc.setLocalDescription(offer);
      _appliedOffer = 1;

      final batch = _db.batch();
      batch.set(ref, {
        'callerId': me,
        'calleeId': peer,
        'members': [me, peer],
        'type': kind.name,
        'status': 'ringing',
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'offerVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(_history(me, ref.id), {
        'callId': ref.id,
        'peerId': peer,
        'type': kind.name,
        'direction': 'outgoing',
        'status': 'ringing',
        'seen': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Recorded as missed until the callee answers.
      batch.set(_history(peer, ref.id), {
        'callId': ref.id,
        'peerId': me,
        'type': kind.name,
        'direction': 'incoming',
        'status': 'missed',
        'seen': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _flushLocalCandidates(call);
      _listenRemoteCandidates(call);
      _docSub = _calls.doc(ref.id).snapshots().listen((d) => _onCallerDoc(call, d), onError: (_) {});
      _ringTimer = Timer(AppConfig.ringTimeout, () {
        if (call.phase == CallPhase.outgoing) hangUp(reason: 'no_answer');
      });
    } catch (e) {
      await _finish(call, 'failed', writeStatus: false);
      rethrow;
    }
    return call;
  }

  Future<void> _onCallerDoc(ActiveCall call, DocumentSnapshot<Map<String, dynamic>> d) async {
    if (!d.exists || call.isOver) return;
    final doc = CallDoc.fromDoc(d);
    if (doc.answer != null && doc.answerVersion > _appliedAnswer) {
      _appliedAnswer = doc.answerVersion;
      _ringTimer?.cancel();
      if (call.phase == CallPhase.outgoing) call.setPhase(CallPhase.connecting);
      try {
        await _setRemote(call, doc.answer!);
      } catch (_) {}
    }
    switch (doc.status) {
      case 'rejected':
        await _finish(call, 'rejected', writeStatus: false);
        break;
      case 'busy':
        await _finish(call, 'busy', writeStatus: false);
        break;
      case 'ended':
        await _finish(call, 'ended', writeStatus: false);
        break;
    }
  }

  // ---------- answering ----------

  Future<ActiveCall> accept(CallDoc incoming, String me) async {
    if (active.value != null && !active.value!.isOver) throw const CallBusyException();
    await _ensurePermissions(incoming.kind);
    _reset();
    final call = ActiveCall(
      callId: incoming.id,
      me: me,
      peerId: incoming.callerId,
      kind: incoming.kind,
      outgoing: false,
      phase: CallPhase.connecting,
    );
    call.speakerOn = incoming.kind == CallKind.video;
    active.value = call;
    try {
      final fresh = CallDoc.fromDoc(await _calls.doc(incoming.id).get());
      if (fresh.status != 'ringing' || fresh.offer == null) {
        await _finish(call, 'cancelled', writeStatus: false);
        return call;
      }
      await call.initRenderers();
      final stream = await _openMedia(incoming.kind);
      call.localStream = stream;
      call.localRenderer.srcObject = stream;
      final pc = await _createPeer(call);
      for (final t in stream.getTracks()) {
        await pc.addTrack(t, stream);
      }
      await Helper.setSpeakerphoneOn(call.speakerOn);
      _signalingReady = true;
      _listenRemoteCandidates(call);
      _appliedOffer = fresh.offerVersion;
      await _setRemote(call, fresh.offer!);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _appliedAnswer = 1;
      await _calls.doc(incoming.id).update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'answerVersion': 1,
        'status': 'accepted',
        'answeredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _flushLocalCandidates(call);
      _history(me, incoming.id).update({
        'status': 'answered',
        'seen': true,
        'answeredAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});
      _docSub = _calls.doc(incoming.id).snapshots().listen((d) => _onCalleeDoc(call, d), onError: (_) {});
    } catch (e) {
      await _finish(call, 'failed');
      rethrow;
    }
    return call;
  }

  Future<void> _onCalleeDoc(ActiveCall call, DocumentSnapshot<Map<String, dynamic>> d) async {
    if (!d.exists || call.isOver) return;
    final doc = CallDoc.fromDoc(d);
    // ICE restart requested by the caller.
    if (doc.offer != null && doc.offerVersion > _appliedOffer) {
      _appliedOffer = doc.offerVersion;
      try {
        await _setRemote(call, doc.offer!);
        final answer = await call.pc!.createAnswer();
        await call.pc!.setLocalDescription(answer);
        _appliedAnswer++;
        await _calls.doc(call.callId).update({
          'answer': {'sdp': answer.sdp, 'type': answer.type},
          'answerVersion': _appliedAnswer,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
    if (doc.status == 'ended' || doc.status == 'cancelled') {
      await _finish(call, 'ended', writeStatus: false);
    }
  }

  Future<void> reject(CallDoc incoming, String me) async {
    try {
      await _calls.doc(incoming.id).update({
        'status': 'rejected',
        'endedAt': FieldValue.serverTimestamp(),
        'endedBy': me,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _history(me, incoming.id).update({'status': 'rejected', 'seen': true});
    } catch (_) {}
  }

  // ---------- controls ----------

  void toggleMute() {
    final call = active.value;
    if (call == null) return;
    call.micMuted = !call.micMuted;
    for (final t in call.localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !call.micMuted;
    }
    call.changed();
  }

  Future<void> toggleSpeaker() async {
    final call = active.value;
    if (call == null) return;
    call.speakerOn = !call.speakerOn;
    await Helper.setSpeakerphoneOn(call.speakerOn);
    call.changed();
  }

  void toggleCamera() {
    final call = active.value;
    if (call == null) return;
    call.cameraOff = !call.cameraOff;
    for (final t in call.localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !call.cameraOff;
    }
    call.changed();
  }

  Future<void> switchCamera() async {
    final tracks = active.value?.localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  // ---------- ending ----------

  Future<void> hangUp({String reason = 'ended'}) async {
    final call = active.value;
    if (call == null || call.isOver) return;
    final notAnswered = call.outgoing && call.connectedAt == null && _appliedAnswer == 0;
    final status = notAnswered ? (reason == 'no_answer' ? 'missed' : 'cancelled') : 'ended';
    await _finish(call, notAnswered ? (reason == 'no_answer' ? 'no_answer' : 'cancelled') : reason,
        callStatus: status);
  }

  Future<void> _finish(ActiveCall call, String reason, {bool writeStatus = true, String callStatus = 'ended'}) async {
    if (call.isOver) return;
    call.endReason = reason;
    final seconds = call.duration.inSeconds;
    call.setPhase(CallPhase.ended);
    _ringTimer?.cancel();
    _reconnectTimer?.cancel();
    await _docSub?.cancel();
    await _candSub?.cancel();
    _docSub = null;
    _candSub = null;
    if (writeStatus) {
      try {
        await _calls.doc(call.callId).update({
          'status': callStatus,
          'endedAt': FieldValue.serverTimestamp(),
          'endedBy': call.me,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
    final historyStatus = call.connectedAt != null
        ? 'answered'
        : (call.outgoing ? (reason == 'no_answer' ? 'no_answer' : reason) : 'missed');
    _history(call.me, call.callId).update({
      'status': historyStatus,
      'durationSec': seconds,
      'endedAt': FieldValue.serverTimestamp(),
    }).catchError((_) {});
    try {
      for (final t in call.localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await call.localStream?.dispose();
    } catch (_) {}
    try {
      await call.pc?.close();
      await call.pc?.dispose();
    } catch (_) {}
    call.localStream = null;
    call.pc = null;
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  void _reset() {
    _pendingLocal.clear();
    _pendingRemote.clear();
    _signalingReady = false;
    _remoteSet = false;
    _appliedOffer = 0;
    _appliedAnswer = 0;
    _restarts = 0;
  }
}
