import 'package:chat_adunka/models/app_user.dart';
import 'package:chat_adunka/models/chat_models.dart';
import 'package:chat_adunka/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

const me = 'me';
const friend = 'friend';

Chat direct(
        {int minute = 0,
        String sender = friend,
        int unread = 1,
        String type = 'text',
        String id = 'friend_me'}) =>
    Chat(
      id: id,
      isGroup: false,
      members: const [friend, me],
      lastMessage: 'hi',
      lastMessageType: type,
      lastSenderId: sender,
      lastMessageAt: DateTime.utc(2026, 10, 27, 12, minute),
      unread: {me: unread},
    );

Chat group({int minute = 0, int unread = 1}) => Chat(
      id: 'group1',
      isGroup: true,
      members: const [friend, me, 'x'],
      name: 'Family',
      lastMessage: 'hello all',
      lastSenderId: friend,
      lastMessageAt: DateTime.utc(2026, 10, 27, 12, minute),
      unread: {me: unread},
    );

void main() {
  late Map<String, String> known;
  setUp(() => known = {});

  List<Chat> pick(List<Chat> chats,
          {bool primed = true,
          Set<String> open = const {},
          Set<String> blocked = const {},
          AccountPrivate prefs = AccountPrivate.defaults}) =>
      NotificationService.selectNewMessages(
        me: me,
        chats: chats,
        known: known,
        primed: primed,
        openChats: open,
        blocked: blocked,
        prefs: prefs,
      );

  test('no alerts for messages already there when the app starts', () {
    expect(pick([direct()], primed: false), isEmpty);
    expect(known, isNotEmpty);
  });

  test('a new message from someone else is announced once', () {
    pick([direct()], primed: false);
    expect(
        pick([direct(minute: 1, unread: 2)]).map((c) => c.id), ['friend_me']);
    // Same snapshot again (e.g. typing indicator update): no repeat.
    expect(pick([direct(minute: 1, unread: 2)]), isEmpty);
  });

  test('first message of a brand-new chat is announced', () {
    // The person had no chats at all when the app started.
    pick([], primed: false);
    expect(pick([direct(minute: 3)]).length, 1);
  });

  test('own messages, system events and read chats are silent', () {
    pick([direct()], primed: false);
    expect(pick([direct(minute: 1, sender: me, unread: 0)]), isEmpty);
    expect(pick([direct(minute: 2, type: 'system')]), isEmpty);
    expect(pick([direct(minute: 3, unread: 0)]), isEmpty);
  });

  test('the chat on screen is silent', () {
    pick([direct()], primed: false);
    expect(pick([direct(minute: 1)], open: {'friend_me'}), isEmpty);
  });

  test('blocked people are silent', () {
    pick([direct()], primed: false);
    expect(pick([direct(minute: 1)], blocked: {friend}), isEmpty);
  });

  test('settings turn message and group alerts off separately', () {
    pick([direct(), group()], primed: false);
    const noGroups = AccountPrivate(notifyGroups: false);
    expect(
        pick([direct(minute: 1), group(minute: 1)], prefs: noGroups)
            .map((c) => c.id),
        ['friend_me']);
    const noDirect = AccountPrivate(notifyMessages: false);
    expect(
        pick([direct(minute: 2), group(minute: 2)], prefs: noDirect)
            .map((c) => c.id),
        ['group1']);
  });
}
