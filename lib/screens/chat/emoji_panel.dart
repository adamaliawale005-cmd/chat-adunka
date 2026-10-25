import 'package:flutter/material.dart';

/// Simple emoji keyboard with common emoji grouped by category.
class EmojiPanel extends StatelessWidget {
  final void Function(String emoji) onPick;
  const EmojiPanel({super.key, required this.onPick});

  static const List<(IconData, String)> _groups = [
    (
      Icons.emoji_emotions_outlined,
      '😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥳 😏 😒 😞 😔 😟 😕 🙁 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕'
    ),
    (
      Icons.waving_hand_outlined,
      '👋 🤚 🖐 ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 💪 🫶'
    ),
    (
      Icons.favorite_border,
      '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ✨ ⭐ 🌟 🔥 💯 ✅ ❌ ❗ ❓ 💤 🎉 🎊 🎁'
    ),
    (
      Icons.pets_outlined,
      '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🦅 🐪 🐫 🐘 🦒 🐄 🐐 🐑 🐟 🐬 🐳 🌸 🌹 🌻 🌴 🌵 🌙 ☀️ 🌧 ⛅ 🌈'
    ),
    (
      Icons.restaurant_outlined,
      '☕ 🍵 🥛 🍞 🥖 🧀 🍳 🥩 🍗 🍖 🍕 🍔 🍟 🌯 🥙 🍝 🍚 🍛 🍲 🥗 🍌 🍉 🍇 🍓 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🥕 🌽 🍰 🎂 🍪 🍫 🍬 🍭 🧃'
    ),
    (
      Icons.sports_soccer_outlined,
      '⚽ 🏀 🏈 ⚾ 🎾 🏐 🏓 🏸 🥅 🏆 🥇 🎮 🎲 🎵 🎶 🎤 🎧 📚 ✏️ 📌 📎 📷 📱 💻 ⌚ 💡 🔑 🏠 🕌 🚗 ✈️ 🚀 ⛵ 🗺 🧳 ⏰'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return DefaultTabController(
      length: groups.length,
      child: Column(children: [
        TabBar(tabs: [for (final g in groups) Tab(icon: Icon(g.$1, size: 20))]),
        Expanded(
          child: TabBarView(children: [
            for (final g in groups)
              GridView.extent(
                maxCrossAxisExtent: 44,
                padding: const EdgeInsets.all(6),
                children: [
                  for (final e in g.$2.split(' ').where((s) => s.isNotEmpty))
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onPick(e),
                      child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                ],
              ),
          ]),
        ),
      ]),
    );
  }
}
