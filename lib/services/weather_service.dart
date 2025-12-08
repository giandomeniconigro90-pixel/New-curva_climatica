// lib/services/weather_service.dart

import 'dart:convert';
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
      // 1. Controlla servizi di localizzazione
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('🌍 GPS abilitato: $serviceEnabled');
      if (!serviceEnabled) return null;

      // 2. Controlla/Chiedi permessi
      LocationPermission permission = await Geolocator.checkPermission();
      print('🌍 Permesso iniziale: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print('🌍 Permesso dopo richiesta: $permission');
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) {
        print('🌍 Permesso negato per sempre');
        return null;
      }

      // 3. Prendi posizione GPS
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      print('🌍 Posizione: ${position.latitude}, ${position.longitude}');

      // 4. Reverse geocoding per il nome città
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
        print('🌍 Città rilevata: $cityName');
      } catch (e) {
        print('🌍 Errore geocoding: $e');
      }

      // 5. Chiamata Open-Meteo
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
            '?latitude=${position.latitude}&longitude=${position.longitude}'
            '&daily=temperature_2m_mean&timezone=auto&forecast_days=1',
      );
      print('🌍 URL meteo: $url');

      final response = await http.get(url);
      print('🌍 HTTP status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List temps = data['daily']['temperature_2m_mean'];
        if (temps.isNotEmpty) {
          final double avgTemp = (temps[0] as num).toDouble();
          print('🌍 Temperatura media: $avgTemp');
          return WeatherData(temp: avgTemp, locationName: cityName);
        }
      }

      print('🌍 Nessun dato meteo valido');
      return null;
    } catch (e) {
      print('🌍 ERRORE getDailyAvgTemp: $e');
      return null;
    }
  }
}
