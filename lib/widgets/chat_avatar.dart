import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/chat_models.dart';
import '../services/user_service.dart';
import 'user_avatar.dart';

/// Group picture, or the other person's picture for a direct chat.
class ChatAvatar extends StatelessWidget {
  final Chat chat;
  final String me;
  final double radius;
  const ChatAvatar(
      {super.key, required this.chat, required this.me, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    if (chat.isGroup) {
      return Avatar(
          photoBase64: chat.photoBase64,
          name: chat.name,
          radius: radius,
          fallbackIcon: Icons.groups);
    }
    return UserAvatar(
        uid: chat.otherMember(me), radius: radius, showOnline: true);
  }
}

/// Shows [child] only if the user's name or username contains [query].
class UserNameMatcher extends StatelessWidget {
  final String uid;
  final String query;
  final Widget child;
  const UserNameMatcher(
      {super.key, required this.uid, required this.query, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser>(
      stream: UserService.instance.watchUser(uid),
      initialData: UserService.instance.cachedUser(uid),
      builder: (context, snap) {
        final u = snap.data;
        if (u == null) return const SizedBox.shrink();
        final match = u.displayName.toLowerCase().contains(query) ||
            (u.username ?? '').contains(query);
        return match ? child : const SizedBox.shrink();
      },
    );
  }
}
