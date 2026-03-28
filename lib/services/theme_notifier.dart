// lib/services/theme_notifier.dart

import 'package:flutter/material.dart';
import 'hive_storage.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode;

  ThemeNotifier(this._themeMode);

  ThemeMode get themeMode => _themeMode;

  static ThemeNotifier fromStorage() {
    return ThemeNotifier(AppStorage.getThemeMode());
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await AppStorage.saveThemeMode(mode);
  }
}
