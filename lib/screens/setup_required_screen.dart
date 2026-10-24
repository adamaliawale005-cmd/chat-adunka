import 'package:flutter/material.dart';

class SetupRequiredScreen extends StatelessWidget {
  final Object? error;
  const SetupRequiredScreen({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup required')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.teal),
          const SizedBox(height: 16),
          Text(
            error == null
                ? 'This build of Chat Aduunka is not connected to Firebase yet.'
                : 'Firebase could not start with the settings in this build.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Sign-in, chats and notifications need a Firebase project. '
            'The project owner adds the Firebase settings as GitHub Actions '
            'secrets and runs a new build. See docs/FIREBASE_SETUP.md in the '
            'repository.',
            textAlign: TextAlign.center,
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            SelectableText('$error', style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
