// lib/features/home/new_thermostat_home.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/hive_storage.dart';

class NewThermostatHome extends StatefulWidget {
  const NewThermostatHome({super.key});

  @override
  State<NewThermostatHome> createState() => _NewThermostatHomeState();
}

class _NewThermostatHomeState extends State<NewThermostatHome> {
  bool _isLoading = true;
  String _systemMode = 'heating';
  double _currentInternalTemp = 20.0;
  // Rimosso _targetTemp che non era usato

  @override
  void initState() {
    super.initState();
    _loadSystemData();
  }

  Future<void> _loadSystemData() async {
    final mode = await AppStorage.getSystemMode();
    final records = await AppStorage.loadRecords();

    double lastTemp = 20.0;
    if (records.isNotEmpty) {
      final last = records.last;
      if (last.internalTemps.isNotEmpty) {
        double sum = 0;
        last.internalTemps.values.forEach((v) => sum += v);
        lastTemp = sum / last.internalTemps.length;
      }
    }

    if (mounted) {
      setState(() {
        _systemMode = mode;
        _currentInternalTemp = lastTemp;
        _isLoading = false;
      });
    }
  }

  Color get _mainColor {
    if (_systemMode == 'cooling') return const Color(0xFF4CD964);
    return const Color(0xFFFF9500);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: _mainColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context), // Torna alla Dashboard
        ),
        title: Text(
          _systemMode == 'heating' ? 'Riscaldamento' : 'Raffrescamento',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(
              "ALL'INTERNO ORA ${_currentInternalTemp.toStringAsFixed(1)}°",
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Pillola centrale
            Center(
              child: Container(
                width: 240,
                height: 400,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(45),
                ),
                child: Column(
                  children: [
                    const Spacer(flex: 4),
                    Expanded(
                      flex: 5,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(45)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
