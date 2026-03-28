// lib/services/weather_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temp;
  final String locationName;

  WeatherData({required this.temp, required this.locationName});
}

class WeatherService {
  static const Duration _timeout = Duration(seconds: 10);

  /// Ottieni temperatura media giornaliera e nome città attuale.
  ///
  /// I log di debug sono abilitati solo in [kDebugMode] e non includono
  /// mai coordinate GPS (dati sensibili).
  static Future<WeatherData?> getDailyAvgTemp() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (kDebugMode) debugPrint('🌍 GPS abilitato: $serviceEnabled');
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (kDebugMode) debugPrint('🌍 Permesso iniziale: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (kDebugMode) debugPrint('🌍 Permesso dopo richiesta: $permission');
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) debugPrint('🌍 Permesso negato per sempre');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(_timeout);
      // NON loggare lat/lon: sono dati personali sensibili.
      if (kDebugMode) debugPrint('🌍 Posizione ottenuta');

      String cityName = 'Tua Posizione';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(_timeout);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          cityName = p.locality ??
              p.subAdministrativeArea ??
              p.administrativeArea ??
              'Tua Posizione';
        }
        // Il nome città non è un dato sensibile: ok loggarlo.
        if (kDebugMode) debugPrint('🌍 Città rilevata: $cityName');
      } catch (e) {
        if (kDebugMode) debugPrint('🌍 Errore geocoding: $e');
        // Continua comunque con cityName = 'Tua Posizione'
      }

      // NON loggare l'URL: contiene lat/lon in chiaro.
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${position.latitude}&longitude=${position.longitude}'
        '&daily=temperature_2m_mean&timezone=auto&forecast_days=1',
      );

      final response = await http.get(url).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('Timeout richiesta meteo'),
      );
      if (kDebugMode) debugPrint('🌍 HTTP status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List temps = data['daily']['temperature_2m_mean'];
        if (temps.isNotEmpty) {
          final double avgTemp = (temps[0] as num).toDouble();
          if (kDebugMode) debugPrint('🌍 Temperatura media: $avgTemp°C');
          return WeatherData(temp: avgTemp, locationName: cityName);
        }
      }

      if (kDebugMode) debugPrint('🌍 Nessun dato meteo valido');
      return null;
    } on TimeoutException catch (e) {
      if (kDebugMode) debugPrint('🌍 TIMEOUT: $e');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('🌍 ERRORE getDailyAvgTemp: $e');
      return null;
    }
  }
}
