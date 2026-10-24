import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../widgets/user_avatar.dart';

class ProfileEditScreen extends StatefulWidget {
  final String uid;
  final String phoneNumber;
  final AppUser? existing;
  final bool isFirstSetup;

  const ProfileEditScreen({
    super.key,
    required this.uid,
    required this.phoneNumber,
    this.existing,
    this.isFirstSetup = false,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  String? _photo;
  bool _photoChanged = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.displayName ?? '');
    _about = TextEditingController(text: widget.existing?.about ?? '');
    _photo = widget.existing?.photoBase64;
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 65,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 140000) {
        setState(() => _error = 'That picture is too large. Please choose another.');
        return;
      }
      setState(() {
        _photo = base64Encode(bytes);
        _photoChanged = true;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open the picture: $e');
    }
  }

  void _choosePhoto() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(ctx);
              _pickPhoto(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickPhoto(ImageSource.camera);
            },
          ),
          if (_photo != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _photo = null;
                  _photoChanged = true;
                });
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 50) {
      setState(() => _error = 'Enter a name (up to 50 characters).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserService.instance.saveProfile(
        uid: widget.uid,
        phoneNumber: widget.phoneNumber,
        displayName: name,
        about: _about.text,
        photoBase64: _photoChanged ? _photo : null,
        removePhoto: _photoChanged && _photo == null,
      );
      if (!mounted) return;
      if (!widget.isFirstSetup) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstSetup ? 'Create your profile' : 'Edit profile'),
        actions: [
          if (widget.isFirstSetup)
            TextButton(
              onPressed: _saving ? null : () => AuthService.instance.signOut(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Stack(
                children: [
                  UserAvatar(photoBase64: _photo, name: _name.text, radius: 56),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      onPressed: _saving ? null : _choosePhoto,
                      icon: const Icon(Icons.camera_alt, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(child: Text(widget.phoneNumber)),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              enabled: !_saving,
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Your name',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _about,
              enabled: !_saving,
              maxLength: 140,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'About (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.isFirstSetup ? 'Continue' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
