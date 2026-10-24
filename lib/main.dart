import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'config/firebase_config.dart';
import 'screens/auth_gate.dart';
import 'screens/setup_required_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? firebaseError;
  if (FirebaseConfig.isConfigured) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      firebaseError = e;
    }
  }
  runApp(ChatAdunka(
    firebaseReady: FirebaseConfig.isConfigured && firebaseError == null,
    firebaseError: firebaseError,
  ));
}

class ChatAdunka extends StatelessWidget {
  final bool firebaseReady;
  final Object? firebaseError;

  const ChatAdunka({super.key, this.firebaseReady = false, this.firebaseError});

  @override
  Widget build(BuildContext context) {
    final signedIn = firebaseReady && FirebaseAuth.instance.currentUser != null;
    return MaterialApp(
      title: 'Chat Aduunka',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: NotificationService.instance.messengerKey,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: signedIn
          ? const AuthGate()
          : WelcomeScreen(firebaseReady: firebaseReady, firebaseError: firebaseError),
    );
  }
}

/// The original Chat Aduunka welcome screen, now with a "Get started" button.
class WelcomeScreen extends StatelessWidget {
  final bool firebaseReady;
  final Object? firebaseError;

  const WelcomeScreen({super.key, required this.firebaseReady, this.firebaseError});

  void _start(BuildContext context) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => firebaseReady
          ? const AuthGate()
          : SetupRequiredScreen(error: firebaseError),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Aduunka'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble,
              size: 90,
              color: Colors.teal,
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome to Chat Aduunka',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Connect with people around the world'),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _start(context),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Get started'),
            ),
          ],
        ),
      ),
    );
  }
}
