// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

// Import Services
import 'services/hive_storage.dart';
import 'services/notification_service.dart';

// Import Splash Screen (Percorso corretto)
import 'features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza lo Storage (Hive)
  await AppStorage.init();

  // Inizializza le Notifiche
  await NotificationService.init();

  // Inizializza la localizzazione per le date (Italiano)
  await initializeDateFormatting('it_IT', null);

  // --- CONFIGURAZIONE ORIENTAMENTO ---
  // Abilitiamo tutte le orientazioni (Portrait + Landscape)
  // Fondamentale per far funzionare correttamente la UI Tablet del Samsung Tab S6
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const ClimaSenseApp());
}

class ClimaSenseApp extends StatelessWidget {
  const ClimaSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClimaSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Impostazioni tema base
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF263238)),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      // Avvia dalla Splash Screen
      home: const SplashScreen(),
    );
  }
}
