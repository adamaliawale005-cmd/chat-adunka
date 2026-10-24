import 'package:intl/intl.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "14:05" today, "Yesterday", "Mon", or "12 Oct 2026" for older dates.
String formatListTime(DateTime t) {
  final local = t.toLocal();
  final now = DateTime.now();
  if (_sameDay(local, now)) return DateFormat.Hm().format(local);
  if (_sameDay(local, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  if (now.difference(local).inDays < 7) return DateFormat.E().format(local);
  return DateFormat('d MMM yyyy').format(local);
}

/// Time shown under each message bubble.
String formatMessageTime(DateTime t) => DateFormat.Hm().format(t.toLocal());

/// Day separator label in a conversation.
String formatDayHeader(DateTime t) {
  final local = t.toLocal();
  final now = DateTime.now();
  if (_sameDay(local, now)) return 'Today';
  if (_sameDay(local, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return DateFormat('EEEE, d MMMM yyyy').format(local);
}

String formatLastSeen(DateTime? t) {
  if (t == null) return '';
  final local = t.toLocal();
  final now = DateTime.now();
  if (now.difference(local).inMinutes < 2) return 'online recently';
  if (_sameDay(local, now)) return 'last seen today at ${DateFormat.Hm().format(local)}';
  if (_sameDay(local, now.subtract(const Duration(days: 1)))) {
    return 'last seen yesterday at ${DateFormat.Hm().format(local)}';
  }
  return 'last seen ${DateFormat('d MMM').format(local)}';
}
