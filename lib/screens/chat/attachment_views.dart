import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../services/attachment_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/temp_files.dart';
import '../../utils/time_format.dart';
import '../../widgets/states.dart';

class AttachmentView extends StatelessWidget {
  final ChatMessage message;
  final Attachment attachment;
  final bool mine;
  const AttachmentView(
      {super.key,
      required this.message,
      required this.attachment,
      required this.mine});

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return InlineImage(chatId: message.chatId, attachment: attachment);
      case MessageType.audio:
        return AudioMessagePlayer(
            chatId: message.chatId, attachment: attachment, mine: mine);
      case MessageType.video:
        return FileTile(
          attachment: attachment,
          icon: Icons.play_circle_fill,
          onOpen: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(attachment: attachment),
          )),
        );
      default:
        return FileTile(
          attachment: attachment,
          icon: Icons.insert_drive_file,
          onOpen: () async {
            final url = await AttachmentService.instance.streamUrl(attachment);
            if (url == null) {
              if (context.mounted)
                showSnack(context, context.tr('attachment_unavailable'));
              return;
            }
            await launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication);
          },
        );
    }
  }
}

class InlineImage extends StatefulWidget {
  final String chatId;
  final Attachment attachment;
  const InlineImage(
      {super.key, required this.chatId, required this.attachment});

  @override
  State<InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<InlineImage> {
  late Future<Uint8List?> _bytes =
      AttachmentService.instance.load(widget.chatId, widget.attachment);

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    final ratio = (a.width != null && a.height != null && a.height! > 0)
        ? a.width! / a.height!
        : 1.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            maxWidth: 260, maxHeight: 320, minWidth: 120, minHeight: 80),
        child: AspectRatio(
          aspectRatio: ratio.clamp(0.5, 2.0),
          child: FutureBuilder<Uint8List?>(
            future: _bytes,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Container(
                  color: Colors.black12,
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final bytes = snap.data;
              if (bytes == null) {
                return InkWell(
                  onTap: () => setState(() => _bytes =
                      AttachmentService.instance.load(widget.chatId, a)),
                  child: Container(
                    color: Colors.black12,
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.broken_image_outlined),
                      Text(context.tr('tap_to_retry'),
                          style: const TextStyle(fontSize: 12)),
                    ])),
                  ),
                );
              }
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      ImageViewerScreen(bytes: bytes, title: a.name),
                )),
                child: Image.memory(bytes,
                    fit: BoxFit.cover, gaplessPlayback: true),
              );
            },
          ),
        ),
      ),
    );
  }
}

class ImageViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  final String title;
  const ImageViewerScreen(
      {super.key, required this.bytes, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: InteractiveViewer(
            minScale: 1, maxScale: 5, child: Image.memory(bytes)),
      ),
    );
  }
}

class AudioMessagePlayer extends StatefulWidget {
  final String chatId;
  final Attachment attachment;
  final bool mine;
  const AudioMessagePlayer(
      {super.key,
      required this.chatId,
      required this.attachment,
      required this.mine});

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  AudioPlayer? _player;
  final List<StreamSubscription> _subs = [];
  bool _loading = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    final ms = widget.attachment.durationMs;
    if (ms != null) _duration = Duration(milliseconds: ms);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_player != null) {
      if (_playing) {
        await _player!.pause();
      } else {
        await _player!.resume();
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final a = widget.attachment;
      final bytes = await AttachmentService.instance.load(widget.chatId, a);
      if (bytes == null) throw Exception('unavailable');
      // Phones play from a temporary file; browsers from in-memory data.
      final path =
          await writeTempFile('${a.blobId ?? a.storagePath.hashCode}_${a.name}', bytes);
      final Source source = path != null
          ? DeviceFileSource(path)
          : UrlSource('data:${a.mime};base64,${base64Encode(bytes)}');
      final p = AudioPlayer();
      _player = p;
      _subs.add(p.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }));
      _subs.add(p.onPositionChanged.listen((d) {
        if (mounted) setState(() => _position = d);
      }));
      _subs.add(p.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }));
      _subs.add(p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      }));
      await p.play(source);
    } catch (_) {
      if (mounted) showSnack(context, context.tr('attachment_unavailable'));
      _player?.dispose();
      _player = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.chatColors;
    final total = _duration ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : _position.inMilliseconds / total.inMilliseconds;
    return SizedBox(
      width: 230,
      child: Row(children: [
        IconButton(
          onPressed: _loading ? null : _toggle,
          icon: _loading
              ? const ButtonSpinner()
              : Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  size: 36),
        ),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
            const SizedBox(height: 4),
            Text(
              formatDuration(
                  _playing || _position > Duration.zero ? _position : total),
              style: TextStyle(fontSize: 11, color: colors.meta),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Icon(Icons.mic, size: 18, color: colors.meta),
      ]),
    );
  }
}

class FileTile extends StatelessWidget {
  final Attachment attachment;
  final IconData icon;
  final VoidCallback onOpen;
  const FileTile(
      {super.key,
      required this.attachment,
      required this.icon,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.chatColors;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(attachment.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(formatBytes(attachment.size),
                  style: TextStyle(fontSize: 11, color: colors.meta)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final Attachment attachment;
  const VideoPlayerScreen({super.key, required this.attachment});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final url = await AttachmentService.instance.streamUrl(widget.attachment);
    if (!mounted) return;
    if (url == null) {
      setState(() => _error = context.tr('attachment_unavailable'));
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      await c.dispose();
      if (mounted)
        setState(() => _error = context.tr('attachment_unavailable'));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.attachment.name,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white))
            : c == null
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () {
                      c.value.isPlaying ? c.pause() : c.play();
                      setState(() {});
                    },
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child:
                          Stack(alignment: Alignment.bottomCenter, children: [
                        VideoPlayer(c),
                        VideoProgressIndicator(c, allowScrubbing: true),
                      ]),
                    ),
                  ),
      ),
    );
  }
}
