import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/app_user.dart';
import '../models/call_models.dart';
import '../models/chat_models.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../state/session.dart';
import 'calls/call_screen.dart';
import 'calls/calls_tab.dart';
import 'calls/incoming_call_screen.dart';
import 'chat/chat_screen.dart';
import 'chat/chats_tab.dart';
import 'contacts/contacts_tab.dart';
import 'groups/create_group_screen.dart';
import 'settings/settings_tab.dart';

class HomeScreen extends StatefulWidget {
  final AppUser me;
  final User authUser;
  const HomeScreen({super.key, required this.me, required this.authUser});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  final List<StreamSubscription> _subs = [];
  Timer? _heartbeat;
  bool _incomingOpen = false;
  late final Stream<List<Chat>> _chats =
      ChatService.instance.watchChats(_uid).asBroadcastStream();
  late final Stream<List<CallLogEntry>> _history =
      CallService.instance.watchHistory(_uid);

  String get _uid => widget.authUser.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Session.uid = _uid;

    _subs.add(UserService.instance.watchPrivate(_uid).listen((p) {
      Session.settings.value = p;
      NotificationService.instance.prefs = p;
      UserService.instance.setShowLastSeen(p.showLastSeen);
    }, onError: (_) {}));
    _subs.add(UserService.instance
        .watchBlocked(_uid)
        .listen((b) => Session.blocked.value = b, onError: (_) {}));

    // Delivery receipts and in-app notifications for new messages.
    _subs.add(_chats.listen((chats) {
      final pending = chats.where((c) =>
          !c.isGroup && c.lastSenderId.isNotEmpty && c.lastSenderId != _uid);
      ChatService.instance.markDelivered(_uid, pending.map((c) => c.id));
      if (mounted) {
        NotificationService.instance
            .onChatsChanged(_uid, chats, tr: (k) => context.tr(k));
      }
    }, onError: (_) {}));

    _setOnline(true);
    _heartbeat =
        Timer.periodic(const Duration(seconds: 60), (_) => _setOnline(true));

    NotificationService.instance.start(_uid);
    NotificationService.instance.attach(_openPayload);

    final calls = CallService.instance;
    calls.listenForIncoming(_uid);
    _subs.add(calls.incomingCalls.listen(_showIncoming));
    calls.onMissedCall = (call) async {
      if (!Session.settings.value.notifyCalls) return;
      final caller = await UserService.instance.getUser(call.callerId);
      if (!mounted) return;
      NotificationService.instance.showLocal(
        title: context.tr('missed_call'),
        body: caller.hasProfile
            ? caller.displayName
            : context.tr('deleted_account'),
        payload: 'calls',
        call: true,
      );
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _heartbeat?.cancel();
    CallService.instance.stopListening();
    CallService.instance.onMissedCall = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setOnline(false);
    }
  }

  void _setOnline(bool online) =>
      UserService.instance.setPresence(_uid, online: online);

  void _showIncoming(CallDoc call) {
    if (_incomingOpen || Session.blocked.value.contains(call.callerId)) return;
    _incomingOpen = true;
    rootNavigatorKey.currentState
        ?.push(MaterialPageRoute(
            builder: (_) => IncomingCallScreen(call: call, me: _uid)))
        .whenComplete(() => _incomingOpen = false);
  }

  Future<void> _openPayload(String payload) async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    if (payload.startsWith('chat:')) {
      final chat = await ChatService.instance.getChat(payload.substring(5));
      if (chat == null) return;
      nav.push(
          MaterialPageRoute(builder: (_) => ChatScreen(me: _uid, chat: chat)));
    } else if (payload == 'calls') {
      setState(() => _tab = 2);
    } else if (payload.startsWith('call:')) {
      final active = CallService.instance.active.value;
      if (active != null && !active.isOver) {
        nav.push(MaterialPageRoute(builder: (_) => CallScreen(call: active)));
      }
    }
  }

  void _newChatMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: Text(ctx.tr('new_chat')),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _tab = 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text(ctx.tr('new_group')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CreateGroupScreen(me: _uid)));
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      context.tr('app_name'),
      context.tr('contacts'),
      context.tr('calls'),
      context.tr('settings')
    ];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: IndexedStack(
        index: _tab,
        children: [
          ChatsTab(me: _uid),
          ContactsTab(me: _uid, authUser: widget.authUser),
          CallsTab(me: _uid, active: _tab == 2),
          SettingsTab(me: widget.me, authUser: widget.authUser),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              tooltip: context.tr('new_chat'),
              onPressed: _newChatMenu,
              child: const Icon(Icons.chat),
            )
          : null,
      bottomNavigationBar: StreamBuilder<List<Chat>>(
        stream: _chats,
        builder: (context, snap) {
          final unreadChats = (snap.data ?? const <Chat>[])
              .where((c) => c.unreadFor(_uid) > 0)
              .length;
          return StreamBuilder<List<CallLogEntry>>(
            stream: _history,
            builder: (context, callSnap) {
              final missed = (callSnap.data ?? const <CallLogEntry>[])
                  .where((e) => e.isMissed && !e.seen)
                  .length;
              return NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: unreadChats > 0,
                      label: Text('$unreadChats'),
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
                    selectedIcon: const Icon(Icons.chat_bubble),
                    label: context.tr('chats'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.people_outline),
                    selectedIcon: const Icon(Icons.people),
                    label: context.tr('contacts'),
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: missed > 0,
                      label: Text('$missed'),
                      child: const Icon(Icons.call_outlined),
                    ),
                    selectedIcon: const Icon(Icons.call),
                    label: context.tr('calls'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: context.tr('settings'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
