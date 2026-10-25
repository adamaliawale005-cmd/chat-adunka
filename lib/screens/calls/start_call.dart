import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/call_models.dart';
import '../../services/call_service.dart';
import '../../widgets/states.dart';
import 'call_screen.dart';

/// Starts a voice or video call and opens the call screen.
Future<void> startCall(BuildContext context, {required String me, required String peer, required CallKind kind}) async {
  try {
    final call = await CallService.instance.startCall(me: me, peer: peer, kind: kind);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(call: call)));
  } on CallPermissionDenied catch (e) {
    if (!context.mounted) return;
    if (e.permanently) {
      final open = await confirm(
        context,
        title: context.tr('permission_needed'),
        message: context.tr(kind == CallKind.video ? 'camera_mic_permission' : 'mic_permission_needed'),
        confirmLabel: context.tr('open_settings'),
        cancelLabel: context.tr('cancel'),
      );
      if (open) await openAppSettings();
    } else {
      showSnack(context, context.tr(kind == CallKind.video ? 'camera_mic_permission' : 'mic_permission_needed'));
    }
  } on CallBusyException {
    if (context.mounted) showSnack(context, context.tr('already_in_call'));
  } catch (e) {
    if (context.mounted) showSnack(context, context.tr('call_failed'));
  }
}
