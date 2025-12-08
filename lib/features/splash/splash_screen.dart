// lib/features/splash/splash_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/hive_storage.dart';
import '../home/climate_curve_home.dart';
import '../initial_settings/initial_settings_home.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Controller per le animazioni
  late AnimationController _bgController;
  late AnimationController _logoController;
  late Animation<Color?> _colorAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Animazione Sfondo (Ciclo Freddo -> Caldo)
    _bgController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _colorAnimation = ColorTween(
      begin: Colors.lightBlue.shade800, // Freddo
      end: Colors.orange.shade900,      // Caldo
    ).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    // 2. Animazione Logo (Respiro)
    _logoController = AnimationController(
      duration: const Duration(seconds: 1, milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.05).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    // 3. Avvia la sequenza di controllo logico
    _startSplashSequence();
  }

  Future<void> _startSplashSequence() async {
    // Attendi che l'animazione faccia scena per almeno 3.5 secondi
    await Future.delayed(const Duration(milliseconds: 3500));

    // CONTROLLO INTELLIGENTE
    final bool isInitialized = await AppStorage.isAppInitialized();

    // Carica i parametri salvati (o default)
    final double slope = await AppStorage.getSlope();
    final double offset = await AppStorage.getOffset();

    if (!mounted) return;

    if (isInitialized) {
      // CASO A: Utente già registrato -> VAI ALLA HOME
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ClimateCurveOfflineHome(
            initialSlope: slope,
            initialOffset: offset,
          ),
        ),
      );
    } else {
      // CASO B: Primo avvio -> VAI ALLA CALIBRAZIONE (Manopole)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const InitialSettingsHome()),
      );
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Status bar trasparente
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, child) {
        return Scaffold(
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _colorAnimation.value ?? Colors.blue,
                  Colors.white,
                ],
                stops: const [0.0, 1.5], // Effetto luce diffusa
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO ANIMATO (Respiro)
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 140,
                    height: 140,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25), // Effetto vetro
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_colorAnimation.value ?? Colors.blue).withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.thermostat, size: 60, color: Colors.white);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // NOME APP
                const Text(
                  'ClimaSense',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                    shadows: [
                      Shadow(color: Colors.black26, offset: Offset(0, 3), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // SOTTOTITOLO
                Text(
                  'Ottimizzazione Climatica',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.95),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 80),

                // LOADING
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
