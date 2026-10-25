import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../../state/session.dart';
import '../../widgets/states.dart';
import '../profile/profile_edit_screen.dart';

/// Sign-in details, username and account deletion.
class AccountScreen extends StatefulWidget {
  final User authUser;
  final AppUser me;
  const AccountScreen({super.key, required this.authUser, required this.me});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (!AuthService.instance.signedInRecently) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('delete_account')),
          content: Text(ctx.tr('delete_needs_recent_login')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok'))),
          ],
        ),
      );
      return;
    }
    final confirmText = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('delete_account_q')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ctx.tr('delete_account_explanation')),
          const SizedBox(height: 12),
          TextField(
            controller: confirmText,
            decoration: InputDecoration(labelText: ctx.tr('type_delete_to_confirm')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, confirmText.text.trim().toUpperCase() == 'DELETE'),
            child: Text(ctx.tr('delete'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    confirmText.dispose();
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await NotificationService.instance.unregister(widget.authUser.uid);
      await ContactsService.instance.clear();
      await UserService.instance.deleteAccount(widget.authUser);
      Session.clear();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showSnack(context, context.tr(AuthService.errorKey(e.code)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showSnack(context, context.tr('action_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.authUser;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('account'))),
      body: AbsorbPointer(
        absorbing: _deleting,
        child: ListView(
          children: [
            if (_deleting) const LinearProgressIndicator(),
            if (u.phoneNumber != null)
              ListTile(
                leading: const Icon(Icons.phone),
                title: Text(context.tr('phone_number')),
                subtitle: Text(u.phoneNumber!, textDirection: TextDirection.ltr),
              ),
            if (u.email != null)
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: Text(context.tr('email')),
                subtitle: Text(u.email!),
                trailing: u.emailVerified
                    ? Chip(label: Text(context.tr('verified')))
                    : TextButton(
                        onPressed: () async {
                          try {
                            await AuthService.instance.resendEmailVerification();
                            if (context.mounted) showSnack(context, context.tr('verification_sent'));
                          } catch (_) {
                            if (context.mounted) showSnack(context, context.tr('action_failed'));
                          }
                        },
                        child: Text(context.tr('verify')),
                      ),
              ),
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(context.tr('username')),
              subtitle: Text(widget.me.username != null ? '@${widget.me.username}' : '—'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProfileEditScreen(authUser: u, existing: widget.me),
              )),
            ),
            if (u.email != null)
              ListTile(
                leading: const Icon(Icons.password),
                title: Text(context.tr('reset_password')),
                onTap: () async {
                  try {
                    await AuthService.instance.sendPasswordReset(u.email!);
                    if (context.mounted) showSnack(context, context.tr('reset_email_sent'));
                  } catch (_) {
                    if (context.mounted) showSnack(context, context.tr('action_failed'));
                  }
                },
              ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
              title: Text(context.tr('delete_account'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: Text(context.tr('delete_account_subtitle')),
              onTap: _delete,
            ),
          ],
        ),
      ),
    );
  }
}
