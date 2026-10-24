import 'package:chat_adunka/main.dart';
import 'package:chat_adunka/screens/auth/phone_entry_screen.dart';
import 'package:chat_adunka/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Welcome screen is shown when Firebase is not configured', (tester) async {
    await tester.pumpWidget(const ChatAdunka());
    expect(find.text('Welcome to Chat Aduunka'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Setup required'), findsOneWidget);
  });

  test('phone numbers are normalised to E.164', () {
    expect(toE164('252', '061 234 5678'), '+252612345678');
    expect(toE164('966', '0501234567'), '+966501234567');
    expect(toE164('966', '+966 50 123 4567'), '+966501234567');
    expect(toE164('1', '(415) 555-0100'), '+14155550100');
    expect(isPlausibleE164('+252612345678'), isTrue);
    expect(isPlausibleE164('+2521'), isFalse);
  });

  test('chat ids are the same for both participants', () {
    expect(ChatService.chatIdFor('b', 'a'), 'a_b');
    expect(ChatService.chatIdFor('a', 'b'), 'a_b');
  });

  testWidgets('placeholder', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
