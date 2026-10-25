import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/user_service.dart';
import 'states.dart';

const reportReasons = ['spam', 'harassment', 'inappropriate', 'impersonation', 'other'];

/// Lets the user report a person (and optionally a message). Reports are
/// write-only: nobody can read them from the app.
Future<void> showReportDialog(
  BuildContext context, {
  required String reporter,
  required String reported,
  String? chatId,
  String? messageId,
}) async {
  var reason = reportReasons.first;
  final details = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(ctx.tr('report_user')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RadioGroup<String>(
              groupValue: reason,
              onChanged: (v) => setState(() => reason = v ?? reason),
              child: Column(children: [
                for (final r in reportReasons)
                  RadioListTile<String>(value: r, title: Text(ctx.tr('reason_$r')), contentPadding: EdgeInsets.zero),
              ]),
            ),
            TextField(
              controller: details,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(labelText: ctx.tr('report_details_optional')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('report')),
          ),
        ],
      ),
    ),
  );
  final text = details.text;
  details.dispose();
  if (ok != true || !context.mounted) return;
  try {
    await UserService.instance.report(
      reporterId: reporter,
      reportedUid: reported,
      reason: reason,
      details: text,
      chatId: chatId,
      messageId: messageId,
    );
    if (context.mounted) showSnack(context, context.tr('report_sent'));
  } catch (_) {
    if (context.mounted) showSnack(context, context.tr('action_failed'));
  }
}
