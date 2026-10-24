import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../utils/time_format.dart';
import '../../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  final AppUser me;
  final AppUser other;
  const ChatScreen({super.key, required this.me, required this.other});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  late final String _chatId;
  late final Stream<List<ChatMessage>> _messages;
  final Set<String> _readRequested = {};

  @override
  void initState() {
    super.initState();
    _chatId = ChatService.chatIdFor(widget.me.uid, widget.other.uid);
    _messages = ChatService.instance.watchMessages(_chatId);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ChatService.instance
        .sendMessage(senderId: widget.me.uid, receiverId: widget.other.uid, text: text)
        .catchError((Object e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message not sent: $e')),
        );
      }
    });
  }

  void _markIncomingRead(List<ChatMessage> messages) {
    final unread = messages
        .where((m) =>
            m.receiverId == widget.me.uid &&
            (m.status == MessageStatus.sent || m.status == MessageStatus.delivered) &&
            !_readRequested.contains(m.id))
        .toList();
    if (unread.isEmpty) return;
    _readRequested.addAll(unread.map((m) => m.id));
    ChatService.instance.markRead(unread);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: StreamBuilder<AppUser?>(
          stream: UserService.instance.watchUser(widget.other.uid),
          initialData: widget.other,
          builder: (context, snap) {
            final u = snap.data ?? widget.other;
            return Row(children: [
              UserAvatar(photoBase64: u.photoBase64, name: u.displayName, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (u.lastSeen != null)
                      Text(formatLastSeen(u.lastSeen),
                          style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
            ]);
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _messages,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load messages: ${snap.error}',
                          textAlign: TextAlign.center),
                    ));
                  }
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final messages = snap.data!;
                  WidgetsBinding.instance.addPostFrameCallback((_) => _markIncomingRead(messages));
                  if (messages.isEmpty) {
                    return Center(child: Text('Say hello to ${widget.other.displayName} 👋'));
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      final older = i + 1 < messages.length ? messages[i + 1] : null;
                      final showDay = older == null ||
                          formatDayHeader(older.createdAt) != formatDayHeader(m.createdAt);
                      return Column(children: [
                        if (showDay) _DayChip(label: formatDayHeader(m.createdAt)),
                        _Bubble(message: m, mine: m.senderId == widget.me.uid),
                      ]);
                    },
                  );
                },
              ),
            ),
            _Composer(controller: _input, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  const _DayChip({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Chip(label: Text(label, style: const TextStyle(fontSize: 12))),
      );
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  const _Bubble({required this.message, required this.mine});

  Widget _statusIcon() {
    switch (message.status) {
      case MessageStatus.pending:
        return const Icon(Icons.schedule, size: 14, color: Colors.black45);
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 16, color: Colors.black45);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 16, color: Colors.black45);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 16, color: Colors.blue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
          decoration: BoxDecoration(
            color: mine ? Colors.teal.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 2),
              bottomRight: Radius.circular(mine ? 2 : 14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(message.text, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatMessageTime(message.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  if (mine) ...[const SizedBox(width: 4), _statusIcon()],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _Composer({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message',
                counterText: '',
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send)),
        ],
      ),
    );
  }
}
