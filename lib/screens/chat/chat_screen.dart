import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/call_models.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/chat_avatar.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/states.dart';
import '../calls/start_call.dart';
import '../groups/group_info_screen.dart';
import '../profile/user_profile_screen.dart';
import 'composer.dart';
import 'forward_screen.dart';
import 'message_bubble.dart';
import 'message_search_screen.dart';

class ChatScreen extends StatefulWidget {
  final String me;
  final Chat chat;
  const ChatScreen({super.key, required this.me, required this.chat});

  /// Opens (or starts) a direct chat with [other].
  static Future<void> openDirect(BuildContext context, String me, String other) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(me: me, chat: Chat.direct(me, other)),
    ));
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late Chat _chat = widget.chat;
  late final StreamSubscription<Chat?> _chatSub;
  int _limit = 40;
  late Stream<List<ChatMessage>> _messages;
  List<ChatMessage> _last = const [];
  ReplyInfo? _replyTo;
  ChatMessage? _editing;
  bool _foreground = true;
  final Set<String> _readRequested = {};

  String get me => widget.me;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ChatService.instance.openChats.add(_chat.id);
    NotificationService.instance.cancelFor('chat:${_chat.id}');
    _messages = ChatService.instance.watchMessages(_chat.id, limit: _limit);
    _chatSub = ChatService.instance.watchChat(_chat.id).listen((c) {
      if (c != null && mounted) setState(() => _chat = c);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ChatService.instance.openChats.remove(_chat.id);
    ChatService.instance.setTyping(_chat.id, me, false);
    _chatSub.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _markRead(_last);
  }

  void _loadMore() {
    if (_last.length < _limit) return;
    setState(() {
      _limit += 40;
      _messages = ChatService.instance.watchMessages(_chat.id, limit: _limit);
    });
  }

  void _markRead(List<ChatMessage> messages) {
    if (!_foreground || !mounted) return;
    final readReceipts = Session.settings.value.readReceipts;
    final todo = messages.where((m) {
      if (m.senderId == me || m.isSystem || !m.fromServer) return false;
      final key = '${m.id}:${m.status.name}:${m.readBy.length}';
      if (_readRequested.contains(key)) return false;
      final needs = _chat.isGroup ? (readReceipts && !m.readBy.contains(me)) : m.status != MessageStatus.read;
      if (needs) _readRequested.add(key);
      return needs;
    }).toList();
    if (todo.isEmpty && _chat.unreadFor(me) == 0) return;
    ChatService.instance.markRead(_chat, me, todo, readReceipts: readReceipts);
  }

  // ---------- actions ----------

  ReplyInfo _replyFor(ChatMessage m) => ReplyInfo(
        messageId: m.id,
        senderId: m.senderId,
        text: m.text.isNotEmpty ? m.text : (m.attachment?.name ?? ''),
        type: m.type,
      );

  Future<void> _onSendText(String text) async {
    if (_editing != null) {
      final m = _editing!;
      setState(() => _editing = null);
      if (text.trim() == m.text.trim()) return;
      try {
        await ChatService.instance.edit(m, text);
      } catch (e) {
        if (mounted) showSnack(context, context.tr('edit_failed'));
      }
      return;
    }
    final reply = _replyTo;
    setState(() => _replyTo = null);
    await ChatService.instance.sendText(chat: _chat, senderId: me, text: text, replyTo: reply);
  }

  Future<void> _messageMenu(ChatMessage m) async {
    if (m.isSystem) return;
    HapticFeedback.selectionClick();
    final mine = m.senderId == me;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          if (!m.deleted && _chat.canSend(me))
            ListTile(leading: const Icon(Icons.reply), title: Text(ctx.tr('reply')), onTap: () => Navigator.pop(ctx, 'reply')),
          if (!m.deleted && m.text.isNotEmpty)
            ListTile(leading: const Icon(Icons.copy), title: Text(ctx.tr('copy')), onTap: () => Navigator.pop(ctx, 'copy')),
          if (!m.deleted)
            ListTile(leading: const Icon(Icons.shortcut), title: Text(ctx.tr('forward')), onTap: () => Navigator.pop(ctx, 'forward')),
          if (ChatService.canEdit(m, me))
            ListTile(leading: const Icon(Icons.edit), title: Text(ctx.tr('edit')), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(ctx.tr('delete_for_me')),
            onTap: () => Navigator.pop(ctx, 'hide'),
          ),
          if (mine && !m.deleted)
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: Text(ctx.tr('delete_for_everyone')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          if (!mine && !m.deleted)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(ctx.tr('report')),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'reply':
          setState(() {
            _editing = null;
            _replyTo = _replyFor(m);
          });
          break;
        case 'copy':
          await Clipboard.setData(ClipboardData(text: m.text));
          if (mounted) showSnack(context, context.tr('copied'));
          break;
        case 'forward':
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ForwardScreen(me: me, message: m),
          ));
          break;
        case 'edit':
          setState(() {
            _replyTo = null;
            _editing = m;
          });
          break;
        case 'hide':
          await ChatService.instance.hideForMe(m, me);
          break;
        case 'delete':
          final ok = await confirm(
            context,
            title: context.tr('delete_for_everyone_q'),
            confirmLabel: context.tr('delete'),
            cancelLabel: context.tr('cancel'),
            destructive: true,
          );
          if (ok) await ChatService.instance.deleteForEveryone(m);
          break;
        case 'report':
          await showReportDialog(context, reporter: me, reported: m.senderId, chatId: _chat.id, messageId: m.id);
          break;
      }
    } catch (e) {
      if (mounted) showSnack(context, context.tr('action_failed'));
    }
  }

  Future<void> _toggleBlock(bool blocked) async {
    final other = _chat.otherMember(me);
    try {
      if (blocked) {
        await UserService.instance.unblock(me, other);
      } else {
        final ok = await confirm(
          context,
          title: context.tr('block_q'),
          message: context.tr('block_explanation'),
          confirmLabel: context.tr('block'),
          cancelLabel: context.tr('cancel'),
          destructive: true,
        );
        if (ok) await UserService.instance.block(me, other);
      }
    } catch (_) {
      if (mounted) showSnack(context, context.tr('action_failed'));
    }
  }

  void _openInfo() {
    if (_chat.isGroup) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupInfoScreen(me: me, chatId: _chat.id)));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UserProfileScreen(me: me, uid: _chat.otherMember(me), fromChat: true),
      ));
    }
  }

  // ---------- UI ----------

  PreferredSizeWidget _appBar(bool blocked) {
    final locale = Localizations.localeOf(context).languageCode;
    final typing = _chat.typingUsers(me);
    Widget subtitle;
    if (_chat.isGroup) {
      subtitle = typing.isNotEmpty
          ? Text(context.tr('typing'))
          : Text(context.tr('members_count', {'count': _chat.members.length}));
    } else {
      final other = _chat.otherMember(me);
      subtitle = typing.isNotEmpty
          ? Text(context.tr('typing'))
          : StreamBuilder<AppUser>(
              stream: UserService.instance.watchUser(other),
              initialData: UserService.instance.cachedUser(other),
              builder: (context, snap) {
                final u = snap.data;
                if (u == null || !u.hasProfile || blocked) return const SizedBox.shrink();
                if (u.isOnlineNow) return Text(context.tr('online'));
                if (u.lastSeen == null) return const SizedBox.shrink();
                return Text(formatLastSeen(u.lastSeen, context.tr, locale), maxLines: 1, overflow: TextOverflow.ellipsis);
              },
            );
    }
    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: _openInfo,
        child: Row(children: [
          ChatAvatar(chat: _chat, me: me, radius: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _chat.isGroup
                    ? Text(_chat.name, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : StreamBuilder<AppUser>(
                        stream: UserService.instance.watchUser(_chat.otherMember(me)),
                        initialData: UserService.instance.cachedUser(_chat.otherMember(me)),
                        builder: (context, snap) => Text(
                          snap.data == null
                              ? ''
                              : (snap.data!.hasProfile ? snap.data!.displayName : context.tr('deleted_account')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, color: Colors.white70), child: subtitle),
              ],
            ),
          ),
        ]),
      ),
      actions: [
        if (!_chat.isGroup && !blocked) ...[
          IconButton(
            tooltip: context.tr('video_call'),
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => startCall(context, me: me, peer: _chat.otherMember(me), kind: CallKind.video),
          ),
          IconButton(
            tooltip: context.tr('voice_call'),
            icon: const Icon(Icons.call_outlined),
            onPressed: () => startCall(context, me: me, peer: _chat.otherMember(me), kind: CallKind.audio),
          ),
        ],
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'info':
                _openInfo();
                break;
              case 'search':
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MessageSearchScreen(me: me, chat: _chat),
                ));
                break;
              case 'block':
                _toggleBlock(blocked);
                break;
              case 'report':
                showReportDialog(context, reporter: me, reported: _chat.otherMember(me), chatId: _chat.id);
                break;
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'info', child: Text(ctx.tr(_chat.isGroup ? 'group_info' : 'view_profile'))),
            PopupMenuItem(value: 'search', child: Text(ctx.tr('search'))),
            if (!_chat.isGroup) PopupMenuItem(value: 'block', child: Text(ctx.tr(blocked ? 'unblock' : 'block'))),
            if (!_chat.isGroup) PopupMenuItem(value: 'report', child: Text(ctx.tr('report'))),
          ],
        ),
      ],
    );
  }

  Widget _banner(String text, {VoidCallback? onTap, String? actionLabel}) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: Text(text, textAlign: TextAlign.center)),
              if (onTap != null) TextButton(onPressed: onTap, child: Text(actionLabel ?? '')),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: Session.blocked,
      builder: (context, blockedSet, _) {
        final blocked = !_chat.isGroup && blockedSet.contains(_chat.otherMember(me));
        final notMember = _chat.isGroup && !_chat.members.contains(me);
        return Scaffold(
          backgroundColor: context.chatColors.chatBackground,
          appBar: _appBar(blocked),
          body: Column(
            children: [
              Expanded(child: _messageList()),
              if (blocked)
                _banner(context.tr('you_blocked_contact'), onTap: () => _toggleBlock(true), actionLabel: context.tr('unblock'))
              else if (notMember)
                _banner(context.tr('not_a_member'))
              else if (!_chat.canSend(me))
                _banner(context.tr('only_admins_can_send'))
              else
                Composer(
                  key: ValueKey('composer-${_chat.id}'),
                  chat: _chat,
                  me: me,
                  replyTo: _replyTo,
                  editing: _editing,
                  onCancelReply: () => setState(() => _replyTo = null),
                  onCancelEdit: () => setState(() => _editing = null),
                  onSendText: _onSendText,
                  onTyping: (t) => ChatService.instance.setTyping(_chat.id, me, t),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _messageList() {
    final locale = Localizations.localeOf(context).languageCode;
    return StreamBuilder<List<ChatMessage>>(
      stream: _messages,
      builder: (context, snap) {
        if (snap.hasError && _last.isEmpty) {
          return ErrorView(message: context.tr('messages_load_failed'), details: '${snap.error}');
        }
        if (snap.hasData) {
          _last = snap.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) => _markRead(_last));
        }
        if (!snap.hasData && _last.isEmpty) return const LoadingView();
        final messages = _last.where((m) => !m.hiddenFor.contains(me)).toList();

        return ValueListenableBuilder<Map<String, List<OutgoingMessage>>>(
          valueListenable: ChatService.instance.outbox,
          builder: (context, outbox, _) {
            final sent = messages.map((m) => m.id).toSet();
            final outgoing = (outbox[_chat.id] ?? const <OutgoingMessage>[])
                .where((o) => !sent.contains(o.id))
                .toList()
                .reversed
                .toList();
            if (messages.isEmpty && outgoing.isEmpty) {
              return EmptyState(icon: Icons.waving_hand_outlined, title: context.tr('say_hello'));
            }
            final total = outgoing.length + messages.length;
            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _loadMore();
                return false;
              },
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                itemCount: total,
                itemBuilder: (context, i) {
                  if (i < outgoing.length) return OutgoingBubble(item: outgoing[i]);
                  final idx = i - outgoing.length;
                  final m = messages[idx];
                  final older = idx + 1 < messages.length ? messages[idx + 1] : null;
                  final showDay = older == null || dayKey(older.createdAt) != dayKey(m.createdAt);
                  final showSender = _chat.isGroup &&
                      m.senderId != me &&
                      !m.isSystem &&
                      (older == null || older.senderId != m.senderId || older.isSystem || showDay);
                  return Column(
                    children: [
                      if (showDay) DayChip(label: formatDayHeader(m.createdAt, context.tr, locale)),
                      MessageBubble(
                        key: ValueKey(m.id),
                        message: m,
                        chat: _chat,
                        me: me,
                        showSender: showSender,
                        onLongPress: () => _messageMenu(m),
                        onSwipeReply: _chat.canSend(me) && !m.deleted && !m.isSystem
                            ? () => setState(() {
                                  _editing = null;
                                  _replyTo = _replyFor(m);
                                })
                            : null,
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
