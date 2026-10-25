import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/contacts_service.dart';
import '../../services/user_service.dart';
import '../../state/session.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';
import '../groups/create_group_screen.dart';
import '../profile/user_profile_screen.dart';
import 'people_search.dart';

/// Find people by username, name or phone number, and (optionally) see
/// which phone contacts use AduChat.
class ContactsTab extends StatefulWidget {
  final String me;
  final User authUser;
  const ContactsTab({super.key, required this.me, required this.authUser});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<String>? _results;
  bool _searching = false;
  List<ContactMatch> _matches = ContactsService.instance.cached();
  bool _syncing = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final r = await searchPeople(q,
            me: widget.me, myPhone: widget.authUser.phoneNumber);
        if (mounted && _search.text == q) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _sync() async {
    final settings = Session.settings.value;
    if (!settings.contactSync) {
      final ok = await confirm(
        context,
        title: context.tr('find_contacts_title'),
        message: context.tr('find_contacts_explanation'),
        confirmLabel: context.tr('allow'),
        cancelLabel: context.tr('not_now'),
      );
      if (!ok) return;
      await UserService.instance
          .updatePrivate(widget.authUser, settings.copyWith(contactSync: true));
    }
    setState(() => _syncing = true);
    try {
      final m = await ContactsService.instance
          .sync(myUid: widget.me, myPhone: widget.authUser.phoneNumber);
      if (mounted) setState(() => _matches = m);
      if (mounted && m.isEmpty)
        showSnack(context, context.tr('no_contacts_found'));
    } on ContactsPermissionDenied {
      if (mounted) showSnack(context, context.tr('contacts_permission_denied'));
    } catch (_) {
      if (mounted) showSnack(context, context.tr('action_failed'));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _openProfile(String uid) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UserProfileScreen(me: widget.me, uid: uid),
      ));

  Widget _personTile(String uid, {String? subtitle}) {
    return StreamBuilder<AppUser>(
      stream: UserService.instance.watchUser(uid),
      initialData: UserService.instance.cachedUser(uid),
      builder: (context, snap) {
        final u = snap.data;
        if (u != null && !u.hasProfile) return const SizedBox.shrink();
        return ListTile(
          leading: UserAvatar(uid: uid, showOnline: true),
          title: Text(u?.displayName ?? ''),
          subtitle: Text(
            subtitle ??
                (u?.username != null ? '@${u!.username}' : (u?.about ?? '')),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => ChatScreen.openDirect(context, widget.me, uid),
          trailing: IconButton(
            tooltip: context.tr('view_profile'),
            icon: const Icon(Icons.info_outline),
            onPressed: () => _openProfile(uid),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncEnabled = Session.settings.value.contactSync;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('search_people_hint'),
              isDense: true,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _onSearch('');
                      },
                    ),
            ),
            onChanged: _onSearch,
          ),
        ),
        Expanded(
          child: _results != null || _searching
              ? _searchResults()
              : ListView(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.group_add)),
                      title: Text(context.tr('new_group')),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CreateGroupScreen(me: widget.me),
                      )),
                    ),
                    ListTile(
                      leading: CircleAvatar(
                        child: _syncing
                            ? const ButtonSpinner()
                            : const Icon(Icons.contacts),
                      ),
                      title: Text(context.tr(syncEnabled
                          ? 'refresh_contacts'
                          : 'find_contacts_title')),
                      subtitle: Text(context.tr('find_contacts_subtitle')),
                      onTap: _syncing ? null : _sync,
                    ),
                    if (_matches.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(context.tr('contacts_on_aduchat'),
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final m in _matches)
                        _personTile(m.uid, subtitle: m.contactName),
                    ] else
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          context.tr('contacts_empty_hint'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _searchResults() {
    if (_searching && _results == null) return const LoadingView();
    final r = _results ?? const <String>[];
    if (r.isEmpty) {
      return EmptyState(
        icon: Icons.person_search_outlined,
        title: context.tr('no_people_found'),
        message: context.tr('no_people_found_message'),
      );
    }
    return ListView(children: [for (final uid in r) _personTile(uid)]);
  }
}
