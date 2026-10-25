import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../utils/time_format.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// Searches the text of the latest 500 messages in a conversation.
class MessageSearchScreen extends StatefulWidget {
  final String me;
  final Chat chat;
  const MessageSearchScreen({super.key, required this.me, required this.chat});

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ChatMessage>? _results;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (q.trim().isEmpty) {
        setState(() => _results = null);
        return;
      }
      setState(() => _loading = true);
      try {
        final r = await ChatService.instance.search(widget.chat.id, q, widget.me);
        if (mounted && _query.text == q) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: context.tr('search_messages'),
            hintStyle: const TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _results == null
              ? EmptyState(icon: Icons.search, title: context.tr('search_messages_hint'))
              : _results!.isEmpty
                  ? EmptyState(icon: Icons.search_off, title: context.tr('no_results'))
                  : ListView.separated(
                      itemCount: _results!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = _results![i];
                        return ListTile(
                          leading: UserAvatar(uid: m.senderId, radius: 18),
                          title: m.senderId == widget.me
                              ? Text(context.tr('you'))
                              : UserName(uid: m.senderId, deletedLabel: context.tr('deleted_account')),
                          subtitle: Text(
                            m.text.isNotEmpty ? m.text : (m.attachment?.name ?? ''),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            formatListTime(m.createdAt, context.tr, locale),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
    );
  }
}
