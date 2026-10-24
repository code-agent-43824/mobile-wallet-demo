import 'package:flutter/widgets.dart';

import 'key_storage/secure_key_value_store.dart';

/// Where the chosen UI language is persisted.
///
/// The app has exactly one key/value store, so the preference rides along in it
/// rather than pulling in a second persistence package for a single string. It
/// is not a secret — it is stored beside the wallet only because that store is
/// the one the app already has.
const String uiLocaleStorageKey = 'ui_locale';

/// The languages the user can pick between, plus "follow the system".
///
/// Kept as an explicit list rather than reading
/// `AppLocalizations.supportedLocales` so the picker's order and its native
/// language names are a product decision, not an artefact of code generation.
const List<Locale> selectableLocales = <Locale>[Locale('ru'), Locale('en')];

/// Reads the persisted language choice. Returns null when the user has not
/// chosen one (or chose "system"), which means the app follows the device.
Future<Locale?> readStoredLocale(SecureKeyValueStore store) async {
  final code = await store.read(uiLocaleStorageKey);
  if (code == null || code.isEmpty) {
    return null;
  }
  for (final locale in selectableLocales) {
    if (locale.languageCode == code) {
      return locale;
    }
  }
  // An unknown code (a downgrade, a hand-edited store) is not a reason to fail
  // startup — fall back to following the system.
  return null;
}

/// Persists [locale], or clears the choice when it is null ("follow system").
Future<void> writeStoredLocale(
  SecureKeyValueStore store,
  Locale? locale,
) async {
  if (locale == null) {
    await store.delete(uiLocaleStorageKey);
    return;
  }
  await store.write(uiLocaleStorageKey, locale.languageCode);
}

/// Exposes the current language choice and the way to change it to the widgets
/// that render the picker, without threading two more parameters through every
/// screen between `app.dart` and the Настройки tab.
class AppLocaleScope extends InheritedWidget {
  const AppLocaleScope({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required super.child,
  });

  /// The explicit choice, or null when the app follows the system locale.
  final Locale? locale;

  /// Called with the new choice; null means "follow the system".
  final ValueChanged<Locale?> onLocaleChanged;

  /// Null when no scope is installed — the case in widget tests that pump a
  /// screen directly. Callers hide the picker rather than crash.
  static AppLocaleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();

  @override
  bool updateShouldNotify(AppLocaleScope oldWidget) =>
      locale != oldWidget.locale ||
      onLocaleChanged != oldWidget.onLocaleChanged;
}
