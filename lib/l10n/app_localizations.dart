import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'strings_ar.dart';
import 'strings_en.dart';
import 'strings_so.dart';

/// Simple key-based translations for English, Somali and Arabic.
/// Arabic switches the whole layout to right-to-left automatically.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static const supportedLocales = [Locale('en'), Locale('so'), Locale('ar')];

  static const Map<String, Map<String, String>> tables = {
    'en': stringsEn,
    'so': stringsSo,
    'ar': stringsAr,
  };

  static const languageNames = {
    'en': 'English',
    'so': 'Soomaali',
    'ar': 'العربية'
  };

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('en'));

  String tr(String key, [Map<String, Object?> args = const {}]) {
    var text = tables[locale.languageCode]?[key] ?? stringsEn[key] ?? key;
    args.forEach(
        (name, value) => text = text.replaceAll('{$name}', '${value ?? ''}'));
    return text;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    _FallbackMaterialLocalizationsDelegate(),
    _FallbackCupertinoLocalizationsDelegate(),
  ];

  /// Picks a supported language for the phone's locale, defaulting to English.
  static Locale resolve(Locale? device, Iterable<Locale> supported) {
    if (device != null) {
      for (final l in supported) {
        if (l.languageCode == device.languageCode) return l;
      }
    }
    return const Locale('en');
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.tables.containsKey(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Material widgets have no built-in Somali texts on every Flutter version;
/// fall back to English for those (our own texts are still Somali).
class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      !GlobalMaterialLocalizations.delegate.isSupported(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}

class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      !GlobalCupertinoLocalizations.delegate.isSupported(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_FallbackCupertinoLocalizationsDelegate old) => false;
}

extension L10nX on BuildContext {
  String tr(String key, [Map<String, Object?> args = const {}]) =>
      AppLocalizations.of(this).tr(key, args);
}
