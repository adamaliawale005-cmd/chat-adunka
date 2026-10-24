import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String? photoBase64;
  final String name;
  final double radius;

  const UserAvatar({
    super.key,
    required this.photoBase64,
    required this.name,
    this.radius = 22,
  });

  static final Map<String, Uint8List> _cache = {};

  static Uint8List? _decode(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    final key = '${b64.length}:${b64.hashCode}';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final bytes = base64Decode(b64);
      if (_cache.length > 200) _cache.clear();
      _cache[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(photoBase64);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.teal.shade100,
      foregroundColor: Colors.teal.shade900,
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(initial, style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.bold))
          : null,
    );
  }
}
