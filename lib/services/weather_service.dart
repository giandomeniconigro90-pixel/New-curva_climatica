// lib/services/weather_service.dart
//
// Refactor #5 — WeatherService con:
//   • Sealed class WeatherResult (fresh / stale / unavailable)
//   • Stale-while-revalidate: restituisce cache scaduta mentre aggiorna in bg
//   • Retry con backoff esponenziale (max 2 tentativi)
//   • Fallback offline esplicito: mai null, sempre un WeatherResult
//   • Errori differenziati: timeout, no-connection, server-error, parse-error

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

// ─────────────────────────────────────────────────────────────────────────────
// Modello dati
// ─────────────────────────────────────────────────────────────────────────────

class WeatherData {
  final double temp;
  final String locationName;
  final DateTime fetchedAt;

  WeatherData({
    required this.temp,
    required this.locationName,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();
}

/// Tipo di errore meteo — permette all'UI di mostrare messaggi specifici.
enum WeatherErrorKind {
  timeout,
  noConnection,
  serverError,
  parseError,
  locationDenied,
  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
// Sealed result type
// ─────────────────────────────────────────────────────────────────────────────

sealed class WeatherResult {
  const WeatherResult();
}

/// Dato fresco o quasi-fresco (fetch OK, cache < [WeatherService.cacheDuration]).
final class WeatherFresh extends WeatherResult {
  final WeatherData data;
  const WeatherFresh(this.data);
}

/// Dato stale (cache scaduta, rete non raggiungibile).
/// Il campo [data] contiene l'ultimo valore noto.
/// [error] descrive il motivo per cui il refresh è fallito.
final class WeatherStale extends WeatherResult {
  final WeatherData data;
  final WeatherErrorKind error;
  const WeatherStale(this.data, this.error);
}

/// Nessun dato disponibile: né cache né rete.
final class WeatherUnavailable extends WeatherResult {
  final WeatherErrorKind error;
  final String? message;
  const WeatherUnavailable(this.error, {this.message});
}

// ─────────────────────────────────────────────────────────────────────────────
// WeatherService
// ─────────────────────────────────────────────────────────────────────────────

class WeatherService {
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration cacheDuration = Duration(minutes: 30);

  /// Finestra entro cui la cache è considerata "stale ma usabile".
  /// Oltre [_staleLimit] il dato viene scartato anche come fallback.
  static const Duration _staleLimit = Duration(hours: 6);

  static const String _cacheBoxName = 'clima_sense_box';
  static const String _keyTemp = 'weatherCacheTemp';
  static const String _keyCity = 'weatherCacheCity';
  static const String _keyTimestamp = 'weatherCacheTimestamp';

  /// Tentativi max per ogni fetch prima di arrendersi.
  static const int _maxRetries = 2;

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  // -------------------------------------------------------------------------
  // Cache helpers
  // -------------------------------------------------------------------------

  static WeatherData? _readCache({bool allowStale = false}) {
    try {
      final box = Hive.box(_cacheBoxName);
      final String? tsStr = box.get(_keyTimestamp);
      if (tsStr == null) return null;
      final DateTime? ts = DateTime.tryParse(tsStr);
      if (ts == null) return null;
      final age = DateTime.now().difference(ts);
      final double? temp = box.get(_keyTemp);
      final String? city = box.get(_keyCity);
      if (temp == null || city == null) return null;

      // Cache fresca: sempre valida.
      if (age <= cacheDuration) {
        return WeatherData(temp: temp, locationName: city, fetchedAt: ts);
      }
      // Cache stale: valida solo se richiesto e non troppo vecchia.
      if (allowStale && age <= _staleLimit) {
        return WeatherData(temp: temp, locationName: city, fetchedAt: ts);
      }
      return null;
    } catch (e) {
      debugPrint('[WeatherService] _readCache error: $e');
      return null;
    }
  }

  static Future<void> _writeCache(WeatherData data) async {
    try {
      final box = Hive.box(_cacheBoxName);
      await box.put(_keyTemp, data.temp);
      await box.put(_keyCity, data.locationName);
      await box.put(_keyTimestamp, data.fetchedAt.toIso8601String());
    } catch (e) {
      debugPrint('[WeatherService] _writeCache error: $e');
    }
  }

  static Future<void> clearCache() async {
    try {
      final box = Hive.box(_cacheBoxName);
      await box.delete(_keyTemp);
      await box.delete(_keyCity);
      await box.delete(_keyTimestamp);
    } catch (e) {
      debugPrint('[WeatherService] clearCache error: $e');
    }
  }

  static int? getCacheAgeMinutes() {
    try {
      final box = Hive.box(_cacheBoxName);
      final String? tsStr = box.get(_keyTimestamp);
      if (tsStr == null) return null;
      final DateTime? ts = DateTime.tryParse(tsStr);
      if (ts == null) return null;
      final age = DateTime.now().difference(ts);
      if (age > cacheDuration) return null;
      return age.inMinutes;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Entry point principale — restituisce sempre un WeatherResult non-null
  // -------------------------------------------------------------------------

  /// Flusso stale-while-revalidate:
  ///   1. Cache fresca  → [WeatherFresh] immediato, nessuna rete
  ///   2. Cache stale   → [WeatherFresh] (stale) + refresh in background
  ///   3. No cache      → fetch con retry, poi:
  ///        OK   → [WeatherFresh]
  ///        FAIL → [WeatherUnavailable]
  static Future<WeatherResult> getDailyAvgTemp() async {
    // 1. Cache fresca?
    final fresh = _readCache(allowStale: false);
    if (fresh != null) {
      _log('\u2705 Cache fresca (${getCacheAgeMinutes()}min)');
      return WeatherFresh(fresh);
    }

    // 2. Cache stale? Restituisci subito e aggiorna in background.
    final stale = _readCache(allowStale: true);
    if (stale != null) {
      _log('\u23f3 Cache stale — avvio refresh in background');
      unawaited(_refreshInBackground());
      return WeatherFresh(stale); // UI non si blocca
    }

    // 3. Nessuna cache: fetch sincrono.
    return _fetchWithFallback();
  }

  /// Versione che espone il tipo stale all'UI (per mostrare badge "aggiornando…")
  static Future<WeatherResult> getDailyAvgTempVerbose() async {
    final fresh = _readCache(allowStale: false);
    if (fresh != null) return WeatherFresh(fresh);

    final stale = _readCache(allowStale: true);
    if (stale != null) {
      unawaited(_refreshInBackground());
      // Qui restituiamo Stale così l'UI può mostrare un indicatore
      return WeatherStale(stale, WeatherErrorKind.unknown);
    }

    return _fetchWithFallback();
  }

  // -------------------------------------------------------------------------
  // Refresh background (fire & forget)
  // -------------------------------------------------------------------------

  static Future<void> _refreshInBackground() async {
    try {
      final result = await _fetchWithFallback();
      if (result is WeatherFresh) {
        _log('\ud83d\udd04 Refresh background completato: ${result.data.temp}\u00b0C');
      }
    } catch (e) {
      _log('\ud83d\udd04 Refresh background fallito: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Fetch con retry
  // -------------------------------------------------------------------------

  static Future<WeatherResult> _fetchWithFallback() async {
    final cityOverride = AppStorage.getCityOverride();
    if (cityOverride != null) {
      return _fetchByCityNameWithRetry(cityOverride);
    }
    if (_isDesktop) {
      _log('\ud83d\udda5\ufe0f Desktop: GPS non disponibile.');
      return const WeatherUnavailable(WeatherErrorKind.noConnection,
          message: 'Imposta una citt\u00e0 nelle impostazioni.');
    }
    return _fetchByGpsWithRetry();
  }

  /// Ritenta [_maxRetries] volte con backoff 1s, 2s.
  static Future<WeatherResult> _fetchByCityNameWithRetry(String cityName) async {
    WeatherErrorKind lastError = WeatherErrorKind.unknown;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      final result = await _fetchByCityNameOnce(cityName);
      if (result is WeatherFresh) return result;
      if (result is WeatherUnavailable) lastError = result.error;
      if (attempt < _maxRetries) {
        _log('\u21aa Retry $attempt/$_maxRetries per citt\u00e0 "$cityName" tra ${attempt}s...');
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    // Fallback cache stale dopo tutti i retry
    final stale = _readCache(allowStale: true);
    if (stale != null) return WeatherStale(stale, lastError);
    return WeatherUnavailable(lastError);
  }

  static Future<WeatherResult> _fetchByGpsWithRetry() async {
    WeatherErrorKind lastError = WeatherErrorKind.unknown;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      final result = await _fetchByGpsOnce();
      if (result is WeatherFresh) return result;
      if (result is WeatherUnavailable) lastError = result.error;
      // Non ritentiamo se GPS è negato: è un errore permanente.
      if (lastError == WeatherErrorKind.locationDenied) break;
      if (attempt < _maxRetries) {
        _log('\u21aa Retry GPS $attempt/$_maxRetries tra ${attempt}s...');
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    final stale = _readCache(allowStale: true);
    if (stale != null) return WeatherStale(stale, lastError);
    return WeatherUnavailable(lastError);
  }

  // -------------------------------------------------------------------------
  // Fetch per nome città (singolo tentativo)
  // -------------------------------------------------------------------------

  static Future<WeatherResult> _fetchByCityNameOnce(String cityName) async {
    try {
      _log('\ud83c\udf0d Fetch citt\u00e0: $cityName');
      final geoUrl = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeComponent(cityName)}&count=1&language=it&format=json',
      );
      final geoResp = await http.get(geoUrl).timeout(_timeout);
      if (geoResp.statusCode != 200) {
        return WeatherUnavailable(
          WeatherErrorKind.serverError,
          message: 'Geocoding HTTP ${geoResp.statusCode}',
        );
      }

      final geoData = json.decode(geoResp.body);
      final results = geoData['results'] as List?;
      if (results == null || results.isEmpty) {
        return WeatherUnavailable(
          WeatherErrorKind.parseError,
          message: 'Citt\u00e0 "$cityName" non trovata.',
        );
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
      if (response.statusCode != 200) {
        return WeatherUnavailable(
          WeatherErrorKind.serverError,
          message: 'Forecast HTTP ${response.statusCode}',
        );
      }

      final data = json.decode(response.body);
      final List? temps = data['daily']?['temperature_2m_mean'] as List?;
      if (temps == null || temps.isEmpty) {
        return const WeatherUnavailable(WeatherErrorKind.parseError,
            message: 'Risposta meteo senza dati temperatura.');
      }

      final result = WeatherData(
        temp: (temps[0] as num).toDouble(),
        locationName: resolvedName,
      );
      await _writeCache(result);
      _log('\ud83c\udf0d OK $resolvedName: ${result.temp}\u00b0C');
      return WeatherFresh(result);
    } on TimeoutException {
      return const WeatherUnavailable(WeatherErrorKind.timeout);
    } on SocketException {
      return const WeatherUnavailable(WeatherErrorKind.noConnection);
    } on FormatException {
      return const WeatherUnavailable(WeatherErrorKind.parseError);
    } catch (e) {
      _log('\ud83c\udf0d ERRORE fetchByCityNameOnce: $e');
      return WeatherUnavailable(WeatherErrorKind.unknown, message: '$e');
    }
  }

  // -------------------------------------------------------------------------
  // Fetch via GPS (singolo tentativo)
  // -------------------------------------------------------------------------

  static Future<WeatherResult> _fetchByGpsOnce() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const WeatherUnavailable(WeatherErrorKind.locationDenied,
            message: 'Servizio GPS disabilitato.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const WeatherUnavailable(WeatherErrorKind.locationDenied,
            message: 'Permesso GPS negato.');
      }

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
      _log('\ud83d\udccd GPS \u2192 $cityName (${position.latitude}, ${position.longitude})');

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${position.latitude}&longitude=${position.longitude}'
        '&daily=temperature_2m_mean&timezone=auto&forecast_days=1',
      );
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode != 200) {
        return WeatherUnavailable(
          WeatherErrorKind.serverError,
          message: 'Forecast HTTP ${response.statusCode}',
        );
      }

      final data = json.decode(response.body);
      final List? temps = data['daily']?['temperature_2m_mean'] as List?;
      if (temps == null || temps.isEmpty) {
        return const WeatherUnavailable(WeatherErrorKind.parseError);
      }

      final result = WeatherData(
        temp: (temps[0] as num).toDouble(),
        locationName: cityName,
      );
      await _writeCache(result);
      _log('\ud83d\udccd OK GPS $cityName: ${result.temp}\u00b0C');
      return WeatherFresh(result);
    } on TimeoutException {
      return const WeatherUnavailable(WeatherErrorKind.timeout);
    } on SocketException {
      return const WeatherUnavailable(WeatherErrorKind.noConnection);
    } on FormatException {
      return const WeatherUnavailable(WeatherErrorKind.parseError);
    } catch (e) {
      _log('\ud83d\udccd ERRORE _fetchByGpsOnce: $e');
      return WeatherUnavailable(WeatherErrorKind.unknown, message: '$e');
    }
  }

  // -------------------------------------------------------------------------
  // Retrocompatibilità: vecchia firma getDailyAvgTemp() che restituisce
  // WeatherData? — usata da widget che non sono ancora stati migrati.
  // -------------------------------------------------------------------------

  /// @deprecated Usa [getDailyAvgTemp] che restituisce [WeatherResult].
  static Future<WeatherData?> getDailyAvgTempLegacy() async {
    final result = await getDailyAvgTemp();
    return switch (result) {
      WeatherFresh(:final data) => data,
      WeatherStale(:final data) => data,
      WeatherUnavailable() => null,
    };
  }

  // -------------------------------------------------------------------------
  // Logging
  // -------------------------------------------------------------------------

  static void _log(String msg) {
    if (kDebugMode) debugPrint('[WeatherService] $msg');
  }
}
