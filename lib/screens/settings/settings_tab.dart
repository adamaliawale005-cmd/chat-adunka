import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../../state/app_settings.dart';
import '../../state/session.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../profile/profile_edit_screen.dart';
import 'account_screen.dart';
import 'help_screen.dart';
import 'language_sheet.dart';
import 'notification_settings_screen.dart';
import 'privacy_screen.dart';

class SettingsTab extends StatelessWidget {
  final AppUser me;
  final User authUser;
  const SettingsTab({super.key, required this.me, required this.authUser});

  Future<void> _signOut(BuildContext context) async {
    final ok = await confirm(
      context,
      title: context.tr('sign_out_q'),
      message: context.tr('sign_out_explanation'),
      confirmLabel: context.tr('sign_out'),
      cancelLabel: context.tr('cancel'),
    );
    if (!ok) return;
    await UserService.instance.setPresence(authUser.uid, online: false);
    await NotificationService.instance.unregister(authUser.uid);
    Session.clear();
    await AuthService.instance.signOut();
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final settings = AppSettings.instance;
    final lang = settings.locale == null
        ? context.tr('system_default')
        : (AppLocalizations.languageNames[settings.locale!.languageCode] ?? '');
    final theme = context.tr(switch (settings.themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system_default',
    });
    return ListView(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Avatar(
              photoBase64: me.photoBase64, name: me.displayName, radius: 32),
          title: Text(me.displayName,
              style: Theme.of(context).textTheme.titleLarge),
          subtitle: Text(
            [
              if (me.username != null) '@${me.username}',
              if (me.about.isNotEmpty) me.about
            ].join('\n'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _push(
              context, ProfileEditScreen(authUser: authUser, existing: me)),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(context.tr('account')),
          subtitle: Text(context.tr('account_subtitle')),
          onTap: () =>
              _push(context, AccountScreen(authUser: authUser, me: me)),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(context.tr('privacy')),
          subtitle: Text(context.tr('privacy_subtitle')),
          onTap: () => _push(context, PrivacyScreen(authUser: authUser)),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: Text(context.tr('notifications')),
          subtitle: Text(context.tr('notifications_subtitle')),
          onTap: () =>
              _push(context, NotificationSettingsScreen(authUser: authUser)),
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(context.tr('theme')),
          subtitle: Text(theme),
          onTap: () => showThemeSheet(context),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(context.tr('language')),
          subtitle: Text(lang),
          onTap: () => showLanguageSheet(context),
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(context.tr('help')),
          subtitle: Text(context.tr('help_subtitle')),
          onTap: () => _push(context, const HelpScreen()),
        ),
        const Divider(),
        ListTile(
          leading:
              Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: Text(context.tr('sign_out'),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => _signOut(context),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
