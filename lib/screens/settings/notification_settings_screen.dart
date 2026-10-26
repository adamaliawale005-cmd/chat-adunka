import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/user_service.dart';
import '../../state/session.dart';
import '../../widgets/states.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final User authUser;
  const NotificationSettingsScreen({super.key, required this.authUser});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  PermissionStatus? _permission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (kIsWeb) return;
    final s = await Permission.notification.status;
    if (mounted) setState(() => _permission = s);
  }

  Future<void> _request() async {
    final s = await Permission.notification.request();
    if (s.isPermanentlyDenied) await openAppSettings();
    await _check();
  }

  Future<void> _update(AccountPrivate next) async {
    try {
      await UserService.instance.updatePrivate(widget.authUser, next);
    } catch (_) {
      if (mounted) showSnack(context, context.tr('action_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final granted = _permission?.isGranted ?? true;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('notifications'))),
      body: ValueListenableBuilder<AccountPrivate>(
        valueListenable: Session.settings,
        builder: (context, s, _) => ListView(children: [
          if (!granted)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(context.tr('notifications_blocked')),
                trailing: TextButton(
                    onPressed: _request, child: Text(context.tr('allow'))),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.chat_bubble_outline),
            title: Text(context.tr('notify_messages')),
            value: s.notifyMessages,
            onChanged: (v) => _update(s.copyWith(notifyMessages: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.groups_outlined),
            title: Text(context.tr('notify_groups')),
            value: s.notifyGroups,
            onChanged: (v) => _update(s.copyWith(notifyGroups: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.call_outlined),
            title: Text(context.tr('notify_calls')),
            value: s.notifyCalls,
            onChanged: (v) => _update(s.copyWith(notifyCalls: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: Text(context.tr('notify_preview')),
            subtitle: Text(context.tr('notify_preview_subtitle')),
            value: s.notificationPreview,
            onChanged: (v) => _update(s.copyWith(notificationPreview: v)),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr('push_note'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
}
