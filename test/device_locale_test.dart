import 'package:ccnews_app/device_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects Arabic or French from the device locale list', () {
    expect(resolveDeviceLocale(const [Locale('ar', 'EG')]), const Locale('ar'));
    expect(resolveDeviceLocale(const [Locale('fr', 'FR')]), const Locale('fr'));
  });

  test('falls back to English for unsupported device languages', () {
    expect(
      resolveDeviceLocale(const [Locale('es', 'ES'), Locale('fr', 'FR')]),
      const Locale('en'),
    );
  });
}