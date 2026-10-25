import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../state/session.dart';
import '../../utils/time_format.dart';
import '../../widgets/chat_avatar.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import 'chat_screen.dart';

class ChatsTab extends StatefulWidget {
  final String me;
  const ChatsTab({super.key, required this.me});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late Stream<List<Chat>> _chats = ChatService.instance.watchChats(widget.me);
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Chat>>(
      stream: _chats,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(
            message: context.tr('chats_load_failed'),
            details: '${snap.error}',
            retryLabel: context.tr('retry'),
            onRetry: () => setState(() => _chats = ChatService.instance.watchChats(widget.me)),
          );
        }
        if (!snap.hasData) return const LoadingView();
        final chats = snap.data!;
        if (chats.isEmpty) {
          return EmptyState(
            icon: Icons.forum_outlined,
            title: context.tr('no_chats_title'),
            message: context.tr('no_chats_message'),
          );
        }
        return ValueListenableBuilder<Set<String>>(
          valueListenable: Session.blocked,
          builder: (context, blocked, _) {
            final visible = chats.where((c) => c.isGroup || !blocked.contains(c.otherMember(widget.me))).toList();
            return Column(
              children: [
                if (chats.length > 6)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: context.tr('search_chats'),
                      ),
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
                    itemBuilder: (context, i) => _ChatTile(me: widget.me, chat: visible[i], query: _query),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String me;
  final Chat chat;
  final String query;
  const _ChatTile({required this.me, required this.chat, required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = chat.unreadFor(me);
    final typing = chat.typingUsers(me);
    final locale = Localizations.localeOf(context).languageCode;

    Widget subtitle;
    if (typing.isNotEmpty) {
      subtitle = Text(
        context.tr('typing'),
        style: TextStyle(color: theme.colorScheme.primary, fontStyle: FontStyle.italic),
      );
    } else {
      final preview = chat.lastMessageType == 'system' && chat.lastMessage.isEmpty
          ? context.tr('group_created_preview')
          : chat.lastMessage;
      final prefix = chat.lastSenderId == me && chat.lastMessage.isNotEmpty ? '${context.tr('you')}: ' : '';
      if (chat.isGroup && prefix.isEmpty && chat.lastSenderId.isNotEmpty && chat.lastMessageType != 'system') {
        subtitle = Row(children: [
          Flexible(
            child: UserName(
              uid: chat.lastSenderId,
              deletedLabel: context.tr('deleted_account'),
              format: (u) => '${u.displayName}: ',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(flex: 3, child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]);
      } else {
        subtitle = Text('$prefix$preview', maxLines: 1, overflow: TextOverflow.ellipsis);
      }
    }

    final title = chat.isGroup
        ? Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis)
        : UserName(uid: chat.otherMember(me), deletedLabel: context.tr('deleted_account'));

    final tile = ListTile(
      leading: ChatAvatar(chat: chat, me: me, radius: 26),
      title: DefaultTextStyle.merge(
        style: TextStyle(fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500),
        child: title,
      ),
      subtitle: subtitle,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (chat.lastMessageAt != null)
            Text(
              formatListTime(chat.lastMessageAt!, context.tr, locale),
              style: theme.textTheme.bodySmall?.copyWith(
                color: unread > 0 ? theme.colorScheme.primary : null,
              ),
            ),
          const SizedBox(height: 4),
          if (unread > 0)
            Badge(
              backgroundColor: theme.colorScheme.primary,
              label: Text(unread > 99 ? '99+' : '$unread'),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(me: me, chat: chat),
      )),
    );

    if (query.isEmpty) return tile;
    // Filter by name; direct chat names are resolved from the profile.
    if (chat.isGroup) return chat.name.toLowerCase().contains(query) ? tile : const SizedBox.shrink();
    return _NameFilter(uid: chat.otherMember(me), query: query, child: tile);
  }
}

class _NameFilter extends StatelessWidget {
  final String uid;
  final String query;
  final Widget child;
  const _NameFilter({required this.uid, required this.query, required this.child});

  @override
  Widget build(BuildContext context) {
    return UserNameMatcher(uid: uid, query: query, child: child);
  }
}
