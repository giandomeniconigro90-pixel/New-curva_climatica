// lib/services/weather_service_geocoding.dart
//
// Helper isolato per il geocoding inverso, usato SOLO su piattaforme mobili.
// Su desktop (Windows/macOS/Linux) questo file non viene chiamato.

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

class GeocodingHelper {
  /// Restituisce il nome della città a partire dalle coordinate.
  /// In caso di errore restituisce 'Tua Posizione'.
  static Future<String> cityFromCoordinates(
    double latitude,
    double longitude, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(timeout);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final city = p.locality ??
            p.subAdministrativeArea ??
            p.administrativeArea ??
            'Tua Posizione';
        if (kDebugMode) debugPrint('\ud83c\udf0d Citt\u00e0 rilevata: $city');
        return city;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('\ud83c\udf0d Errore geocoding: $e');
    }
    return 'Tua Posizione';
  }
}
