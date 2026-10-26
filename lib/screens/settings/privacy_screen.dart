import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/contacts_service.dart';
import '../../services/user_service.dart';
import '../../state/session.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

class PrivacyScreen extends StatefulWidget {
  final User authUser;
  const PrivacyScreen({super.key, required this.authUser});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _saving = false;

  Future<void> _update(AccountPrivate next) async {
    setState(() => _saving = true);
    try {
      await UserService.instance.updatePrivate(widget.authUser, next);
      if (!next.contactSync) await ContactsService.instance.clear();
    } catch (_) {
      if (mounted) showSnack(context, context.tr('action_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('privacy'))),
      body: ValueListenableBuilder<AccountPrivate>(
        valueListenable: Session.settings,
        builder: (context, s, _) => AbsorbPointer(
          absorbing: _saving,
          child: ListView(children: [
            if (_saving) const LinearProgressIndicator(),
            if (widget.authUser.phoneNumber != null)
              SwitchListTile(
                secondary: const Icon(Icons.phone_outlined),
                title: Text(context.tr('privacy_phone_title')),
                subtitle: Text(context.tr('privacy_phone_subtitle')),
                value: s.discoverableByPhone,
                onChanged: (v) => _update(s.copyWith(discoverableByPhone: v)),
              ),
            SwitchListTile(
              secondary: const Icon(Icons.search),
              title: Text(context.tr('privacy_directory_title')),
              subtitle: Text(context.tr('privacy_directory_subtitle')),
              value: s.showInDirectory,
              onChanged: (v) => _update(s.copyWith(showInDirectory: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.access_time),
              title: Text(context.tr('privacy_last_seen_title')),
              subtitle: Text(context.tr('privacy_last_seen_subtitle')),
              value: s.showLastSeen,
              onChanged: (v) => _update(s.copyWith(showLastSeen: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.done_all),
              title: Text(context.tr('privacy_read_receipts_title')),
              subtitle: Text(context.tr('privacy_read_receipts_subtitle')),
              value: s.readReceipts,
              onChanged: (v) => _update(s.copyWith(readReceipts: v)),
            ),
            if (!kIsWeb)
              SwitchListTile(
                secondary: const Icon(Icons.contacts_outlined),
                title: Text(context.tr('privacy_contacts_title')),
                subtitle: Text(context.tr('privacy_contacts_subtitle')),
                value: s.contactSync,
                onChanged: (v) => _update(s.copyWith(contactSync: v)),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(context.tr('blocked_users')),
              trailing: ValueListenableBuilder<Set<String>>(
                valueListenable: Session.blocked,
                builder: (context, b, _) => Text('${b.length}'),
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BlockedUsersScreen(me: widget.authUser.uid),
              )),
            ),
          ]),
        ),
      ),
    );
  }
}

class BlockedUsersScreen extends StatelessWidget {
  final String me;
  const BlockedUsersScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('blocked_users'))),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: Session.blocked,
        builder: (context, blocked, _) {
          if (blocked.isEmpty) {
            return EmptyState(
                icon: Icons.block, title: context.tr('no_blocked_users'));
          }
          return ListView(children: [
            for (final uid in blocked)
              ListTile(
                leading: UserAvatar(uid: uid),
                title: UserName(
                    uid: uid, deletedLabel: context.tr('deleted_account')),
                trailing: TextButton(
                  onPressed: () => UserService.instance.unblock(me, uid),
                  child: Text(context.tr('unblock')),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
