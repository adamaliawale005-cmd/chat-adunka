import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-level preferences: theme and language. Stored on the phone only.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _themeKey = 'theme_mode';
  static const _localeKey = 'locale';

  SharedPreferences? _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;

  ThemeMode get themeMode => _themeMode;

  /// null means "follow the phone's language".
  Locale? get locale => _locale;

  SharedPreferences? get prefs => _prefs;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final theme = _prefs!.getString(_themeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == theme,
      orElse: () => ThemeMode.system,
    );
    final code = _prefs!.getString(_localeKey);
    _locale = (code == null || code.isEmpty) ? null : Locale(code);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _prefs?.setString(_themeKey, mode.name);
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    await _prefs?.setString(_localeKey, locale?.languageCode ?? '');
  }
}
