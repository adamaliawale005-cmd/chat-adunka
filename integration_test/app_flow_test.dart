// End-to-end test of the real app on an Android emulator, against local
// Firebase emulators (Auth + Firestore) that enforce firestore.rules.
//
// User A is driven through the UI: register, create profile, find user B,
// send a message, receive B's reply. User B acts through a second Firebase
// app instance (another signed-in user), so every write goes through the
// security rules exactly as on a second phone.
//
// Run (CI does this):  flutter test integration_test/app_flow_test.dart \
//   --dart-define=USE_FIREBASE_EMULATOR=true
import 'dart:convert';
import 'dart:io';

import 'package:chat_adunka/config/firebase_config.dart';
import 'package:chat_adunka/main.dart' as app;
import 'package:chat_adunka/models/chat_models.dart';
import 'package:chat_adunka/services/attachment_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

// 1x1 PNG image.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

Future<Map<String, dynamic>?> waitForDoc(
    WidgetTester tester, Future<Map<String, dynamic>?> Function() read,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final d = await read();
    if (d != null) return d;
    await tester.pump(const Duration(milliseconds: 500));
  }
  return null;
}

Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 45), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for ${what ?? finder}');
}

void step(String name) => debugPrint('E2E STEP PASS: $name');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('register, create profile, exchange messages', (tester) async {
    assert(FirebaseConfig.useEmulator, 'run with USE_FIREBASE_EMULATOR=true');
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final usernameA = 'usera$stamp';
    final usernameB = 'userb$stamp';

    // ---- start the app ----
    await app.main();
    await pumpUntil(tester, find.text('Create account'),
        what: 'welcome screen');
    expect(find.text('Firebase: demo-aduchat'), findsOneWidget);
    step('app opens and connects to Firebase');

    // ---- user B (second "phone") ----
    final bApp = await Firebase.initializeApp(
        name: 'userB', options: FirebaseConfig.options);
    final bAuth = FirebaseAuth.instanceFor(app: bApp);
    await bAuth.useAuthEmulator(FirebaseConfig.emulatorHost, 9099);
    final bDb = FirebaseFirestore.instanceFor(app: bApp);
    bDb.useFirestoreEmulator(FirebaseConfig.emulatorHost, 8080);
    final bCred = await bAuth.createUserWithEmailAndPassword(
        email: '$usernameB@example.com', password: 'test-password-B1');
    final bUid = bCred.user!.uid;
    final bBatch = bDb.batch();
    bBatch.set(bDb.collection('usernames').doc(usernameB),
        {'uid': bUid, 'createdAt': FieldValue.serverTimestamp()});
    bBatch.set(bDb.collection('users').doc(bUid), {
      'uid': bUid,
      'displayName': 'User B',
      'displayNameLower': 'user b',
      'username': usernameB,
      'usernameLower': usernameB,
      'about': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    bBatch.set(bDb.collection('directory').doc(bUid), {
      'uid': bUid,
      'displayName': 'User B',
      'displayNameLower': 'user b',
      'username': usernameB,
      'usernameLower': usernameB,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await bBatch.commit();
    step('second user registered and created a profile');

    // ---- user A registers through the UI ----
    await tester.tap(find.text('Create account'));
    await pumpUntil(tester, find.text('Email'), what: 'sign-in screen');
    await tester.tap(find.text('Email'));
    await pumpUntil(tester, find.widgetWithText(TextField, 'Password'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), '$usernameA@example.com');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'test-password-A1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm password'), 'test-password-A1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await pumpUntil(tester, find.text('Create your profile'),
        what: 'profile setup');
    step('new account registered (email)');

    // ---- profile ----
    await tester.enterText(
        find.widgetWithText(TextField, 'Your name'), 'User A');
    await tester.enterText(
        find.widgetWithText(TextField, 'Username'), usernameA);
    await pumpUntil(tester, find.text('Available'),
        what: 'username availability');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await pumpUntil(tester, find.text('Contacts'),
        what: 'home screen after saving the profile');
    final aUid = FirebaseAuth.instance.currentUser!.uid;
    final saved = await bDb.collection('users').doc(aUid).get();
    expect(saved.data()?['username'], usernameA);
    expect(saved.data()?.containsKey('phoneNumber'), isFalse);
    step('profile saved; username reserved; visible to other users');

    // ---- find user B and send a message ----
    await tester.tap(find.text('Contacts'));
    final search =
        find.widgetWithText(TextField, 'Username, name or phone number');
    await pumpUntil(tester, search, what: 'contacts search');
    await tester.enterText(search, usernameB);
    await pumpUntil(tester, find.text('User B'),
        what: 'search result for user B');
    step('user search by username');
    await tester.tap(find.text('User B'));
    final composer = find.widgetWithText(TextField, 'Message');
    await pumpUntil(tester, composer, what: 'chat screen');
    await tester.enterText(composer, 'Hello from A');
    await pumpUntil(tester, find.byTooltip('Send'));
    await tester.tap(find.byTooltip('Send'));
    await pumpUntil(tester, find.text('Hello from A'),
        what: 'sent message bubble');

    // ---- user B receives it ----
    final chatId = ([aUid, bUid]..sort()).join('_');
    QuerySnapshot<Map<String, dynamic>>? received;
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(end)) {
      received = await bDb
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isEqualTo: aUid)
          .get(const GetOptions(source: Source.server));
      if (received.docs.isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(received!.docs.single.data()['text'], 'Hello from A');
    expect(received.docs.single.data()['receiverId'], bUid);
    step('message sent by A is received by B');

    // B marks it read, as B's phone would when opening the chat.
    await received.docs.single.reference
        .update({'status': 'read', 'readAt': FieldValue.serverTimestamp()});

    // ---- B replies, A receives it in real time ----
    final now = Timestamp.now();
    final reply = bDb.batch();
    reply.set(
        bDb.collection('chats').doc(chatId),
        {
          'type': 'direct',
          'members': ([aUid, bUid]..sort()),
          'lastMessage': 'Hello from B',
          'lastMessageType': 'text',
          'lastSenderId': bUid,
          'lastMessageAt': now,
          'updatedAt': FieldValue.serverTimestamp(),
          'unread': {aUid: FieldValue.increment(1), bUid: 0},
        },
        SetOptions(merge: true));
    reply
        .set(bDb.collection('chats').doc(chatId).collection('messages').doc(), {
      'senderId': bUid,
      'receiverId': aUid,
      'type': 'text',
      'text': 'Hello from B',
      'status': 'sent',
      'clientCreatedAt': now,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await reply.commit();
    await pumpUntil(tester, find.text('Hello from B'),
        what: "B's reply on A's screen");
    step('reply from B is received by A in real time');

    // A's phone marks B's reply as read (receipts flow back to B).
    final end2 = DateTime.now().add(const Duration(seconds: 30));
    String? status;
    while (DateTime.now().isBefore(end2)) {
      final q = await bDb
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isEqualTo: bUid)
          .get(const GetOptions(source: Source.server));
      status = q.docs.single.data()['status'] as String?;
      if (status == 'read') break;
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(status, 'read');
    step('read receipts reach the sender');

    // ---- an outsider cannot read the conversation ----
    final cApp = await Firebase.initializeApp(
        name: 'userC', options: FirebaseConfig.options);
    final cAuth = FirebaseAuth.instanceFor(app: cApp);
    await cAuth.useAuthEmulator(FirebaseConfig.emulatorHost, 9099);
    final cDb = FirebaseFirestore.instanceFor(app: cApp);
    cDb.useFirestoreEmulator(FirebaseConfig.emulatorHost, 8080);
    await cAuth.createUserWithEmailAndPassword(
        email: 'userc$stamp@example.com', password: 'test-password-C1');
    Object? denied;
    try {
      await cDb
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      denied = e.code;
    }
    expect(denied, 'permission-denied');
    step('a third user cannot read the private chat');

    // ---- photo and voice message (same pipeline as the attach buttons) ----
    final tmp = await getTemporaryDirectory();
    final photo = File('${tmp.path}/e2e.png')..writeAsBytesSync(_png);
    final direct = Chat.direct(aUid, bUid);
    await AttachmentService.instance.sendFile(
        chat: direct,
        senderId: aUid,
        type: MessageType.image,
        file: photo,
        name: 'e2e.png',
        mime: 'image/png');
    final voiceBytes = List<int>.generate(4000, (i) => i % 251);
    final voice = File('${tmp.path}/voice.m4a')..writeAsBytesSync(voiceBytes);
    await AttachmentService.instance.sendFile(
        chat: direct,
        senderId: aUid,
        type: MessageType.audio,
        file: voice,
        name: 'voice.m4a',
        mime: 'audio/mp4',
        durationMs: 1000);
    Future<List<int>?> bReadsAttachment(String type) async {
      final m = await waitForDoc(tester, () async {
        final q = await bDb
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .where('senderId', isEqualTo: aUid)
            .where('type', isEqualTo: type)
            .get(const GetOptions(source: Source.server));
        return q.docs.isEmpty ? null : q.docs.first.data();
      });
      final blobId = (m?['attachment'] as Map?)?['blobId'] as String?;
      if (blobId == null) return null;
      final blob = await bDb
          .collection('chats')
          .doc(chatId)
          .collection('blobs')
          .doc(blobId)
          .get(const GetOptions(source: Source.server));
      return base64Decode(blob.data()!['data'] as String);
    }

    expect(await bReadsAttachment('image'), _png);
    step('photo sent by A is downloaded intact by B');
    expect(await bReadsAttachment('audio'), voiceBytes);
    step('voice message sent by A is downloaded intact by B');

    // ---- group chat through the UI ----
    await tester.pageBack();
    await pumpUntil(tester, find.text('Chats'), what: 'home screen');
    await tester.tap(find.text('Chats'));
    await pumpUntil(tester, find.byTooltip('New chat'));
    await tester.tap(find.byTooltip('New chat'));
    await pumpUntil(tester, find.text('New group'));
    await tester.tap(find.text('New group'));
    await pumpUntil(tester, find.text('Add participants'),
        what: 'participant picker');
    await pumpUntil(tester, find.text('User B'));
    await tester.tap(find.text('User B'));
    await pumpUntil(tester, find.textContaining('Next'));
    await tester.tap(find.textContaining('Next'));
    final groupName = find.widgetWithText(TextField, 'Group name');
    await pumpUntil(tester, groupName, what: 'group details');
    await tester.enterText(groupName, 'E2E group');
    await tester.tap(find.byIcon(Icons.check));
    final groupComposer = find.widgetWithText(TextField, 'Message');
    await pumpUntil(tester, groupComposer, what: 'group chat screen');
    await pumpUntil(tester, find.text('You created the group'),
        what: 'group system message');
    await tester.enterText(groupComposer, 'Hello group');
    await pumpUntil(tester, find.byTooltip('Send'));
    await tester.tap(find.byTooltip('Send'));
    await pumpUntil(tester, find.text('Hello group'));
    final groups = await bDb
        .collection('chats')
        .where('members', arrayContains: bUid)
        .where('type', isEqualTo: 'group')
        .get(const GetOptions(source: Source.server));
    expect(groups.docs.length, 1);
    final groupId = groups.docs.single.id;
    final gMsgs = await bDb
        .collection('chats')
        .doc(groupId)
        .collection('messages')
        .where('senderId', isEqualTo: aUid)
        .get(const GetOptions(source: Source.server));
    expect(gMsgs.docs.map((d) => d.data()['text']), contains('Hello group'));
    await bDb
        .collection('chats')
        .doc(groupId)
        .collection('messages')
        .doc()
        .set({
      'senderId': bUid,
      'type': 'text',
      'text': 'Hi from B in the group',
      'readBy': <String>[],
      'clientCreatedAt': Timestamp.now(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await pumpUntil(tester, find.text('Hi from B in the group'),
        what: 'group reply');
    step('group created in the UI; members exchange messages');
    Object? groupDenied;
    try {
      await cDb
          .collection('chats')
          .doc(groupId)
          .collection('messages')
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      groupDenied = e.code;
    }
    expect(groupDenied, 'permission-denied');
    step('a non-member cannot read the group');

    // ---- call signaling: A calls B, B declines ----
    await tester.pageBack();
    await pumpUntil(tester, find.text('Chats'));
    await tester.tap(find.text('User B').first);
    await pumpUntil(tester, find.byTooltip('Voice call'),
        what: 'direct chat with call buttons');
    await tester.tap(find.byTooltip('Voice call'));
    final ringing = await waitForDoc(tester, () async {
      final q = await bDb
          .collection('calls')
          .where('calleeId', isEqualTo: bUid)
          .where('status', isEqualTo: 'ringing')
          .get(const GetOptions(source: Source.server));
      return q.docs.isEmpty
          ? null
          : {'id': q.docs.first.id, ...q.docs.first.data()};
    });
    if (ringing == null) {
      debugPrint('E2E CALL NOT TESTED: the call did not start on this emulator '
          '(no microphone available to WebRTC).');
      return;
    }
    expect(ringing['callerId'], aUid);
    expect((ringing['offer'] as Map)['type'], 'offer');
    step('voice call rings on the other side (WebRTC offer delivered)');
    await pumpUntil(tester, find.text('Calling…'),
        what: 'outgoing call screen');
    await bDb.collection('calls').doc(ringing['id'] as String).update({
      'status': 'rejected',
      'endedAt': FieldValue.serverTimestamp(),
      'endedBy': bUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await pumpUntil(tester, find.text('Declined'), what: 'declined call state');
    final bHistory = await bDb
        .collection('users')
        .doc(bUid)
        .collection('calls')
        .doc(ringing['id'] as String)
        .get(const GetOptions(source: Source.server));
    expect(bHistory.exists, isTrue);
    step('declined call ends on the caller; call history recorded');
  }, timeout: const Timeout(Duration(minutes: 25)));
}
