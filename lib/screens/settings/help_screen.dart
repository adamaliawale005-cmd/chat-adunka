import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/firebase_config.dart';
import '../../l10n/app_localizations.dart';

/// Frequently asked questions, what the app does and does not protect,
/// and licences.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const appVersion = '2.0.0';

  @override
  Widget build(BuildContext context) {
    final faqs = [
      'faq_find',
      'faq_group',
      'faq_calls',
      'faq_files',
      'faq_notifications',
      'faq_delete'
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('help'))),
      body: ListView(
        children: [
          for (final f in faqs)
            ExpansionTile(
              title: Text(context.tr('${f}_q')),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(context.tr('${f}_a'))],
            ),
          ExpansionTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(context.tr('security_title')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(context.tr('security_body'))],
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.tr('about_app')),
            subtitle: Text('${AppConfig.appName} $appVersion\n'
                'Firebase: ${FirebaseConfig.projectId}'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(context.tr('licenses')),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: appVersion,
            ),
          ),
        ],
      ),
    );
  }
}
