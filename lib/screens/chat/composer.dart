import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../services/attachment_service.dart';
import '../../utils/mime.dart';
import '../../utils/time_format.dart';
import '../../widgets/states.dart';
import 'emoji_panel.dart';
import 'message_bubble.dart';

/// Message input: text, emoji, attachments, voice notes, reply and edit.
class Composer extends StatefulWidget {
  final Chat chat;
  final String me;
  final ReplyInfo? replyTo;
  final ChatMessage? editing;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final Future<void> Function(String text) onSendText;
  final void Function(bool typing) onTyping;

  const Composer({
    super.key,
    required this.chat,
    required this.me,
    required this.replyTo,
    required this.editing,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.onSendText,
    required this.onTyping,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _emoji = false;
  bool _hasText = false;

  // Voice recording
  AudioRecorder? _recorder;
  DateTime? _recordStart;
  Timer? _recordTimer;
  Duration _recorded = Duration.zero;

  @override
  void didUpdateWidget(Composer old) {
    super.didUpdateWidget(old);
    if (widget.editing != null && widget.editing != old.editing) {
      _text.text = widget.editing!.text;
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
      _hasText = _text.text.trim().isNotEmpty;
      _focus.requestFocus();
    } else if (widget.editing == null && old.editing != null) {
      _text.clear();
      _hasText = false;
    }
    if (widget.replyTo != null && widget.replyTo != old.replyTo) _focus.requestFocus();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder?.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final has = v.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    widget.onTyping(has);
  }

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    _text.clear();
    setState(() => _hasText = false);
    widget.onTyping(false);
    await widget.onSendText(text);
  }

  void _insertEmoji(String e) {
    final sel = _text.selection;
    final t = _text.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _text.value = TextEditingValue(
      text: t.replaceRange(start, end, e),
      selection: TextSelection.collapsed(offset: start + e.length),
    );
    _onChanged(_text.text);
  }

  void _toggleEmoji() {
    setState(() => _emoji = !_emoji);
    if (_emoji) {
      _focus.unfocus();
    } else {
      _focus.requestFocus();
    }
  }

  // ---------- attachments ----------

  Future<void> _sendFile(MessageType type, File file, String name, {int? durationMs}) async {
    final reply = widget.replyTo;
    widget.onCancelReply();
    try {
      await AttachmentService.instance.sendFile(
        chat: widget.chat,
        senderId: widget.me,
        type: type,
        file: file,
        name: name,
        mime: mimeFromName(name, type),
        durationMs: durationMs,
        replyTo: reply,
      );
    } on AttachmentTooLargeException catch (e) {
      if (mounted) {
        showSnack(context, context.tr('file_too_large', {'limit': formatBytes(e.limit)}));
      }
    } on StorageNotEnabledException {
      if (mounted) showSnack(context, context.tr('storage_required'));
    } catch (_) {
      if (mounted) showSnack(context, context.tr('not_sent'));
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final big = AttachmentService.instance.storageEnabled;
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: big ? 2048 : 1280,
      maxHeight: big ? 2048 : 1280,
      imageQuality: big ? 80 : 68,
    );
    if (x == null) return;
    await _sendFile(MessageType.image, File(x.path), x.name);
  }

  Future<void> _pickVideo() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (x == null) return;
    await _sendFile(MessageType.video, File(x.path), x.name);
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles();
    final f = result?.files.single;
    if (f == null || f.path == null) return;
    await _sendFile(MessageType.file, File(f.path!), f.name);
  }

  void _attachMenu() {
    final storage = AttachmentService.instance.storageEnabled;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(ctx.tr('photo')),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(ctx.tr('camera')),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            enabled: storage,
            leading: const Icon(Icons.videocam_outlined),
            title: Text(ctx.tr('video')),
            subtitle: storage ? null : Text(ctx.tr('storage_required_short')),
            onTap: () {
              Navigator.pop(ctx);
              _pickVideo();
            },
          ),
          ListTile(
            enabled: storage,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(ctx.tr('document')),
            subtitle: storage ? null : Text(ctx.tr('storage_required_short')),
            onTap: () {
              Navigator.pop(ctx);
              _pickDocument();
            },
          ),
        ]),
      ),
    );
  }

  // ---------- voice notes ----------

  Future<void> _startRecording() async {
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        await rec.dispose();
        if (mounted) showSnack(context, context.tr('mic_permission_needed'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 22050, numChannels: 1),
        path: path,
      );
      setState(() {
        _recorder = rec;
        _recordStart = DateTime.now();
        _recorded = Duration.zero;
      });
      _recordTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _recordStart == null) return;
        final d = DateTime.now().difference(_recordStart!);
        setState(() => _recorded = d);
        if (d >= AppConfig.maxVoiceNote) _stopRecording(send: true);
      });
    } catch (_) {
      await rec.dispose();
      if (mounted) showSnack(context, context.tr('recording_failed'));
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    final rec = _recorder;
    if (rec == null) return;
    _recordTimer?.cancel();
    final duration = _recorded;
    setState(() {
      _recorder = null;
      _recordStart = null;
    });
    try {
      if (!send) {
        await rec.cancel();
        return;
      }
      final path = await rec.stop();
      if (path == null || duration < const Duration(milliseconds: 800)) return;
      await _sendFile(MessageType.audio, File(path), 'voice.m4a', durationMs: duration.inMilliseconds);
    } finally {
      await rec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recording = _recorder != null;
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.editing != null)
              _Bar(
                icon: Icons.edit,
                title: context.tr('editing_message'),
                text: widget.editing!.text,
                onClose: widget.onCancelEdit,
              )
            else if (widget.replyTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: ReplyQuote(reply: widget.replyTo!, me: widget.me, onClose: widget.onCancelReply),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: recording ? _recordingRow(theme) : _inputRow(theme),
            ),
            if (_emoji && !recording) SizedBox(height: 260, child: EmojiPanel(onPick: _insertEmoji)),
          ],
        ),
      ),
    );
  }

  Widget _inputRow(ThemeData theme) {
    final editing = widget.editing != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: context.tr('emoji'),
          icon: Icon(_emoji ? Icons.keyboard : Icons.emoji_emotions_outlined),
          onPressed: _toggleEmoji,
        ),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 1,
            maxLines: 6,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            onTap: () {
              if (_emoji) setState(() => _emoji = false);
            },
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: context.tr('message_hint'),
              counterText: '',
              filled: true,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (!editing)
          IconButton(
            tooltip: context.tr('attach'),
            icon: const Icon(Icons.attach_file),
            onPressed: _attachMenu,
          ),
        const SizedBox(width: 2),
        if (_hasText || editing)
          IconButton.filled(
            tooltip: context.tr(editing ? 'save' : 'send'),
            icon: Icon(editing ? Icons.check : Icons.send),
            onPressed: _send,
          )
        else
          IconButton.filled(
            tooltip: context.tr('record_voice'),
            icon: const Icon(Icons.mic),
            onPressed: _startRecording,
          ),
      ],
    );
  }

  Widget _recordingRow(ThemeData theme) {
    return Row(children: [
      IconButton(
        tooltip: context.tr('cancel'),
        icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
        onPressed: () => _stopRecording(send: false),
      ),
      const SizedBox(width: 8),
      Icon(Icons.fiber_manual_record, color: theme.colorScheme.error, size: 16),
      const SizedBox(width: 8),
      Text(formatDuration(_recorded), style: theme.textTheme.titleMedium),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          context.tr('recording_limit', {'minutes': AppConfig.maxVoiceNote.inMinutes}),
          style: theme.textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      IconButton.filled(
        tooltip: context.tr('send'),
        icon: const Icon(Icons.send),
        onPressed: () => _stopRecording(send: true),
      ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onClose;
  const _Bar({required this.icon, required this.title, required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 0, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ]),
    );
  }
}
