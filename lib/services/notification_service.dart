import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../config/firebase_config.dart';

/// Handles messages that arrive while the app is in the background or
/// closed. Notification payloads are shown by Android automatically.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: FirebaseConfig.options);
  }
}

/// Firebase Cloud Messaging client setup.
///
/// Each device's token is saved privately under users/{uid}/devices/{token}.
/// Actually *sending* a push when a message is written needs a trusted
/// server (for example a Cloud Function, which requires the Blaze plan).
/// That sender is not part of this build; see docs/FIREBASE_SETUP.md.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  String? _uid;
  String? lastStatus;

  Future<void> start(String uid) async {
    if (_uid == uid) return;
    await stop();
    _uid = uid;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      lastStatus = settings.authorizationStatus.name;
      final token = await messaging.getToken();
      if (token != null) await _saveToken(uid, token);
      _tokenSub = messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
      _messageSub = FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('${n.title ?? 'New message'}: ${n.body ?? ''}')),
        );
      });
    } catch (e) {
      lastStatus = 'unavailable ($e)';
    }
  }

  Future<void> stop() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    _tokenSub = null;
    _messageSub = null;
    _uid = null;
  }

  /// Removes this device's token before signing out so the old account
  /// stops receiving notifications on it.
  Future<void> unregister(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(token)
            .delete();
      }
    } catch (_) {}
    await stop();
  }

  Future<void> _saveToken(String uid, String token) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(token)
        .set({
      'token': token,
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
