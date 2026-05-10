// lib/services/weather_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

import 'weather_service_geocoding.dart';

class WeatherData {
  final double temp;
  final String locationName;

  WeatherData({required this.temp, required this.locationName});
}

class WeatherService {
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration cacheDuration = Duration(minutes: 30);

  static const String _cacheBoxName = 'clima_sense_box';
  static const String _keyTemp = 'weatherCacheTemp';
  static const String _keyCity = 'weatherCacheCity';
  static const String _keyTimestamp = 'weatherCacheTimestamp';

  static WeatherData? _readCache() {
    final box = Hive.box(_cacheBoxName);
    final String? tsStr = box.get(_keyTimestamp);
    if (tsStr == null) return null;
    final DateTime? ts = DateTime.tryParse(tsStr);
    if (ts == null) return null;
    if (DateTime.now().difference(ts) > cacheDuration) return null;
    final double? temp = box.get(_keyTemp);
    final String? city = box.get(_keyCity);
    if (temp == null || city == null) return null;
    if (kDebugMode) debugPrint('\u2600\ufe0f Cache meteo valida (aggiornata: $tsStr)');
    return WeatherData(temp: temp, locationName: city);
  }

  static Future<void> _writeCache(WeatherData data) async {
    final box = Hive.box(_cacheBoxName);
    await box.put(_keyTemp, data.temp);
    await box.put(_keyCity, data.locationName);
    await box.put(_keyTimestamp, DateTime.now().toIso8601String());
  }

  static Future<void> clearCache() async {
    final box = Hive.box(_cacheBoxName);
    await box.delete(_keyTemp);
    await box.delete(_keyCity);
    await box.delete(_keyTimestamp);
  }

  static int? getCacheAgeMinutes() {
    final box = Hive.box(_cacheBoxName);
    final String? tsStr = box.get(_keyTimestamp);
    if (tsStr == null) return null;
    final DateTime? ts = DateTime.tryParse(tsStr);
    if (ts == null) return null;
    final age = DateTime.now().difference(ts);
    if (age > cacheDuration) return null;
    return age.inMinutes;
  }

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  static Future<WeatherData?> getDailyAvgTemp() async {
    final cached = _readCache();
    if (cached != null) return cached;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (kDebugMode) debugPrint('\ud83c\udf0d GPS abilitato: $serviceEnabled');
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (kDebugMode) debugPrint('\ud83c\udf0d Permesso iniziale: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (kDebugMode) debugPrint('\ud83c\udf0d Permesso dopo richiesta: $permission');
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) debugPrint('\ud83c\udf0d Permesso negato per sempre');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(_timeout);
      if (kDebugMode) debugPrint('\ud83c\udf0d Posizione ottenuta');

      String cityName = 'Tua Posizione';
      if (!_isDesktop) {
        cityName = await GeocodingHelper.cityFromCoordinates(
          position.latitude,
          position.longitude,
          timeout: _timeout,
        );
      } else {
        final lat = position.latitude.toStringAsFixed(2);
        final lon = position.longitude.toStringAsFixed(2);
        cityName = '$lat\u00b0N, $lon\u00b0E';
      }
      if (kDebugMode) debugPrint('\ud83c\udf0d Localit\u00e0: $cityName');

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${position.latitude}&longitude=${position.longitude}'
        '&daily=temperature_2m_mean&timezone=auto&forecast_days=1',
      );

      final response = await http.get(url).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('Timeout richiesta meteo'),
      );
      if (kDebugMode) debugPrint('\ud83c\udf0d HTTP status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List temps = data['daily']['temperature_2m_mean'];
        if (temps.isNotEmpty) {
          final double avgTemp = (temps[0] as num).toDouble();
          if (kDebugMode) debugPrint('\ud83c\udf0d Temperatura media: $avgTemp\u00b0C');
          final result = WeatherData(temp: avgTemp, locationName: cityName);
          await _writeCache(result);
          return result;
        }
      }

      if (kDebugMode) debugPrint('\ud83c\udf0d Nessun dato meteo valido');
      return null;
    } on TimeoutException catch (e) {
      if (kDebugMode) debugPrint('\ud83c\udf0d TIMEOUT: $e');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('\ud83c\udf0d ERRORE getDailyAvgTemp: $e');
      return null;
    }
  }
}
