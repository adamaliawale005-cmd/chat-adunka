import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import 'auth/phone_entry_screen.dart';
import 'home_screen.dart';
import 'profile/profile_edit_screen.dart';

/// Signed out -> phone sign-in. Signed in without a profile -> profile
/// setup. Otherwise -> home.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      initialData: AuthService.instance.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const PhoneEntryScreen();
        return StreamBuilder<AppUser?>(
          key: ValueKey(user.uid),
          stream: UserService.instance.watchUser(user.uid),
          builder: (context, profileSnap) {
            if (profileSnap.hasError) {
              return _ErrorScreen(message: '${profileSnap.error}');
            }
            if (profileSnap.connectionState == ConnectionState.waiting &&
                !profileSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final profile = profileSnap.data;
            if (profile == null || !profile.hasProfile) {
              return ProfileEditScreen(
                uid: user.uid,
                phoneNumber: user.phoneNumber ?? '',
                existing: profile,
                isFirstSetup: true,
              );
            }
            return HomeScreen(me: profile);
          },
        );
      },
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Aduunka')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Could not load your profile.'),
            const SizedBox(height: 8),
            SelectableText(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => AuthService.instance.signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
