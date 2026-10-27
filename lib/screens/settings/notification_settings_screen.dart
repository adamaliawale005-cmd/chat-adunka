import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/user_service.dart';
import '../../services/web_notify.dart';
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
  String _webPermission = 'unsupported';

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
    if (kIsWeb) {
      if (mounted) setState(() => _webPermission = WebNotify.permission);
      return;
    }
    final s = await Permission.notification.status;
    if (mounted) setState(() => _permission = s);
  }

  Future<void> _request() async {
    if (kIsWeb) {
      await WebNotify.requestPermission();
      await _check();
      return;
    }
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

  /// Browser permission for system notifications (web app only).
  Widget _webTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_webPermission) {
      case 'granted':
        return ListTile(
          leading: Icon(Icons.notifications_active, color: scheme.primary),
          title: Text(context.tr('browser_notifications')),
          subtitle: Text(context.tr('browser_notifications_on')),
        );
      case 'default':
        return Material(
          color: scheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.notifications_none),
            title: Text(context.tr('browser_notifications')),
            subtitle: Text(context.tr('browser_notifications_ask')),
            trailing: FilledButton(
                onPressed: _request, child: Text(context.tr('allow'))),
          ),
        );
      case 'denied':
        return Material(
          color: scheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(context.tr('browser_notifications')),
            subtitle: Text(context.tr('browser_notifications_blocked')),
            trailing: TextButton(
                onPressed: _check, child: Text(context.tr('retry'))),
          ),
        );
      default:
        return ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(context.tr('browser_notifications')),
          subtitle: Text(context.tr('browser_notifications_unsupported')),
        );
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
          if (kIsWeb) _webTile(context),
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
            child: Text(context.tr(kIsWeb ? 'web_push_note' : 'push_note'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
}
