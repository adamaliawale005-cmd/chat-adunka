import 'dart:io';

import 'package:chat_adunka/app.dart';
import 'package:chat_adunka/l10n/strings_ar.dart';
import 'package:chat_adunka/l10n/strings_en.dart';
import 'package:chat_adunka/l10n/strings_so.dart';
import 'package:chat_adunka/screens/welcome_screen.dart';
import 'package:chat_adunka/state/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppSettings.instance.setLocale(null));

  testWidgets(
      'welcome screen opens and leads to setup when Firebase is missing',
      (tester) async {
    await tester.pumpWidget(const AduChatApp());
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AduChat'), findsOneWidget);
    expect(find.text('Connect with people around the world'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Setup required'), findsOneWidget);
  });

  testWidgets('Arabic switches the layout to right-to-left', (tester) async {
    await AppSettings.instance.setLocale(const Locale('ar'));
    await tester.pumpWidget(const AduChatApp());
    await tester.pumpAndSettle();
    expect(find.text(stringsAr['welcome_title']!), findsOneWidget);
    final ctx = tester.element(find.byType(WelcomeScreen));
    expect(Directionality.of(ctx), TextDirection.rtl);
  });

  testWidgets('Somali texts load without missing Material localizations',
      (tester) async {
    await AppSettings.instance.setLocale(const Locale('so'));
    await tester.pumpWidget(const AduChatApp());
    await tester.pumpAndSettle();
    expect(find.text(stringsSo['welcome_title']!), findsOneWidget);
    final ctx = tester.element(find.byType(WelcomeScreen));
    expect(Directionality.of(ctx), TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  test('every language has exactly the same keys', () {
    expect(stringsSo.keys.toSet(), stringsEn.keys.toSet());
    expect(stringsAr.keys.toSet(), stringsEn.keys.toSet());
  });

  test('placeholders are kept in every translation', () {
    final placeholder = RegExp(r'\{[a-z]+\}');
    for (final key in stringsEn.keys) {
      final expected = placeholder
          .allMatches(stringsEn[key]!)
          .map((m) => m.group(0))
          .toSet();
      for (final table in [stringsSo, stringsAr]) {
        final actual =
            placeholder.allMatches(table[key]!).map((m) => m.group(0)).toSet();
        expect(actual, expected, reason: 'placeholders differ for "$key"');
      }
    }
  });

  test('every literal translation key used in the code exists', () {
    final keyPattern = RegExp(r"\btr\('([a-z0-9_]+)'");
    final missing = <String>{};
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in keyPattern.allMatches(f.readAsStringSync())) {
        if (!stringsEn.containsKey(m.group(1)))
          missing.add('${m.group(1)} (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });
}
