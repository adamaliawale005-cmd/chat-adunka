import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../widgets/photo_picker_sheet.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';
import '../contacts/user_picker_screen.dart';
import '../profile/user_profile_screen.dart';

/// Group details: picture, name, description, members, admins and
/// permissions. Leave or delete the group.
class GroupInfoScreen extends StatefulWidget {
  final String me;
  final String chatId;
  const GroupInfoScreen({super.key, required this.me, required this.chatId});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final Stream<Chat?> _chat =
      ChatService.instance.watchChat(widget.chatId);
  bool _busy = false;

  String get me => widget.me;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) showSnack(context, context.tr('action_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editName(Chat chat) async {
    final name = TextEditingController(text: chat.name);
    final description = TextEditingController(text: chat.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('edit_group')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              maxLength: 60,
              decoration: InputDecoration(labelText: ctx.tr('group_name'))),
          TextField(
            controller: description,
            maxLength: 200,
            decoration: InputDecoration(
                labelText: ctx.tr('group_description_optional')),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('save'))),
        ],
      ),
    );
    final newName = name.text.trim();
    final newDescription = description.text.trim();
    name.dispose();
    description.dispose();
    if (ok != true || newName.isEmpty) return;
    await _run(() => ChatService.instance
        .updateGroupInfo(chat, me, name: newName, description: newDescription));
  }

  Future<void> _editPhoto(Chat chat) async {
    final c =
        await showPhotoPickerSheet(context, hasPhoto: chat.photoBase64 != null);
    if (c == null) return;
    await _run(() => ChatService.instance.updateGroupInfo(chat, me,
        photoBase64: c.base64, removePhoto: c.removed));
  }

  Future<void> _addMembers(Chat chat) async {
    final picked =
        await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => UserPickerScreen(
        me: me,
        title: context.tr('add_participants'),
        actionLabel: context.tr('add'),
        exclude: chat.members.toSet(),
      ),
    ));
    if (picked == null || picked.isEmpty) return;
    if (chat.members.length + picked.length > 256) {
      if (mounted) showSnack(context, context.tr('group_full'));
      return;
    }
    await _run(() => ChatService.instance.addMembers(chat, me, picked));
  }

  Future<void> _memberMenu(Chat chat, String uid) async {
    if (uid == me) return;
    final iAmAdmin = chat.isAdmin(me);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(ctx.tr('message')),
              onTap: () => Navigator.pop(ctx, 'message')),
          ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(ctx.tr('view_profile')),
              onTap: () => Navigator.pop(ctx, 'profile')),
          if (iAmAdmin)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(
                  ctx.tr(chat.isAdmin(uid) ? 'dismiss_admin' : 'make_admin')),
              onTap: () => Navigator.pop(ctx, 'admin'),
            ),
          if (iAmAdmin)
            ListTile(
              leading: Icon(Icons.person_remove_outlined,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(ctx.tr('remove_from_group')),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'message':
        await ChatScreen.openDirect(context, me, uid);
        break;
      case 'profile':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => UserProfileScreen(me: me, uid: uid)));
        break;
      case 'admin':
        await _run(() =>
            ChatService.instance.setAdmin(chat, me, uid, !chat.isAdmin(uid)));
        break;
      case 'remove':
        await _run(() => ChatService.instance.removeMember(chat, me, uid));
        break;
    }
  }

  Future<void> _leave(Chat chat) async {
    final ok = await confirm(
      context,
      title: context.tr('leave_group_q'),
      confirmLabel: context.tr('leave_group'),
      cancelLabel: context.tr('cancel'),
      destructive: true,
    );
    if (!ok) return;
    await _run(() => ChatService.instance.leaveGroup(chat, me));
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _delete(Chat chat) async {
    final ok = await confirm(
      context,
      title: context.tr('delete_group_q'),
      message: context.tr('delete_group_explanation'),
      confirmLabel: context.tr('delete'),
      cancelLabel: context.tr('cancel'),
      destructive: true,
    );
    if (!ok) return;
    await _run(() => ChatService.instance.deleteGroup(chat));
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('group_info'))),
      body: StreamBuilder<Chat?>(
        stream: _chat,
        builder: (context, snap) {
          if (snap.hasError)
            return ErrorView(
                message: context.tr('action_failed'), details: '${snap.error}');
          if (!snap.hasData) {
            return snap.connectionState == ConnectionState.active
                ? EmptyState(
                    icon: Icons.group_off_outlined,
                    title: context.tr('group_deleted'))
                : const LoadingView();
          }
          final chat = snap.data!;
          final member = chat.members.contains(me);
          final admin = chat.isAdmin(me);
          final canEdit = member && chat.canEditInfo(me);
          final members = [...chat.members]..sort((a, b) {
              if (a == me) return -1;
              if (b == me) return 1;
              final aa = chat.isAdmin(a) ? 0 : 1;
              final bb = chat.isAdmin(b) ? 0 : 1;
              return aa.compareTo(bb);
            });
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                Center(
                  child: GestureDetector(
                    onTap: canEdit ? () => _editPhoto(chat) : null,
                    child: Avatar(
                        photoBase64: chat.photoBase64,
                        name: chat.name,
                        radius: 56,
                        fallbackIcon: Icons.groups),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text(chat.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center),
                  subtitle: Text(
                    chat.description.isNotEmpty
                        ? chat.description
                        : context.tr(
                            'members_count', {'count': chat.members.length}),
                    textAlign: TextAlign.center,
                  ),
                  trailing: canEdit
                      ? IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editName(chat))
                      : null,
                ),
                if (admin) ...[
                  const Divider(),
                  SwitchListTile(
                    title: Text(context.tr('only_admins_send')),
                    value: chat.onlyAdminsCanSend,
                    onChanged: (v) => _run(() => ChatService.instance
                        .setGroupPermissions(chat, me, onlyAdminsCanSend: v)),
                  ),
                  SwitchListTile(
                    title: Text(context.tr('only_admins_edit')),
                    value: chat.onlyAdminsEditInfo,
                    onChanged: (v) => _run(() => ChatService.instance
                        .setGroupPermissions(chat, me, onlyAdminsEditInfo: v)),
                  ),
                ],
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    context.tr(
                        'participants_count', {'count': chat.members.length}),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (admin)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add)),
                    title: Text(context.tr('add_participants')),
                    onTap: () => _addMembers(chat),
                  ),
                for (final uid in members)
                  ListTile(
                    leading: UserAvatar(uid: uid),
                    title: uid == me
                        ? Text(context.tr('you'))
                        : UserName(
                            uid: uid,
                            deletedLabel: context.tr('deleted_account')),
                    trailing: chat.isAdmin(uid)
                        ? Chip(
                            label: Text(context.tr('admin')),
                            visualDensity: VisualDensity.compact)
                        : null,
                    onTap: () => _memberMenu(chat, uid),
                  ),
                const Divider(),
                if (member)
                  ListTile(
                    leading: Icon(Icons.exit_to_app,
                        color: Theme.of(context).colorScheme.error),
                    title: Text(context.tr('leave_group'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    onTap: () => _leave(chat),
                  ),
                if (admin)
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined,
                        color: Theme.of(context).colorScheme.error),
                    title: Text(context.tr('delete_group'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    onTap: () => _delete(chat),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
