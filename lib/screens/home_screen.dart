import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/chat_models.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import 'chat/chat_list_view.dart';
import 'directory_screen.dart';
import 'profile/my_profile_view.dart';

class HomeScreen extends StatefulWidget {
  final AppUser me;
  const HomeScreen({super.key, required this.me});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<List<ChatSummary>>? _deliverySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = widget.me.uid;
    UserService.instance.touchLastSeen(uid);
    NotificationService.instance.start(uid);
    // Whenever a chat changes and the last message came from someone else,
    // confirm delivery of anything still marked "sent".
    _deliverySub = ChatService.instance.watchChats(uid).listen((chats) {
      final pending = chats.where((c) => c.lastSenderId.isNotEmpty && c.lastSenderId != uid);
      ChatService.instance.markDeliveredInChats(uid, pending.map((c) => c.id));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      UserService.instance.touchLastSeen(widget.me.uid);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deliverySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ChatListView(me: widget.me),
      DirectoryView(me: widget.me),
      MyProfileView(me: widget.me),
    ];
    const titles = ['Chat Aduunka', 'Contacts', 'Profile'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              tooltip: 'New chat',
              onPressed: () => setState(() => _tab = 1),
              child: const Icon(Icons.chat),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
