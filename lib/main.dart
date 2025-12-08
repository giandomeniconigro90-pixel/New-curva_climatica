// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/hive_storage.dart';
import 'services/notification_service.dart'; // <--- IMPORT NOTIFICHE
import 'features/splash/splash_screen.dart';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza Database
  await AppStorage.init();

  // Inizializza e programma Notifiche
  await NotificationService.init();
  await NotificationService.scheduleDailyReminder();

  // Configura Stile Status Bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const OfflineClimateCurveApp());
}

class OfflineClimateCurveApp extends StatelessWidget {
  const OfflineClimateCurveApp({super.key});

  @override
  Widget build(BuildContext context) {
    // --- PALETTE ECO-TECH 2.0 ---
    const primaryColor = Color(0xFF00695C);
    const secondaryColor = Color(0xFF4DB6AC);
    const scaffoldBg = Color(0xFFF5F7F6);
    const surfaceColor = Colors.white;

    return MaterialApp(
      title: 'ClimaSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          secondary: secondaryColor,
          background: scaffoldBg,
          surface: surfaceColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: scaffoldBg,

        // Font Theme Moderno
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: Color(0xFF1A1A1A),
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF263238),
          ),
          bodyMedium: TextStyle(
            fontSize: 15,
            color: Color(0xFF455A64),
            height: 1.5,
          ),
        ),

        // AppBar "Glassy" Flat
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          backgroundColor: scaffoldBg,
          foregroundColor: Color(0xFF263238),
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF004D40),
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: primaryColor),
        ),

        // Card Theme
        cardTheme: CardThemeData(
          color: surfaceColor,
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.05),
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide.none,
          ),
        ),

        // Input Theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: secondaryColor, width: 2),
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          floatingLabelStyle: const TextStyle(
            color: primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),

        // Button Theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 6,
            padding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),

        // Nav Bar Theme
        navigationBarTheme: NavigationBarThemeData(
          height: 75,
          backgroundColor: Colors.white,
          elevation: 10,
          shadowColor: Colors.black.withOpacity(0.1),
          indicatorColor: secondaryColor.withOpacity(0.2),
          iconTheme: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const IconThemeData(color: primaryColor, size: 26);
            }
            return IconThemeData(
              color: Colors.grey.shade400,
              size: 24,
            );
          }),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
