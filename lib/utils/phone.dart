/// Phone number helpers (E.164 format: "+" then country code and number).
library;

/// Converts a country dial code and a locally typed number to E.164,
/// e.g. ("252", "061 234 5678") -> "+252612345678".
String toE164(String dialCode, String input) {
  final trimmed = input.trim();
  if (trimmed.startsWith('+')) {
    return '+${trimmed.replaceAll(RegExp(r'[^0-9]'), '')}';
  }
  var digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) return '+${digits.substring(2)}';
  // People often retype the country code without "+".
  if (digits.startsWith(dialCode) && digits.length > dialCode.length + 6) {
    digits = digits.substring(dialCode.length);
  }
  // Drop the national trunk prefix (leading zeros).
  digits = digits.replaceFirst(RegExp(r'^0+'), '');
  return '+$dialCode$digits';
}

bool isPlausibleE164(String e164) => RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(e164);

/// Normalises a number from the phone's address book. Numbers without a
/// country code are assumed to be in [defaultDialCode].
String? normalizeContactNumber(String raw, String defaultDialCode) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  final e164 = toE164(defaultDialCode, cleaned);
  return isPlausibleE164(e164) ? e164 : null;
}

/// Finds the dial code at the start of an E.164 number using the given
/// list of known codes (longest match wins).
String? dialCodeOf(String e164, Iterable<String> knownCodes) {
  if (!e164.startsWith('+')) return null;
  final digits = e164.substring(1);
  String? best;
  for (final code in knownCodes) {
    if (code.isEmpty) continue;
    if (digits.startsWith(code) && (best == null || code.length > best.length)) best = code;
  }
  return best;
}
