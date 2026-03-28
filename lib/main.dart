// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'services/hive_storage.dart';
import 'services/notification_service.dart';
import 'services/theme_notifier.dart';
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

  // Applica subito l'overlay corretto prima del primo frame,
  // basandosi sul tema salvato su Hive.
  _applyOverlayForTheme(AppStorage.getThemeMode());

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier.fromStorage(),
      child: const ClimaSenseApp(),
    ),
  );
}

void _applyOverlayForTheme(ThemeMode mode) {
  // Per ThemeMode.system usiamo la finestra di sistema: non possiamo saperlo
  // a priori, quindi lasciamo Brightness.dark come fallback sicuro
  // (icone chiare su sfondo scuro). Se l'utente ha scelto light, usiamo
  // Brightness.dark (icone scure su sfondo chiaro).
  final bool isDark = mode == ThemeMode.dark;
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

    // Aggiorna overlay ad ogni cambio tema in-app
    _applyOverlayForTheme(themeMode);

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
