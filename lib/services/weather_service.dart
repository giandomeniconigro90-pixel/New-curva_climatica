// lib/services/weather_service.dart

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
  /// Ottieni temperatura media giornaliera e nome città attuale
  static Future<WeatherData?> getDailyAvgTemp() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('🌍 GPS abilitato: $serviceEnabled');
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('🌍 Permesso iniziale: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('🌍 Permesso dopo richiesta: $permission');
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('🌍 Permesso negato per sempre');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      debugPrint('🌍 Posizione: ${position.latitude}, ${position.longitude}');

      String cityName = "Tua Posizione";
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          cityName = p.locality ??
              p.subAdministrativeArea ??
              p.administrativeArea ??
              "Tua Posizione";
        }
        debugPrint('🌍 Città rilevata: $cityName');
      } catch (e) {
        debugPrint('🌍 Errore geocoding: $e');
      }

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
            '?latitude=${position.latitude}&longitude=${position.longitude}'
            '&daily=temperature_2m_mean&timezone=auto&forecast_days=1',
      );
      debugPrint('🌍 URL meteo: $url');

      final response = await http.get(url);
      debugPrint('🌍 HTTP status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List temps = data['daily']['temperature_2m_mean'];
        if (temps.isNotEmpty) {
          final double avgTemp = (temps[0] as num).toDouble();
          debugPrint('🌍 Temperatura media: $avgTemp');
          return WeatherData(temp: avgTemp, locationName: cityName);
        }
      }

      debugPrint('🌍 Nessun dato meteo valido');
      return null;
    } catch (e) {
      debugPrint('🌍 ERRORE getDailyAvgTemp: $e');
      return null;
    }
  }
}
