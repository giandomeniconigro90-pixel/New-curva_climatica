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
  /// Ottieni temperatura e nome città attuale
  static Future<WeatherData?> getDailyAvgTemp() async {
    try {
      // 1. Controlla permessi GPS
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      // 2. Prendi posizione GPS
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low
      );

      // 3. TROVA IL NOME DELLA CITTÀ (Reverse Geocoding)
      String cityName = "Tua Posizione"; // Default più carino
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude
        );
        if (placemarks.isNotEmpty) {
          // Cerca prima la località (Comune), poi l'area amministrativa
          cityName = placemarks.first.locality ??
              placemarks.first.subAdministrativeArea ??
              placemarks.first.administrativeArea ??
              "Tua Posizione";
        }
      } catch (e) {
        // Se fallisce il geocoding, lasciamo "Tua Posizione" invece delle coordinate
        // print("Errore Geocoding: $e");
      }

      // 4. Chiama OpenMeteo per la Temperatura
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?'
              'latitude=${position.latitude}&longitude=${position.longitude}'
              '&daily=temperature_2m_mean&timezone=auto&forecast_days=1'
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> temps = data['daily']['temperature_2m_mean'];
        if (temps.isNotEmpty) {
          final double avgTemp = (temps[0] as num).toDouble();

          return WeatherData(temp: avgTemp, locationName: cityName);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
