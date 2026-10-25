import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/user_service.dart';
import '../../state/session.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import 'people_search.dart';

/// Select several people: from recent chats, phone contacts on AduChat or
/// search. Returns the chosen user ids.
class UserPickerScreen extends StatefulWidget {
  final String me;
  final String title;
  final String actionLabel;
  final Set<String> exclude;
  const UserPickerScreen({
    super.key,
    required this.me,
    required this.title,
    required this.actionLabel,
    this.exclude = const {},
  });

  @override
  State<UserPickerScreen> createState() => _UserPickerScreenState();
}

class _UserPickerScreenState extends State<UserPickerScreen> {
  final Set<String> _selected = {};
  final _search = TextEditingController();
  Timer? _debounce;
  List<String>? _results;
  late final Stream<List<Chat>> _chats =
      ChatService.instance.watchChats(widget.me);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final r = await searchPeople(q, me: widget.me);
      if (mounted && _search.text == q) setState(() => _results = r);
    });
  }

  Widget _tile(String uid) {
    return StreamBuilder<AppUser>(
      stream: UserService.instance.watchUser(uid),
      initialData: UserService.instance.cachedUser(uid),
      builder: (context, snap) {
        final u = snap.data;
        if (u != null && !u.hasProfile) return const SizedBox.shrink();
        return CheckboxListTile(
          value: _selected.contains(uid),
          onChanged: (v) => setState(
              () => v == true ? _selected.add(uid) : _selected.remove(uid)),
          secondary: UserAvatar(uid: uid),
          title: Text(u?.displayName ?? ''),
          subtitle: u?.username == null ? null : Text('@${u!.username}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = Session.blocked.value;
    bool allowed(String uid) =>
        uid != widget.me &&
        !widget.exclude.contains(uid) &&
        !blocked.contains(uid);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).pop(_selected.toList()),
              icon: const Icon(Icons.check),
              label: Text('${widget.actionLabel} (${_selected.length})'),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('search_people_hint'),
              isDense: true,
            ),
            onChanged: _onSearch,
          ),
        ),
        Expanded(
          child: _results != null
              ? (_results!.where(allowed).isEmpty
                  ? EmptyState(
                      icon: Icons.person_search_outlined,
                      title: context.tr('no_people_found'))
                  : ListView(children: [
                      for (final uid in _results!.where(allowed)) _tile(uid)
                    ]))
              : StreamBuilder<List<Chat>>(
                  stream: _chats,
                  builder: (context, snap) {
                    final ids = <String>{
                      for (final c in snap.data ?? const <Chat>[])
                        if (!c.isGroup) c.otherMember(widget.me),
                      for (final m in ContactsService.instance.cached()) m.uid,
                      ..._selected,
                    }.where(allowed).toList();
                    if (ids.isEmpty) {
                      return EmptyState(
                        icon: Icons.people_outline,
                        title: context.tr('picker_empty'),
                        message: context.tr('picker_empty_message'),
                      );
                    }
                    return ListView(
                        children: [for (final uid in ids) _tile(uid)]);
                  },
                ),
        ),
      ]),
    );
  }
}
