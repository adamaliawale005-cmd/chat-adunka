import 'package:chat_adunka/models/app_user.dart';
import 'package:chat_adunka/models/chat_models.dart';
import 'package:chat_adunka/services/chat_service.dart';
import 'package:chat_adunka/utils/mime.dart';
import 'package:chat_adunka/utils/phone.dart';
import 'package:chat_adunka/utils/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phone numbers', () {
    test('local numbers become E.164', () {
      expect(toE164('252', '061 234 5678'), '+252612345678');
      expect(toE164('966', '0501234567'), '+966501234567');
      expect(toE164('1', '(415) 555-0100'), '+14155550100');
    });

    test('numbers already in international form are kept', () {
      expect(toE164('252', '+966 50 123 4567'), '+966501234567');
      expect(toE164('252', '00966501234567'), '+966501234567');
      expect(toE164('966', '966501234567'), '+966501234567');
    });

    test('plausibility check', () {
      expect(isPlausibleE164('+252612345678'), isTrue);
      expect(isPlausibleE164('+2521'), isFalse);
      expect(isPlausibleE164('252612345678'), isFalse);
    });

    test('address book numbers use the default country code', () {
      expect(normalizeContactNumber('061 234 5678', '252'), '+252612345678');
      expect(
          normalizeContactNumber('+966 50 123 4567', '252'), '+966501234567');
      expect(normalizeContactNumber('12', '252'), isNull);
    });

    test('dial code detection prefers the longest match', () {
      const codes = ['1', '25', '252', '966'];
      expect(dialCodeOf('+252612345678', codes), '252');
      expect(dialCodeOf('+966501234567', codes), '966');
      expect(dialCodeOf('612345678', codes), isNull);
    });
  });

  group('usernames', () {
    test('valid usernames', () {
      for (final u in ['amina', 'yusuf_99', 'abc']) {
        expect(usernamePattern.hasMatch(u), isTrue, reason: u);
      }
    });

    test('invalid usernames', () {
      for (final u in [
        'ab',
        '9lives',
        'Amina',
        'has space',
        'a' * 21,
        'dash-name'
      ]) {
        expect(usernamePattern.hasMatch(u), isFalse, reason: u);
      }
    });

    test('normalisation removes @ and case', () {
      expect(normalizeUsername(' @Amina_1 '), 'amina_1');
    });
  });

  group('chats', () {
    test('direct chat ids are the same for both people', () {
      expect(ChatService.chatIdFor('b', 'a'), 'a_b');
      expect(ChatService.chatIdFor('a', 'b'), 'a_b');
      expect(ChatService.isDirectId('a_b'), isTrue);
      expect(ChatService.isDirectId('Xy12groupId'), isFalse);
    });

    test('chat helpers', () {
      final now = DateTime.now();
      final chat = Chat(
        id: 'g1',
        isGroup: true,
        members: const ['a', 'b', 'c'],
        admins: const ['a'],
        onlyAdminsCanSend: true,
        typing: {
          'b': now,
          'c': now.subtract(const Duration(seconds: 30)),
          'a': now
        },
        unread: const {'b': 3},
      );
      expect(chat.typingUsers('a'), ['b']);
      expect(chat.unreadFor('b'), 3);
      expect(chat.unreadFor('a'), 0);
      expect(chat.canSend('a'), isTrue);
      expect(chat.canSend('b'), isFalse);
      expect(Chat.direct('z', 'y').id, 'y_z');
    });

    test('group read status needs every other member', () {
      ChatMessage msg(List<String> readBy) => ChatMessage(
            id: 'm',
            chatId: 'g1',
            senderId: 'a',
            type: MessageType.text,
            readBy: readBy,
            createdAt: DateTime.now(),
          );
      expect(msg(const ['b']).groupStatus(3), MessageStatus.sent);
      expect(msg(const ['b', 'c']).groupStatus(3), MessageStatus.read);
    });

    test('chat list previews', () {
      expect(ChatService.summaryFor(MessageType.text, 'hi'), 'hi');
      expect(ChatService.summaryFor(MessageType.image, ''), '📷');
      expect(ChatService.summaryFor(MessageType.audio, ''), '🎤');
      expect(ChatService.summaryFor(MessageType.text, 'x' * 300).length, 201);
    });

    test('only recent text messages can be edited', () {
      ChatMessage msg(MessageType t, Duration age, {bool deleted = false}) =>
          ChatMessage(
            id: 'm',
            chatId: 'a_b',
            senderId: 'a',
            type: t,
            text: 'hi',
            deleted: deleted,
            createdAt: DateTime.now().subtract(age),
          );
      expect(
          ChatService.canEdit(
              msg(MessageType.text, const Duration(hours: 1)), 'a'),
          isTrue);
      expect(
          ChatService.canEdit(
              msg(MessageType.text, const Duration(hours: 1)), 'b'),
          isFalse);
      expect(
          ChatService.canEdit(
              msg(MessageType.text, const Duration(days: 3)), 'a'),
          isFalse);
      expect(
          ChatService.canEdit(
              msg(MessageType.image, const Duration(hours: 1)), 'a'),
          isFalse);
      expect(
          ChatService.canEdit(
              msg(MessageType.text, Duration.zero, deleted: true), 'a'),
          isFalse);
    });
  });

  group('privacy settings', () {
    test('defaults are privacy-friendly where it matters', () {
      const p = AccountPrivate.defaults;
      expect(p.contactSync, isFalse);
      expect(p.readReceipts, isTrue);
    });

    test('settings survive a round trip', () {
      final p = AccountPrivate.defaults
          .copyWith(showLastSeen: false, notifyGroups: false);
      final back = AccountPrivate.fromMap(p.toMap());
      expect(back.showLastSeen, isFalse);
      expect(back.notifyGroups, isFalse);
      expect(back.notifyMessages, isTrue);
    });
  });

  group('formatting', () {
    test('file types', () {
      expect(mimeFromName('report.PDF', MessageType.file), 'application/pdf');
      expect(mimeFromName('voice.m4a', MessageType.audio), 'audio/mp4');
      expect(mimeFromName('unknown', MessageType.image), 'image/jpeg');
    });

    test('durations and sizes', () {
      expect(formatDuration(const Duration(seconds: 75)), '01:15');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
