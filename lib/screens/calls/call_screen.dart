import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/call_service.dart';
import '../../services/user_service.dart';
import '../../utils/time_format.dart';
import '../../widgets/user_avatar.dart';

/// Ongoing call: video views, status, duration and controls.
class CallScreen extends StatefulWidget {
  final ActiveCall call;
  const CallScreen({super.key, required this.call});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _ticker;
  bool _closing = false;

  ActiveCall get call => widget.call;

  @override
  void initState() {
    super.initState();
    call.addListener(_onChange);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && call.phase == CallPhase.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    call.removeListener(_onChange);
    if (!call.isOver) CallService.instance.hangUp();
    call.disposeRenderers();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (call.isOver && !_closing) {
      _closing = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  String _status(BuildContext context) {
    switch (call.phase) {
      case CallPhase.outgoing:
        return context.tr('calling');
      case CallPhase.incoming:
        return context.tr('incoming_call');
      case CallPhase.connecting:
        return context.tr('connecting');
      case CallPhase.reconnecting:
        return context.tr('reconnecting');
      case CallPhase.connected:
        return formatDuration(call.duration);
      case CallPhase.ended:
        return context.tr('call_end_${call.endReason ?? 'ended'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo = call.isVideo && call.remoteVideo && call.phase != CallPhase.ended;
    return PopScope(
      canPop: call.isOver,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1413),
        body: Stack(
          children: [
            if (showRemoteVideo)
              Positioned.fill(
                child: RTCVideoView(call.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  if (!showRemoteVideo) ...[
                    UserAvatar(uid: call.peerId, radius: 56),
                    const SizedBox(height: 16),
                  ],
                  StreamBuilder<AppUser>(
                    stream: UserService.instance.watchUser(call.peerId),
                    initialData: UserService.instance.cachedUser(call.peerId),
                    builder: (context, snap) => Text(
                      snap.data?.displayName ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_status(context), style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  if (call.phase == CallPhase.reconnecting)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SizedBox(width: 120, child: LinearProgressIndicator()),
                    ),
                  const Spacer(),
                  _controls(context),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            if (call.isVideo && !call.cameraOff && call.phase != CallPhase.ended)
              PositionedDirectional(
                end: 16,
                top: MediaQuery.of(context).padding.top + 16,
                width: 110,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    call.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final svc = CallService.instance;
    final ended = call.isOver;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 18,
      children: [
        _RoundButton(
          icon: call.micMuted ? Icons.mic_off : Icons.mic,
          label: context.tr(call.micMuted ? 'unmute' : 'mute'),
          active: call.micMuted,
          onTap: ended ? null : svc.toggleMute,
        ),
        _RoundButton(
          icon: call.speakerOn ? Icons.volume_up : Icons.hearing,
          label: context.tr(call.speakerOn ? 'speaker' : 'earpiece'),
          active: call.speakerOn,
          onTap: ended ? null : svc.toggleSpeaker,
        ),
        if (call.isVideo) ...[
          _RoundButton(
            icon: call.cameraOff ? Icons.videocam_off : Icons.videocam,
            label: context.tr(call.cameraOff ? 'camera_on' : 'camera_off'),
            active: call.cameraOff,
            onTap: ended ? null : svc.toggleCamera,
          ),
          _RoundButton(
            icon: Icons.cameraswitch,
            label: context.tr('switch_camera'),
            onTap: ended || call.cameraOff ? null : svc.switchCamera,
          ),
        ],
        _RoundButton(
          icon: Icons.call_end,
          label: context.tr('end_call'),
          color: Colors.red,
          onTap: ended ? null : () => svc.hangUp(),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;
  const _RoundButton({required this.icon, required this.label, this.onTap, this.active = false, this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (active ? Colors.white : Colors.white24);
    final fg = color != null ? Colors.white : (active ? Colors.black : Colors.white);
    return SizedBox(
      width: 72,
      child: Column(children: [
        Material(
          color: onTap == null ? bg.withValues(alpha: 0.4) : bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(16), child: Icon(icon, color: fg, size: 28)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
      ]),
    );
  }
}
