import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../widgets/states.dart';
import 'home_screen.dart';
import 'profile/profile_edit_screen.dart';
import 'splash_screen.dart';
import 'welcome_screen.dart';

/// Signed out -> welcome. Signed in without a profile -> profile setup.
/// Otherwise -> home.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      initialData: AuthService.instance.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const WelcomeScreen(firebaseReady: true);
        return StreamBuilder<AppUser>(
          key: ValueKey(user.uid),
          stream: UserService.instance.watchUserStrict(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.hasError) {
              return Scaffold(
                body: ErrorView(
                  message: context.tr('profile_load_failed'),
                  details: '${profileSnap.error}',
                  retryLabel: context.tr('sign_out'),
                  onRetry: () => AuthService.instance.signOut(),
                ),
              );
            }
            final profile = profileSnap.data;
            if (profile == null) return const SplashScreen();
            if (!profile.hasProfile) {
              return ProfileEditScreen(authUser: user, existing: null, isFirstSetup: true);
            }
            return HomeScreen(key: ValueKey('home-${user.uid}'), me: profile, authUser: user);
          },
        );
      },
    );
  }
}
