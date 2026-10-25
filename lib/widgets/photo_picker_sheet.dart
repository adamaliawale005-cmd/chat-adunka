import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../utils/image_utils.dart';
import 'states.dart';

/// Result of [showPhotoPickerSheet]: a new photo, a removal, or nothing.
class PhotoChoice {
  final String? base64;
  final bool removed;
  const PhotoChoice({this.base64, this.removed = false});
}

Future<PhotoChoice?> showPhotoPickerSheet(BuildContext context, {required bool hasPhoto}) async {
  final source = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(ctx.tr('choose_from_gallery')),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: Text(ctx.tr('take_photo')),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        if (hasPhoto)
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(ctx.tr('remove_photo')),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
      ]),
    ),
  );
  if (source == null) return null;
  if (source == 'remove') return const PhotoChoice(removed: true);
  try {
    final b64 = await pickProfilePhoto(source as ImageSource);
    return b64 == null ? null : PhotoChoice(base64: b64);
  } on PhotoTooLargeException {
    if (context.mounted) showSnack(context, context.tr('photo_too_large'));
  } catch (e) {
    if (context.mounted) showSnack(context, context.tr('photo_open_failed'));
  }
  return null;
}
