import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/user_avatar.dart';
import 'profile_edit_screen.dart';

class MyProfileView extends StatelessWidget {
  final AppUser me;
  const MyProfileView({super.key, required this.me});

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to verify your phone number again to sign in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await NotificationService.instance.unregister(me.uid);
    await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final status = NotificationService.instance.lastStatus;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(child: UserAvatar(photoBase64: me.photoBase64, name: me.displayName, radius: 56)),
        const SizedBox(height: 16),
        Center(child: Text(me.displayName, style: Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: 4),
        Center(child: Text(me.phoneNumber)),
        if (me.about.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(child: Text(me.about, textAlign: TextAlign.center)),
        ],
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('Edit profile'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ProfileEditScreen(
              uid: me.uid,
              phoneNumber: me.phoneNumber,
              existing: me,
            ),
          )),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          subtitle: Text(status == null ? 'Checking…' : 'Permission: $status'),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => _signOut(context),
        ),
      ],
    );
  }
}
