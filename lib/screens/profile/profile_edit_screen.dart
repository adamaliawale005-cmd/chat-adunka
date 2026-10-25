import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../config/firebase_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../widgets/photo_picker_sheet.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// First-time profile setup and later profile editing: name, unique
/// username, about text and picture.
class ProfileEditScreen extends StatefulWidget {
  final User authUser;
  final AppUser? existing;
  final bool isFirstSetup;

  const ProfileEditScreen(
      {super.key,
      required this.authUser,
      this.existing,
      this.isFirstSetup = false});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

enum _UsernameState { unknown, checking, available, taken, invalid }

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.displayName ?? '');
  late final TextEditingController _username =
      TextEditingController(text: widget.existing?.username ?? '');
  late final TextEditingController _about =
      TextEditingController(text: widget.existing?.about ?? '');
  late String? _photo = widget.existing?.photoBase64;
  bool _photoChanged = false;
  bool _saving = false;
  String? _error;
  _UsernameState _usernameState = _UsernameState.unknown;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (_username.text.isNotEmpty) _usernameState = _UsernameState.available;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _username.dispose();
    _about.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();
    final u = normalizeUsername(value);
    if (u.isEmpty) {
      setState(() => _usernameState = _UsernameState.unknown);
      return;
    }
    if (!usernamePattern.hasMatch(u)) {
      setState(() => _usernameState = _UsernameState.invalid);
      return;
    }
    setState(() => _usernameState = _UsernameState.checking);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final ok = await UserService.instance
            .isUsernameAvailable(u, forUid: widget.authUser.uid);
        if (!mounted || normalizeUsername(_username.text) != u) return;
        setState(() => _usernameState =
            ok ? _UsernameState.available : _UsernameState.taken);
      } catch (_) {
        if (mounted) setState(() => _usernameState = _UsernameState.unknown);
      }
    });
  }

  Future<void> _choosePhoto() async {
    final choice =
        await showPhotoPickerSheet(context, hasPhoto: _photo != null);
    if (choice == null) return;
    setState(() {
      _photo = choice.removed ? null : choice.base64;
      _photoChanged = true;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final username = normalizeUsername(_username.text);
    if (name.isEmpty || name.length > 50) {
      setState(() => _error = context.tr('err_name_required'));
      return;
    }
    if (!usernamePattern.hasMatch(username)) {
      setState(() => _error = context.tr('username_rules'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserService.instance.saveProfile(
        authUser: widget.authUser,
        displayName: name,
        username: username,
        about: _about.text,
        photoBase64: _photoChanged ? _photo : null,
        removePhoto: _photoChanged && _photo == null,
      );
      if (!mounted) return;
      if (!widget.isFirstSetup) Navigator.of(context).pop();
    } on UsernameTakenException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _usernameState = _UsernameState.taken;
        _error = context.tr('username_taken');
      });
    } on ProfileSaveException catch (e) {
      final outdated =
          e.permissionDenied && !await UserService.instance.rulesUpToDate();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = outdated
            ? context
                .tr('err_rules_outdated', {'project': FirebaseConfig.projectId})
            : '${context.tr('err_save_profile')}\n'
                '${context.tr('err_save_step', {
                    'step': e.step,
                    'code': e.code
                  })}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${context.tr('err_save_profile')} ($e)';
      });
    }
  }

  Widget? _usernameSuffix() {
    switch (_usernameState) {
      case _UsernameState.checking:
        return const Padding(
            padding: EdgeInsets.all(14), child: ButtonSpinner());
      case _UsernameState.available:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _UsernameState.taken:
      case _UsernameState.invalid:
        return Icon(Icons.error, color: Theme.of(context).colorScheme.error);
      case _UsernameState.unknown:
        return null;
    }
  }

  String? _usernameHelper() {
    switch (_usernameState) {
      case _UsernameState.taken:
        return context.tr('username_taken');
      case _UsernameState.invalid:
        return context.tr('username_rules');
      case _UsernameState.available:
        return context.tr('username_available');
      default:
        return context.tr('username_rules');
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.authUser.phoneNumber ?? widget.authUser.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(context
            .tr(widget.isFirstSetup ? 'create_profile' : 'edit_profile')),
        actions: [
          if (widget.isFirstSetup)
            TextButton(
              onPressed: _saving ? null : () => AuthService.instance.signOut(),
              child: Text(context.tr('sign_out'),
                  style: const TextStyle(color: Colors.white)),
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
                  Avatar(photoBase64: _photo, name: _name.text, radius: 56),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      tooltip: context.tr('change_photo'),
                      onPressed: _saving ? null : _choosePhoto,
                      icon: const Icon(Icons.camera_alt, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(child: Text(account, textDirection: TextDirection.ltr)),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              enabled: !_saving,
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: context.tr('your_name')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _username,
              enabled: !_saving,
              maxLength: 20,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.tr('username'),
                prefixText: '@',
                helperText: _usernameHelper(),
                helperMaxLines: 3,
                suffixIcon: _usernameSuffix(),
              ),
              onChanged: _onUsernameChanged,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _about,
              enabled: !_saving,
              maxLength: 140,
              decoration:
                  InputDecoration(labelText: context.tr('about_optional')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving || _usernameState == _UsernameState.taken
                  ? null
                  : _save,
              child: _saving
                  ? const ButtonSpinner()
                  : Text(context.tr(widget.isFirstSetup ? 'continue' : 'save')),
            ),
          ],
        ),
      ),
    );
  }
}
