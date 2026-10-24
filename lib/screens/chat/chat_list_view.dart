import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../utils/time_format.dart';
import '../../widgets/user_avatar.dart';
import 'chat_screen.dart';

class ChatListView extends StatelessWidget {
  final AppUser me;
  const ChatListView({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatSummary>>(
      stream: ChatService.instance.watchChats(me.uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load chats: ${snap.error}', textAlign: TextAlign.center),
          ));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final chats = snap.data!;
        if (chats.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No chats yet.\nOpen Contacts to start a conversation.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: chats.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, i) => _ChatTile(me: me, chat: chats[i]),
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final AppUser me;
  final ChatSummary chat;
  const _ChatTile({required this.me, required this.chat});

  @override
  Widget build(BuildContext context) {
    final otherId = chat.otherParticipant(me.uid);
    return StreamBuilder<AppUser?>(
      stream: UserService.instance.watchUser(otherId),
      builder: (context, snap) {
        final other = snap.data;
        final name = other?.displayName ?? '…';
        final mine = chat.lastSenderId == me.uid;
        return ListTile(
          leading: UserAvatar(photoBase64: other?.photoBase64, name: name, radius: 26),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${mine ? 'You: ' : ''}${chat.lastMessage}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: chat.updatedAt == null
              ? null
              : Text(formatListTime(chat.updatedAt!), style: Theme.of(context).textTheme.bodySmall),
          onTap: other == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(me: me, other: other),
                  )),
        );
      },
    );
  }
}
