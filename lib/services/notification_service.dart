import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/firebase_config.dart';
import '../models/app_user.dart';
import '../models/chat_models.dart';
import 'chat_service.dart';
import 'user_service.dart';

const _messagesChannel = AndroidNotificationChannel(
  'messages',
  'Messages',
  description: 'New chat and group messages',
  importance: Importance.high,
);

const _callsChannel = AndroidNotificationChannel(
  'calls',
  'Calls',
  description: 'Incoming and missed calls',
  importance: Importance.max,
);

final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocal({void Function(NotificationResponse)? onTap}) async {
  await _local.initialize(
    const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification')),
    onDidReceiveNotificationResponse: onTap,
  );
  final android = _local.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(_messagesChannel);
  await android?.createNotificationChannel(_callsChannel);
}

NotificationDetails _details(AndroidNotificationChannel channel) =>
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: Priority.high,
        icon: 'ic_notification',
        color: const Color(0xFF00897B),
        category: channel.id == 'calls'
            ? AndroidNotificationCategory.call
            : AndroidNotificationCategory.message,
      ),
    );

/// Handles push messages while the app is in the background or closed.
/// Messages with a "notification" part are shown by Android itself; call
/// invitations are data-only and are shown here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: FirebaseConfig.options);
  }
  final data = message.data;
  if (data['type'] == 'call' && message.notification == null) {
    await _initLocal();
    await _local.show(
      data['callId'].hashCode,
      data['title'] ?? 'AduChat',
      data['body'] ?? 'Incoming call',
      _details(_callsChannel),
      payload: 'call:${data['callId'] ?? ''}',
    );
  }
}

/// Push notifications (Firebase Cloud Messaging) and local notifications.
///
/// * Device tokens are saved privately in users/{uid}/devices/{token}.
/// * While the app is running, new messages from Firestore are shown as
///   local notifications (works on the free plan).
/// * When the app is closed, notifications need the Cloud Functions in
///   /functions (Blaze plan) to send pushes to the saved tokens.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Opens a chat or call from a tapped notification ("chat:<id>" / "call:<id>").
  void Function(String payload)? onOpen;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<RemoteMessage>? _openSub;
  String? _uid;
  bool _localReady = false;
  String? _pendingPayload;

  AuthorizationStatus? permission;
  AccountPrivate prefs = AccountPrivate.defaults;

  Future<void> _ensureLocal() async {
    if (_localReady) return;
    try {
      await _initLocal(onTap: (r) => _open(r.payload));
      _localReady = true;
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _open(launch?.notificationResponse?.payload);
      }
    } catch (_) {
      // Local notifications unavailable; ignore.
    }
  }

  void _open(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (onOpen == null) {
      _pendingPayload = payload;
    } else {
      onOpen!(payload);
    }
  }

  /// Called by the home screen once it can navigate.
  void attach(void Function(String payload) handler) {
    onOpen = handler;
    final p = _pendingPayload;
    _pendingPayload = null;
    if (p != null) handler(p);
  }

  Future<void> start(String uid) async {
    if (_uid == uid) return;
    await stop();
    _uid = uid;
    await _ensureLocal();
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      permission = settings.authorizationStatus;
      final token = await messaging.getToken();
      if (token != null) await _saveToken(uid, token);
      _tokenSub = messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
      _fgSub = FirebaseMessaging.onMessage.listen(_onForegroundPush);
      _openSub = FirebaseMessaging.onMessageOpenedApp
          .listen((m) => _open(_payloadOf(m)));
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(_payloadOf(initial));
    } catch (_) {
      permission = null;
    }
  }

  Future<void> stop() async {
    await _tokenSub?.cancel();
    await _fgSub?.cancel();
    await _openSub?.cancel();
    _tokenSub = null;
    _fgSub = null;
    _openSub = null;
    _uid = null;
    _known.clear();
  }

  /// Removes this phone's token so a signed-out account stops getting pushes.
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
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    await stop();
  }

  Future<void> _saveToken(String uid, String token) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(token)
          .set({
        'token': token,
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp()
      });

  String? _payloadOf(RemoteMessage m) {
    final d = m.data;
    if (d['chatId'] != null) return 'chat:${d['chatId']}';
    if (d['callId'] != null) return 'call:${d['callId']}';
    return null;
  }

  void _onForegroundPush(RemoteMessage m) {
    final chatId = m.data['chatId'];
    // The in-app listener already shows message notifications while the
    // app is open; only show pushes it cannot know about.
    if (chatId != null) return;
    final n = m.notification;
    if (n == null) return;
    showLocal(
        title: n.title ?? 'AduChat',
        body: n.body ?? '',
        payload: _payloadOf(m),
        call: m.data['type'] == 'call');
  }

  Future<void> showLocal(
      {required String title,
      required String body,
      String? payload,
      bool call = false}) async {
    await _ensureLocal();
    if (!_localReady) return;
    try {
      await _local.show(
        (payload ?? title).hashCode & 0x7fffffff,
        title,
        body,
        _details(call ? _callsChannel : _messagesChannel),
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> cancelFor(String payload) async {
    if (!_localReady) return;
    try {
      await _local.cancel(payload.hashCode & 0x7fffffff);
    } catch (_) {}
  }

  // ---------- in-app message notifications ----------

  final Map<String, String> _known = {};

  /// Compares the chat list with the previous snapshot and notifies about
  /// new messages from other people in chats that are not open.
  Future<void> onChatsChanged(String me, List<Chat> chats,
      {required String Function(String key) tr}) async {
    final first = _known.isEmpty;
    for (final c in chats) {
      final previous = _known[c.id];
      final marker = '${c.lastMessageAt?.millisecondsSinceEpoch}';
      _known[c.id] = marker;
      if (first ||
          previous == marker ||
          previous == null && c.unreadFor(me) == 0) continue;
      if (c.lastSenderId == me ||
          c.lastSenderId.isEmpty ||
          c.lastMessageType == 'system') continue;
      if (c.unreadFor(me) == 0) continue;
      if (ChatService.instance.openChats.contains(c.id)) continue;
      if (c.isGroup ? !prefs.notifyGroups : !prefs.notifyMessages) continue;
      final sender = await UserService.instance.getUser(c.lastSenderId);
      final senderName =
          sender.hasProfile ? sender.displayName : tr('deleted_account');
      final body = prefs.notificationPreview
          ? c.lastMessage
          : tr('notification_hidden_preview');
      await showLocal(
        title: c.isGroup ? c.name : senderName,
        body: c.isGroup ? '$senderName: $body' : body,
        payload: 'chat:${c.id}',
      );
    }
  }
}
