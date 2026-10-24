import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/user_service.dart';
import '../widgets/user_avatar.dart';
import 'chat/chat_screen.dart';

/// Directory of registered Chat Aduunka users, searchable by name or number.
class DirectoryView extends StatefulWidget {
  final AppUser me;
  const DirectoryView({super.key, required this.me});

  @override
  State<DirectoryView> createState() => _DirectoryViewState();
}

class _DirectoryViewState extends State<DirectoryView> {
  final _search = TextEditingController();
  late final Stream<List<AppUser>> _users;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _users = UserService.instance.watchDirectory();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(AppUser u) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    if (u.displayName.toLowerCase().contains(q)) return true;
    if (digits.length >= 3 && u.phoneNumber.replaceAll('+', '').contains(digits)) return true;
    return false;
  }

  void _open(AppUser other) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(me: widget.me, other: other),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search by name or phone number',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<AppUser>>(
            stream: _users,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load contacts: ${snap.error}', textAlign: TextAlign.center),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final users = snap.data!
                  .where((u) => u.uid != widget.me.uid)
                  .where(_matches)
                  .toList();
              if (users.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _query.isEmpty
                          ? 'No other users yet.\nInvite a friend to install Chat Aduunka.'
                          : 'No one matches "$_query".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, i) {
                  final u = users[i];
                  return ListTile(
                    leading: UserAvatar(photoBase64: u.photoBase64, name: u.displayName),
                    title: Text(u.displayName),
                    subtitle: Text(u.about.isNotEmpty ? u.about : u.phoneNumber,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chat_bubble_outline),
                    onTap: () => _open(u),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
