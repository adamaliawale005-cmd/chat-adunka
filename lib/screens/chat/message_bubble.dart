import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/chat_models.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/user_avatar.dart';
import 'attachment_views.dart';

/// Colour for a group member's name, stable per user.
Color senderColor(String uid, Brightness b) {
  const light = [
    Color(0xFF00796B),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFF1565C0),
    Color(0xFFEF6C00),
    Color(0xFF2E7D32)
  ];
  const dark = [
    Color(0xFF4DB6AC),
    Color(0xFFBA68C8),
    Color(0xFFE57373),
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFF81C784)
  ];
  final list = b == Brightness.dark ? dark : light;
  return list[uid.hashCode.abs() % list.length];
}

class DayChip extends StatelessWidget {
  final String label;
  const DayChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      );
}

class StatusTicks extends StatelessWidget {
  final MessageStatus status;
  const StatusTicks({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.chatColors;
    switch (status) {
      case MessageStatus.pending:
        return Icon(Icons.schedule, size: 14, color: colors.meta);
      case MessageStatus.failed:
        return Icon(Icons.error_outline,
            size: 15, color: Theme.of(context).colorScheme.error);
      case MessageStatus.sent:
        return Icon(Icons.done, size: 16, color: colors.meta);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 16, color: colors.meta);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 16, color: colors.readTick);
    }
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Chat chat;
  final String me;
  final bool showSender;
  final VoidCallback onLongPress;
  final VoidCallback? onSwipeReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.chat,
    required this.me,
    required this.showSender,
    required this.onLongPress,
    this.onSwipeReply,
  });

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.isSystem) return SystemMessageView(message: m, me: me);
    final mine = m.senderId == me;
    final colors = context.chatColors;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final textColor = mine ? colors.myText : colors.otherText;
    final status = chat.isGroup ? m.groupStatus(chat.members.length) : m.status;
    final maxWidth = MediaQuery.of(context).size.width * 0.8;

    final children = <Widget>[];
    if (showSender) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: UserName(
          uid: m.senderId,
          deletedLabel: context.tr('deleted_account'),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: senderColor(m.senderId, theme.brightness),
          ),
        ),
      ));
    }
    if (m.forwarded && !m.deleted) {
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shortcut, size: 14, color: colors.meta),
        const SizedBox(width: 4),
        Text(context.tr('forwarded'),
            style: TextStyle(
                fontSize: 12, fontStyle: FontStyle.italic, color: colors.meta)),
      ]));
    }
    if (m.replyTo != null && !m.deleted) {
      children.add(ReplyQuote(reply: m.replyTo!, me: me));
    }

    if (m.deleted) {
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 16, color: colors.meta),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            context.tr(mine ? 'you_deleted_message' : 'message_deleted'),
            style: TextStyle(fontStyle: FontStyle.italic, color: colors.meta),
          ),
        ),
      ]));
    } else {
      final a = m.attachment;
      if (a != null) {
        children.add(AttachmentView(message: m, attachment: a, mine: mine));
      }
      if (m.text.isNotEmpty) {
        children.add(Padding(
          padding: EdgeInsets.only(top: a != null ? 6 : 0),
          child: Text(m.text, style: TextStyle(fontSize: 16, color: textColor)),
        ));
      }
    }

    children.add(Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.edited && !m.deleted)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Text(context.tr('edited'),
                  style: TextStyle(fontSize: 11, color: colors.meta)),
            ),
          Text(formatMessageTime(m.createdAt, locale),
              style: TextStyle(fontSize: 11, color: colors.meta)),
          if (mine && !m.deleted) ...[
            const SizedBox(width: 4),
            StatusTicks(status: status)
          ],
        ],
      ),
    ));

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: mine ? colors.myBubble : colors.otherBubble,
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(16),
          topEnd: const Radius.circular(16),
          bottomStart: Radius.circular(mine ? 16 : 4),
          bottomEnd: Radius.circular(mine ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in children.take(children.length - 1))
            Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: c),
          children.last,
        ],
      ),
    );

    return GestureDetector(
      onLongPress: onLongPress,
      onHorizontalDragEnd: onSwipeReply == null
          ? null
          : (d) {
              final v = d.primaryVelocity ?? 0;
              final rtl = Directionality.of(context) == TextDirection.rtl;
              if ((rtl ? -v : v) > 300) onSwipeReply!();
            },
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: bubble,
      ),
    );
  }
}

/// Quoted message inside a reply.
class ReplyQuote extends StatelessWidget {
  final ReplyInfo reply;
  final String me;
  final VoidCallback? onClose;
  const ReplyQuote(
      {super.key, required this.reply, required this.me, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = senderColor(reply.senderId, theme.brightness);
    final icon = switch (reply.type) {
      MessageType.image => Icons.photo,
      MessageType.video => Icons.videocam,
      MessageType.audio => Icons.mic,
      MessageType.file => Icons.insert_drive_file,
      _ => null,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: BorderDirectional(start: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        mainAxisSize: onClose == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Flexible(
            fit: onClose == null ? FlexFit.loose : FlexFit.tight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                reply.senderId == me
                    ? Text(context.tr('you'),
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13))
                    : UserName(
                        uid: reply.senderId,
                        deletedLabel: context.tr('deleted_account'),
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14),
                    const SizedBox(width: 4)
                  ],
                  Flexible(
                    child: Text(
                      reply.text.isNotEmpty
                          ? reply.text
                          : context.tr('type_${reply.type.name}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
                icon: const Icon(Icons.close, size: 18), onPressed: onClose),
        ],
      ),
    );
  }
}

/// Group events such as "Amina added Yusuf".
class SystemMessageView extends StatefulWidget {
  final ChatMessage message;
  final String me;
  const SystemMessageView({super.key, required this.message, required this.me});

  @override
  State<SystemMessageView> createState() => _SystemMessageViewState();
}

class _SystemMessageViewState extends State<SystemMessageView> {
  Future<String>? _future;
  String? _forLocale;

  Future<String> _name(String uid) async {
    if (uid == widget.me) return context.tr('you');
    final u = await UserService.instance.getUser(uid);
    if (!mounted) return '';
    return u.hasProfile ? u.displayName : context.tr('deleted_account');
  }

  Future<String> _text() async {
    final parts = widget.message.text.split(':');
    final event = parts.first;
    final targets = parts.skip(1).toList();
    final actor = await _name(widget.message.senderId);
    if (!mounted) return '';
    if (event == 'renamed') {
      return context
          .tr('sys_renamed', {'actor': actor, 'name': targets.join(':')});
    }
    final names = <String>[];
    for (final t in targets) {
      names.add(await _name(t));
      if (!mounted) return '';
    }
    return context
        .tr('sys_$event', {'actor': actor, 'targets': names.join(', ')});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (_future == null || _forLocale != locale) {
      _forLocale = locale;
      _future = _text();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: FutureBuilder<String>(
            future: _future,
            builder: (context, snap) => Text(
              snap.data ?? '…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }
}

/// A message that is uploading or failed to send, with a retry button.
class OutgoingBubble extends StatelessWidget {
  final OutgoingMessage item;
  const OutgoingBubble({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.chatColors;
    final theme = Theme.of(context);
    final icon = switch (item.type) {
      MessageType.image => Icons.photo,
      MessageType.video => Icons.videocam,
      MessageType.audio => Icons.mic,
      MessageType.file => Icons.insert_drive_file,
      _ => Icons.chat_bubble_outline,
    };
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: colors.myBubble.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border:
              item.failed ? Border.all(color: theme.colorScheme.error) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: colors.myText),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(item.label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.myText))),
            ]),
            const SizedBox(height: 6),
            if (item.failed)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 4),
                Text(context.tr('not_sent'),
                    style: TextStyle(
                        color: theme.colorScheme.error, fontSize: 12)),
                TextButton(
                    onPressed: item.retry, child: Text(context.tr('retry'))),
              ])
            else if (item.progress != null)
              SizedBox(
                width: 160,
                child: LinearProgressIndicator(
                    value: item.progress == 0 ? null : item.progress),
              )
            else
              Icon(Icons.schedule, size: 14, color: colors.meta),
          ],
        ),
      ),
    );
  }
}

/// Name lookup helper for widgets that need plain text.
Future<String> displayNameOf(BuildContext context, String uid) async {
  final AppUser u = await UserService.instance.getUser(uid);
  if (!context.mounted) return '';
  return u.hasProfile ? u.displayName : context.tr('deleted_account');
}
