import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../widgets/photo_picker_sheet.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';
import '../contacts/user_picker_screen.dart';

/// New group: choose members, then name and picture.
class CreateGroupScreen extends StatefulWidget {
  final String me;
  const CreateGroupScreen({super.key, required this.me});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<String> _members = [];
  String? _photo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickMembers());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickMembers() async {
    final picked =
        await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => UserPickerScreen(
        me: widget.me,
        title: context.tr('add_participants'),
        actionLabel: context.tr('next'),
      ),
    ));
    if (!mounted) return;
    if (picked == null && _members.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (picked != null)
      setState(() => _members = {..._members, ...picked}.toList());
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, context.tr('group_name_required'));
      return;
    }
    if (_members.isEmpty) {
      showSnack(context, context.tr('group_needs_members'));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ChatService.instance.createGroup(
        creator: widget.me,
        name: name,
        description: _description.text,
        memberIds: _members,
        photoBase64: _photo,
      );
      final chat = await ChatService.instance.getChat(id);
      if (!mounted) return;
      if (chat == null) {
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChatScreen(me: widget.me, chat: chat)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, context.tr('group_create_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('new_group'))),
      floatingActionButton: FloatingActionButton(
        onPressed: _saving ? null : _create,
        child: _saving ? const ButtonSpinner() : const Icon(Icons.check),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            GestureDetector(
              onTap: () async {
                final c = await showPhotoPickerSheet(context,
                    hasPhoto: _photo != null);
                if (c != null)
                  setState(() => _photo = c.removed ? null : c.base64);
              },
              child: Avatar(
                  photoBase64: _photo,
                  name: '',
                  radius: 32,
                  fallbackIcon: Icons.add_a_photo_outlined),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _name,
                maxLength: 60,
                decoration:
                    InputDecoration(labelText: context.tr('group_name')),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLength: 200,
            decoration: InputDecoration(
                labelText: context.tr('group_description_optional')),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(
                context.tr('participants_count', {'count': _members.length}),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
                onPressed: _pickMembers,
                icon: const Icon(Icons.person_add),
                label: Text(context.tr('add'))),
          ]),
          for (final uid in _members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(uid: uid),
              title: UserName(
                  uid: uid, deletedLabel: context.tr('deleted_account')),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _members.remove(uid)),
              ),
            ),
        ],
      ),
    );
  }
}
