import 'package:flutter/material.dart';

const Color aduTeal = Color(0xFF00897B);

/// Colours used by chat bubbles, kept in sync with light/dark mode.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  final Color myBubble;
  final Color otherBubble;
  final Color myText;
  final Color otherText;
  final Color meta;
  final Color readTick;
  final Color chatBackground;

  const ChatColors({
    required this.myBubble,
    required this.otherBubble,
    required this.myText,
    required this.otherText,
    required this.meta,
    required this.readTick,
    required this.chatBackground,
  });

  static const light = ChatColors(
    myBubble: Color(0xFFD7F2EE),
    otherBubble: Colors.white,
    myText: Color(0xFF102321),
    otherText: Color(0xFF1B1F1E),
    meta: Color(0xFF5F6B69),
    readTick: Color(0xFF1E88E5),
    chatBackground: Color(0xFFEFF4F3),
  );

  static const dark = ChatColors(
    myBubble: Color(0xFF115E56),
    otherBubble: Color(0xFF243230),
    myText: Color(0xFFEAF6F4),
    otherText: Color(0xFFE6ECEB),
    meta: Color(0xFFA7B8B5),
    readTick: Color(0xFF64B5F6),
    chatBackground: Color(0xFF0F1A19),
  );

  @override
  ChatColors copyWith({
    Color? myBubble,
    Color? otherBubble,
    Color? myText,
    Color? otherText,
    Color? meta,
    Color? readTick,
    Color? chatBackground,
  }) =>
      ChatColors(
        myBubble: myBubble ?? this.myBubble,
        otherBubble: otherBubble ?? this.otherBubble,
        myText: myText ?? this.myText,
        otherText: otherText ?? this.otherText,
        meta: meta ?? this.meta,
        readTick: readTick ?? this.readTick,
        chatBackground: chatBackground ?? this.chatBackground,
      );

  @override
  ChatColors lerp(ThemeExtension<ChatColors>? other, double t) {
    if (other is! ChatColors) return this;
    return ChatColors(
      myBubble: Color.lerp(myBubble, other.myBubble, t)!,
      otherBubble: Color.lerp(otherBubble, other.otherBubble, t)!,
      myText: Color.lerp(myText, other.myText, t)!,
      otherText: Color.lerp(otherText, other.otherText, t)!,
      meta: Color.lerp(meta, other.meta, t)!,
      readTick: Color.lerp(readTick, other.readTick, t)!,
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: aduTeal, brightness: brightness);
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF111817) : null,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF16211F) : aduTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: aduTeal,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      extensions: [isDark ? ChatColors.dark : ChatColors.light],
    );
  }
}

extension ChatColorsX on BuildContext {
  ChatColors get chatColors => Theme.of(this).extension<ChatColors>() ?? ChatColors.light;
}
