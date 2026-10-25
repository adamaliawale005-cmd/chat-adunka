import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/call_models.dart';
import '../../services/user_service.dart';
import '../../state/session.dart';
import '../../utils/time_format.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../calls/start_call.dart';
import '../chat/chat_screen.dart';

/// Someone else's public profile.
class UserProfileScreen extends StatelessWidget {
  final String me;
  final String uid;
  final bool fromChat;
  const UserProfileScreen(
      {super.key, required this.me, required this.uid, this.fromChat = false});

  Future<void> _toggleBlock(BuildContext context, bool blocked) async {
    try {
      if (blocked) {
        await UserService.instance.unblock(me, uid);
      } else {
        final ok = await confirm(
          context,
          title: context.tr('block_q'),
          message: context.tr('block_explanation'),
          confirmLabel: context.tr('block'),
          cancelLabel: context.tr('cancel'),
          destructive: true,
        );
        if (ok) await UserService.instance.block(me, uid);
      }
    } catch (_) {
      if (context.mounted) showSnack(context, context.tr('action_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: StreamBuilder<AppUser>(
        stream: UserService.instance.watchUser(uid),
        initialData: UserService.instance.cachedUser(uid),
        builder: (context, snap) {
          final u = snap.data;
          if (u == null) return const LoadingView();
          if (!u.hasProfile) {
            return EmptyState(
                icon: Icons.person_off_outlined,
                title: context.tr('deleted_account'));
          }
          return ValueListenableBuilder<Set<String>>(
            valueListenable: Session.blocked,
            builder: (context, blockedSet, _) {
              final blocked = blockedSet.contains(uid);
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                children: [
                  Center(
                      child: Avatar(
                          photoBase64: u.photoBase64,
                          name: u.displayName,
                          radius: 64)),
                  const SizedBox(height: 16),
                  Center(
                      child: Text(u.displayName,
                          style: Theme.of(context).textTheme.headlineSmall)),
                  if (u.username != null)
                    Center(
                        child: Text('@${u.username}',
                            textDirection: TextDirection.ltr)),
                  const SizedBox(height: 4),
                  if (!blocked)
                    Center(
                      child: Text(
                        u.isOnlineNow
                            ? context.tr('online')
                            : formatLastSeen(u.lastSeen, context.tr, locale),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (u.about.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(u.about, textAlign: TextAlign.center),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (!blocked && uid != me)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Action(
                          icon: Icons.chat_bubble_outline,
                          label: context.tr('message'),
                          onTap: () {
                            if (fromChat) {
                              Navigator.of(context).pop();
                            } else {
                              ChatScreen.openDirect(context, me, uid);
                            }
                          },
                        ),
                        _Action(
                          icon: Icons.call_outlined,
                          label: context.tr('voice_call'),
                          onTap: () => startCall(context,
                              me: me, peer: uid, kind: CallKind.audio),
                        ),
                        _Action(
                          icon: Icons.videocam_outlined,
                          label: context.tr('video_call'),
                          onTap: () => startCall(context,
                              me: me, peer: uid, kind: CallKind.video),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (uid != me) ...[
                    const Divider(),
                    ListTile(
                      leading: Icon(blocked ? Icons.lock_open : Icons.block,
                          color: Theme.of(context).colorScheme.error),
                      title: Text(context.tr(blocked ? 'unblock' : 'block')),
                      onTap: () => _toggleBlock(context, blocked),
                    ),
                    ListTile(
                      leading: Icon(Icons.flag_outlined,
                          color: Theme.of(context).colorScheme.error),
                      title: Text(context.tr('report')),
                      onTap: () => showReportDialog(context,
                          reporter: me, reported: uid),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(children: [
          IconButton.filledTonal(
              onPressed: onTap, icon: Icon(icon), iconSize: 28),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
