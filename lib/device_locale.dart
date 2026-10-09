import 'package:flutter/widgets.dart';

Locale resolveDeviceLocale(Iterable<Locale> deviceLocales) {
  final locales = deviceLocales.iterator;
  if (!locales.moveNext()) return const Locale('en');

  final languageCode = locales.current.languageCode.toLowerCase();
  if (languageCode == 'ar' || languageCode == 'fr') {
    return Locale(languageCode);
  }
  return const Locale('en');
}