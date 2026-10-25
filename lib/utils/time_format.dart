import 'package:intl/intl.dart';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Date formats for languages without bundled date data fall back to English.
String _safe(String locale) {
  try {
    return DateFormat.localeExists(locale) ? locale : 'en';
  } catch (_) {
    return 'en';
  }
}

typedef Tr = String Function(String key, [Map<String, Object?> args]);

/// "14:05" today, "Yesterday", weekday this week, otherwise a date.
String formatListTime(DateTime t, Tr tr, String locale) {
  final local = t.toLocal();
  final now = DateTime.now();
  if (_sameDay(local, now)) return DateFormat.Hm(_safe(locale)).format(local);
  if (_sameDay(local, now.subtract(const Duration(days: 1)))) return tr('yesterday');
  if (now.difference(local).inDays < 7) return DateFormat.E(_safe(locale)).format(local);
  return DateFormat.yMd(_safe(locale)).format(local);
}

/// Time shown inside each message bubble.
String formatMessageTime(DateTime t, String locale) => DateFormat.Hm(_safe(locale)).format(t.toLocal());

/// Day separator label in a conversation.
String formatDayHeader(DateTime t, Tr tr, String locale) {
  final local = t.toLocal();
  final now = DateTime.now();
  if (_sameDay(local, now)) return tr('today');
  if (_sameDay(local, now.subtract(const Duration(days: 1)))) return tr('yesterday');
  return DateFormat.yMMMMEEEEd(_safe(locale)).format(local);
}

String dayKey(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${l.month}-${l.day}';
}

String formatLastSeen(DateTime? t, Tr tr, String locale) {
  if (t == null) return '';
  final local = t.toLocal();
  final now = DateTime.now();
  final time = DateFormat.Hm(_safe(locale)).format(local);
  if (_sameDay(local, now)) return tr('last_seen_today', {'time': time});
  if (_sameDay(local, now.subtract(const Duration(days: 1)))) return tr('last_seen_yesterday', {'time': time});
  return tr('last_seen_date', {'date': DateFormat.yMMMd(_safe(locale)).format(local)});
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
