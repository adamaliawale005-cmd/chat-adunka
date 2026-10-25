import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shown while the session and profile load (continues the Android splash).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aduTeal,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/branding/logo_foreground.png', width: 160, height: 160),
            const Text(
              'AduChat',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
