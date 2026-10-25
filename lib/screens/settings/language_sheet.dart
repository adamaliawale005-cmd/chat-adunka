import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_settings.dart';

Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final current = AppSettings.instance.locale?.languageCode ?? '';
      return SafeArea(
        child: RadioGroup<String>(
          groupValue: current,
          onChanged: (v) {
            AppSettings.instance
                .setLocale(v == null || v.isEmpty ? null : Locale(v));
            Navigator.pop(ctx);
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(ctx.tr('language'),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            RadioListTile<String>(
                value: '', title: Text(ctx.tr('system_default'))),
            for (final e in AppLocalizations.languageNames.entries)
              RadioListTile<String>(value: e.key, title: Text(e.value)),
          ]),
        ),
      );
    },
  );
}

Future<void> showThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: RadioGroup<ThemeMode>(
        groupValue: AppSettings.instance.themeMode,
        onChanged: (v) {
          if (v != null) AppSettings.instance.setThemeMode(v);
          Navigator.pop(ctx);
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(ctx.tr('theme'),
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          RadioListTile<ThemeMode>(
              value: ThemeMode.system, title: Text(ctx.tr('system_default'))),
          RadioListTile<ThemeMode>(
              value: ThemeMode.light, title: Text(ctx.tr('light'))),
          RadioListTile<ThemeMode>(
              value: ThemeMode.dark, title: Text(ctx.tr('dark'))),
        ]),
      ),
    ),
  );
}
