import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'screens/auth_gate.dart';
import 'screens/welcome_screen.dart';
import 'services/notification_service.dart';
import 'state/app_settings.dart';
import 'theme/app_theme.dart';

/// Root navigator, used to open chats and calls from notifications.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class AduChatApp extends StatelessWidget {
  final bool firebaseReady;
  final Object? firebaseError;

  const AduChatApp({super.key, this.firebaseReady = false, this.firebaseError});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        final signedIn = firebaseReady && FirebaseAuth.instance.currentUser != null;
        return MaterialApp(
          title: 'AduChat',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: NotificationService.instance.messengerKey,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          locale: settings.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          localeResolutionCallback: (device, supported) => AppLocalizations.resolve(device, supported),
          home: signedIn
              ? const AuthGate()
              : WelcomeScreen(firebaseReady: firebaseReady, firebaseError: firebaseError),
        );
      },
    );
  }
}
