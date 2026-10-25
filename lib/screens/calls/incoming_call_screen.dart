import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/call_models.dart';
import '../../services/call_service.dart';
import '../../services/user_service.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import 'call_screen.dart';

/// Full-screen incoming call with accept and decline.
class IncomingCallScreen extends StatefulWidget {
  final CallDoc call;
  final String me;
  const IncomingCallScreen({super.key, required this.call, required this.me});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription<CallDoc?>? _sub;
  Timer? _vibrate;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Close when the caller hangs up or the call is answered elsewhere.
    _sub = CallService.instance.watchCall(widget.call.id).listen((c) {
      if (c == null || c.status != 'ringing') {
        if (mounted && !_busy) Navigator.of(context).maybePop();
      }
    }, onError: (_) {});
    _vibrate = Timer.periodic(
        const Duration(seconds: 2), (_) => HapticFeedback.heavyImpact());
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _vibrate?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    _vibrate?.cancel();
    final nav = Navigator.of(context);
    try {
      final active = await CallService.instance.accept(widget.call, widget.me);
      await _sub?.cancel();
      if (!mounted) return;
      if (active.isOver) {
        nav.pop();
        return;
      }
      nav.pushReplacement(
          MaterialPageRoute(builder: (_) => CallScreen(call: active)));
    } on CallPermissionDenied catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = context.tr(widget.call.kind == CallKind.video
          ? 'camera_mic_permission'
          : 'mic_permission_needed');
      if (e.permanently) {
        final open = await confirm(
          context,
          title: context.tr('permission_needed'),
          message: msg,
          confirmLabel: context.tr('open_settings'),
          cancelLabel: context.tr('cancel'),
        );
        if (open) await openAppSettings();
      } else {
        showSnack(context, msg);
      }
    } catch (_) {
      if (!mounted) return;
      showSnack(context, context.tr('call_failed'));
      nav.maybePop();
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    await CallService.instance.reject(widget.call, widget.me);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.call.kind == CallKind.video;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1413),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              context.tr(video ? 'incoming_video_call' : 'incoming_voice_call'),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            UserAvatar(uid: widget.call.callerId, radius: 64),
            const SizedBox(height: 16),
            StreamBuilder<AppUser>(
              stream: UserService.instance.watchUser(widget.call.callerId),
              initialData:
                  UserService.instance.cachedUser(widget.call.callerId),
              builder: (context, snap) => Text(
                snap.data?.displayName ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CircleAction(
                  color: Colors.red,
                  icon: Icons.call_end,
                  label: context.tr('decline'),
                  onTap: _busy ? null : _decline,
                ),
                _CircleAction(
                  color: Colors.green,
                  icon: video ? Icons.videocam : Icons.call,
                  label: context.tr('accept'),
                  onTap: _busy ? null : _accept,
                ),
              ],
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _CircleAction(
      {required this.color,
      required this.icon,
      required this.label,
      this.onTap});

  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(22),
                child: Icon(icon, color: Colors.white, size: 34)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ]);
}
