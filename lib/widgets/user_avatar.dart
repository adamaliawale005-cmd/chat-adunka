import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/user_service.dart';

Uint8List? decodePhoto(String? b64) => _PhotoCache.decode(b64);

class _PhotoCache {
  static final Map<int, Uint8List> _cache = {};

  static Uint8List? decode(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    final key = Object.hash(b64.length, b64.hashCode);
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final bytes = base64Decode(b64);
      if (_cache.length > 300) _cache.clear();
      _cache[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

/// Round picture with the person's initial as a fallback.
class Avatar extends StatelessWidget {
  final String? photoBase64;
  final String name;
  final double radius;
  final IconData? fallbackIcon;
  final bool online;

  const Avatar({
    super.key,
    required this.photoBase64,
    required this.name,
    this.radius = 22,
    this.fallbackIcon,
    this.online = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = decodePhoto(photoBase64);
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? '' : trimmed.characters.first.toUpperCase();
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes != null
          ? null
          : (initial.isEmpty || fallbackIcon != null)
              ? Icon(fallbackIcon ?? Icons.person, size: radius)
              : Text(initial,
                  style: TextStyle(
                      fontSize: radius * 0.8, fontWeight: FontWeight.w600)),
    );
    if (!online) return avatar;
    return Stack(
      children: [
        avatar,
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: Container(
            width: radius * 0.55,
            height: radius * 0.55,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Avatar that loads a user's public profile by id.
class UserAvatar extends StatelessWidget {
  final String uid;
  final double radius;
  final bool showOnline;

  const UserAvatar(
      {super.key,
      required this.uid,
      this.radius = 22,
      this.showOnline = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser>(
      stream: UserService.instance.watchUser(uid),
      initialData: UserService.instance.cachedUser(uid),
      builder: (context, snap) {
        final u = snap.data;
        return Avatar(
          photoBase64: u?.photoBase64,
          name: u?.displayName ?? '',
          radius: radius,
          fallbackIcon:
              u != null && !u.exists ? Icons.person_off_outlined : null,
          online: showOnline && (u?.isOnlineNow ?? false),
        );
      },
    );
  }
}

/// Text that shows a user's display name by id.
class UserName extends StatelessWidget {
  final String uid;
  final TextStyle? style;
  final String Function(AppUser user)? format;
  final String deletedLabel;

  const UserName({
    super.key,
    required this.uid,
    required this.deletedLabel,
    this.style,
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser>(
      stream: UserService.instance.watchUser(uid),
      initialData: UserService.instance.cachedUser(uid),
      builder: (context, snap) {
        final u = snap.data;
        final text = u == null
            ? ''
            : !u.hasProfile
                ? deletedLabel
                : (format?.call(u) ?? u.displayName);
        return Text(text,
            style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
