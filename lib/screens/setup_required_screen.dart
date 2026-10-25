import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Shown when this build has no Firebase settings.
class SetupRequiredScreen extends StatelessWidget {
  final Object? error;
  const SetupRequiredScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('setup_required'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.cloud_off, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            context.tr(error == null ? 'setup_not_connected' : 'setup_failed'),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(context.tr('setup_explanation'), textAlign: TextAlign.center),
          if (error != null) ...[
            const SizedBox(height: 16),
            SelectableText('$error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
