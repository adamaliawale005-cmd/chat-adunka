import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/call_models.dart';
import '../../services/call_service.dart';
import '../../utils/time_format.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import 'start_call.dart';

/// Call history with missed calls highlighted.
class CallsTab extends StatefulWidget {
  final String me;
  final bool active;
  const CallsTab({super.key, required this.me, required this.active});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  late final Stream<List<CallLogEntry>> _history = CallService.instance.watchHistory(widget.me);

  String _statusLabel(BuildContext context, CallLogEntry e) {
    if (e.isMissed) return context.tr('missed_call');
    switch (e.status) {
      case 'answered':
        return e.durationSec > 0 ? formatDuration(Duration(seconds: e.durationSec)) : context.tr('answered');
      case 'rejected':
        return context.tr(e.incoming ? 'declined' : 'call_end_rejected');
      case 'busy':
        return context.tr('call_end_busy');
      case 'no_answer':
        return context.tr('call_end_no_answer');
      case 'cancelled':
        return context.tr('call_end_cancelled');
      default:
        return context.tr(e.incoming ? 'incoming' : 'outgoing');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return StreamBuilder<List<CallLogEntry>>(
      stream: _history,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(message: context.tr('calls_load_failed'), details: '${snap.error}');
        if (!snap.hasData) return const LoadingView();
        final entries = snap.data!;
        if (widget.active) {
          WidgetsBinding.instance.addPostFrameCallback((_) => CallService.instance.markHistorySeen(widget.me, entries));
        }
        return Column(
          children: [
            if (!AppConfig.turnConfigured)
              Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(context.tr('turn_missing_note')),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? EmptyState(icon: Icons.call_outlined, title: context.tr('no_calls'), message: context.tr('no_calls_message'))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final missed = e.isMissed;
                        final color = missed ? Theme.of(context).colorScheme.error : null;
                        return Dismissible(
                          key: ValueKey(e.callId),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Theme.of(context).colorScheme.errorContainer,
                            alignment: AlignmentDirectional.centerEnd,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: const Icon(Icons.delete_outline),
                          ),
                          onDismissed: (_) => CallService.instance.deleteHistoryEntry(widget.me, e.callId),
                          child: ListTile(
                            leading: UserAvatar(uid: e.peerId, radius: 24),
                            title: UserName(
                              uid: e.peerId,
                              deletedLabel: context.tr('deleted_account'),
                              style: TextStyle(color: color, fontWeight: missed && !e.seen ? FontWeight.bold : null),
                            ),
                            subtitle: Row(children: [
                              Icon(
                                e.incoming ? Icons.call_received : Icons.call_made,
                                size: 16,
                                color: color ?? Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${_statusLabel(context, e)} · ${formatListTime(e.createdAt, context.tr, locale)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                            trailing: IconButton(
                              tooltip: context.tr(e.kind == CallKind.video ? 'video_call' : 'voice_call'),
                              icon: Icon(e.kind == CallKind.video ? Icons.videocam_outlined : Icons.call_outlined),
                              onPressed: () => startCall(context, me: widget.me, peer: e.peerId, kind: e.kind),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
