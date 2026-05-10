// lib/services/weather_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'hive_storage.dart';
import 'weather_service_geocoding.dart';

import 'package:geolocator/geolocator.dart'
    if (dart.library.html) 'package:geolocator/geolocator.dart';

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

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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

  // ---------------------------------------------------------------------------
  // Fetch per nome città (override manuale)
  // ---------------------------------------------------------------------------
  static Future<WeatherData?> _fetchByCityName(String cityName) async {
    try {
      if (kDebugMode) debugPrint('\ud83c\udf0d Fetch meteo per città: $cityName');
      final geoUrl = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeComponent(cityName)}&count=1&language=it&format=json',
      );
      final geoResp = await http.get(geoUrl).timeout(_timeout);
      if (geoResp.statusCode != 200) return null;
      final geoData = json.decode(geoResp.body);
      final results = geoData['results'] as List?;
      if (results == null || results.isEmpty) {
        if (kDebugMode) debugPrint('\ud83c\udf0d Città non trovata: $cityName');
        return null;
      }
      final double lat = (results[0]['latitude'] as num).toDouble();
      final double lon = (results[0]['longitude'] as num).toDouble();
      final String resolvedName = results[0]['name'] as String? ?? cityName;

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&daily=temperature_2m_mean&timezone=auto&forecast_days=1',
      );
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List temps = data['daily']['temperature_2m_mean'];
        if (temps.isNotEmpty) {
          final double avgTemp = (temps[0] as num).toDouble();
          if (kDebugMode) debugPrint('\ud83c\udf0d Temp ($resolvedName): $avgTemp\u00b0C');
          final result = WeatherData(temp: avgTemp, locationName: resolvedName);
          await _writeCache(result);
          return result;
        }
      }
      return null;
    } on TimeoutException catch (e) {
      if (kDebugMode) debugPrint('\ud83c\udf0d TIMEOUT fetchByCityName: $e');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('\ud83c\udf0d ERRORE fetchByCityName: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Fetch via GPS (solo mobile)
  // ---------------------------------------------------------------------------
  static Future<WeatherData?> _fetchByGps() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(_timeout);

      final cityName = await GeocodingHelper.cityFromCoordinates(
        position.latitude,
        position.longitude,
        timeout: _timeout,
      );
      if (kDebugMode) debugPrint('\ud83c\udf0d GPS → $cityName');

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${position.latitude}&longitude=${position.longitude}'
        '&daily=temperature_2m_mean&timezone=auto&forecast_days=1',
      );
      final response = await http.get(url).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('Timeout richiesta meteo'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List temps = data['daily']['temperature_2m_mean'];
        if (temps.isNotEmpty) {
          final double avgTemp = (temps[0] as num).toDouble();
          if (kDebugMode) debugPrint('\ud83c\udf0d Temp GPS ($cityName): $avgTemp\u00b0C');
          final result = WeatherData(temp: avgTemp, locationName: cityName);
          await _writeCache(result);
          return result;
        }
      }
      return null;
    } on TimeoutException catch (e) {
      if (kDebugMode) debugPrint('\ud83c\udf0d TIMEOUT GPS: $e');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('\ud83c\udf0d ERRORE GPS: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Entry point principale
  // ---------------------------------------------------------------------------
  static Future<WeatherData?> getDailyAvgTemp() async {
    // 1. Cache ancora valida? Restituisce senza log rumorosi.
    final cached = _readCache();
    if (cached != null) return cached;

    // 2. Override città manuale?
    final cityOverride = AppStorage.getCityOverride();
    if (cityOverride != null) {
      return _fetchByCityName(cityOverride);
    }

    // 3. GPS — solo su mobile.
    if (_isDesktop) {
      if (kDebugMode) debugPrint('\ud83d\udda5\ufe0f Desktop: GPS non disponibile.');
      return null;
    }

    return _fetchByGps();
  }
}
