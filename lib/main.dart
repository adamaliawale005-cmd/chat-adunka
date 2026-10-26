import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'config/firebase_config.dart';
import 'services/notification_service.dart';
import 'state/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();

  Object? firebaseError;
  if (FirebaseConfig.isConfigured) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      // Offline cache: messages sent offline are delivered when back online.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024,
      );
      if (FirebaseConfig.useEmulator) {
        // Automated tests only: local emulators, never real data.
        await FirebaseAuth.instance
            .useAuthEmulator(FirebaseConfig.emulatorHost, 9099);
        FirebaseFirestore.instance
            .useFirestoreEmulator(FirebaseConfig.emulatorHost, 8080);
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      // Diagnostic only: the project id is not a secret; keys are never logged.
      debugPrint('AduChat: Firebase project ${FirebaseConfig.projectId} '
          '(${FirebaseConfig.source})');
    } catch (e) {
      firebaseError = e;
    }
  }

  runApp(AduChatApp(
    firebaseReady: FirebaseConfig.isConfigured && firebaseError == null,
    firebaseError: firebaseError,
  ));
}
