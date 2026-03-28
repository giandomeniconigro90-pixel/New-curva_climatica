// lib/main.dart

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'services/hive_storage.dart';
import 'services/notification_service.dart';
import 'services/theme_notifier.dart';
import 'services/weather_service.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStorage.init();
  await NotificationService.init();
  await initializeDateFormatting('it_IT', null);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  _scheduleMidnightCacheClear();

  final ThemeMode savedMode = AppStorage.getThemeMode();
  final bool isDarkAtStart = _resolveIsDark(
    savedMode,
    PlatformDispatcher.instance.platformBrightness,
  );
  _applyOverlay(isDarkAtStart);

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier.fromStorage(),
      child: const ClimaSenseApp(),
    ),
  );
}

/// Schedula la pulizia della cache meteo ogni mezzanotte.
/// Il primo Timer scatta alla prossima mezzanotte locale,
/// poi un Timer.periodic ripete ogni 24 ore.
void _scheduleMidnightCacheClear() {
  final now = DateTime.now();
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  final delay = nextMidnight.difference(now);

  Timer(delay, () {
    WeatherService.clearCache();
    Timer.periodic(const Duration(hours: 24), (_) {
      WeatherService.clearCache();
    });
  });
}

bool _resolveIsDark(ThemeMode mode, Brightness platformBrightness) {
  switch (mode) {
    case ThemeMode.dark:
      return true;
    case ThemeMode.light:
      return false;
    case ThemeMode.system:
      return platformBrightness == Brightness.dark;
  }
}

void _applyOverlay(bool isDark) {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    ),
  );
}

class ClimaSenseApp extends StatelessWidget {
  const ClimaSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final themeMode = themeNotifier.themeMode;

    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final bool isDark = _resolveIsDark(themeMode, platformBrightness);
    _applyOverlay(isDark);

    return MaterialApp(
      title: 'ClimaSense',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF263238),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF263238),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
