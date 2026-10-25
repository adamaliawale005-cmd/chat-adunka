import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../services/attachment_service.dart';
import '../../services/chat_service.dart';
import '../../state/session.dart';
import '../../widgets/chat_avatar.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// Pick one or more chats to forward a message to.
class ForwardScreen extends StatefulWidget {
  final String me;
  final ChatMessage message;
  const ForwardScreen({super.key, required this.me, required this.message});

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  late final Stream<List<Chat>> _chats = ChatService.instance.watchChats(widget.me);
  final Map<String, Chat> _selected = {};
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    var failed = 0;
    for (final chat in _selected.values) {
      try {
        await AttachmentService.instance.forward(widget.message, chat, widget.me);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    showSnack(context, failed == 0 ? context.tr('forwarded_done') : context.tr('forward_failed'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('forward_to'))),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _sending ? null : _send,
              icon: _sending ? const ButtonSpinner() : const Icon(Icons.send),
              label: Text(context.tr('send_to_count', {'count': _selected.length})),
            ),
      body: StreamBuilder<List<Chat>>(
        stream: _chats,
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final blocked = Session.blocked.value;
          final chats = snap.data!
              .where((c) => c.canSend(widget.me) && (c.isGroup || !blocked.contains(c.otherMember(widget.me))))
              .toList();
          if (chats.isEmpty) return EmptyState(icon: Icons.forum_outlined, title: context.tr('no_chats_title'));
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final c = chats[i];
              return CheckboxListTile(
                value: _selected.containsKey(c.id),
                onChanged: _sending
                    ? null
                    : (v) => setState(() => v == true ? _selected[c.id] = c : _selected.remove(c.id)),
                secondary: ChatAvatar(chat: c, me: widget.me),
                title: c.isGroup
                    ? Text(c.name)
                    : UserName(uid: c.otherMember(widget.me), deletedLabel: context.tr('deleted_account')),
              );
            },
          );
        },
      ),
    );
  }
}
