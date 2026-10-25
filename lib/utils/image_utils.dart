import 'dart:convert';

import 'package:image_picker/image_picker.dart';

/// Picks a profile or group picture, resized so it can be stored inside a
/// Firestore document (no Cloud Storage needed). Returns base64 or null.
Future<String?> pickProfilePhoto(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 320,
    maxHeight: 320,
    imageQuality: 70,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > 140000) {
    throw const PhotoTooLargeException();
  }
  return base64Encode(bytes);
}

class PhotoTooLargeException implements Exception {
  const PhotoTooLargeException();
}
