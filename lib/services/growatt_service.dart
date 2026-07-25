// lib/services/growatt_service.dart
//
// Fix 302: il redirect era causato dall'endpoint sbagliato.
// Per impianti type=0 (inverter standard) l'endpoint corretto è:
//   POST /newTwoPlantAPI/getPlantCurrentInfo
// con body: plantId=<id>&type=<type>
//
// Usiamo anche un IOClient con followRedirects=false per evitare
// che Dart segua silenziosamente i redirect perdendo i cookie.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class GrowattData {
  final double pvTodayKwh;
  final double pvPowerW;
  final double gridImportTodayKwh;
  final double gridExportTodayKwh;

  double get selfConsumptionTodayKwh =>
      (pvTodayKwh - gridExportTodayKwh).clamp(0.0, double.infinity);

  final DateTime fetchedAt;

  const GrowattData({
    required this.pvTodayKwh,
    required this.pvPowerW,
    required this.gridImportTodayKwh,
    required this.gridExportTodayKwh,
    required this.fetchedAt,
  });

  @override
  String toString() =>
      'GrowattData(pv: ${pvTodayKwh.toStringAsFixed(2)} kWh, '
      'power: ${pvPowerW.toStringAsFixed(0)} W, '
      'import: ${gridImportTodayKwh.toStringAsFixed(2)} kWh, '
      'export: ${gridExportTodayKwh.toStringAsFixed(2)} kWh)';
}

// ---------------------------------------------------------------------------
// Result sealed
// ---------------------------------------------------------------------------

sealed class GrowattResult {
  const GrowattResult();
}

final class GrowattOk extends GrowattResult {
  final GrowattData data;
  const GrowattOk(this.data);
}

final class GrowattError extends GrowattResult {
  final GrowattErrorKind kind;
  final String message;
  const GrowattError(this.kind, this.message);
}

enum GrowattErrorKind {
  authFailed,
  sessionExpired,
  networkError,
  parseError,
  plantNotFound,
  serverError,
}

// ---------------------------------------------------------------------------
// GrowattService
// ---------------------------------------------------------------------------

class GrowattService {
  static const String _baseUrl = 'https://server.growatt.com';
  static const int defaultPlantId = 11037032;

  /// Tipo impianto letto dal cookie onePlantType (0 = inverter standard)
  static const int defaultPlantType = 0;

  final int plantId;
  final int plantType;
  final http.Client _client;
  String? _sessionCookie;

  GrowattService({
    this.plantId = defaultPlantId,
    this.plantType = defaultPlantType,
    http.Client? client,
  }) : _client = client ?? _buildNoRedirectClient();

  /// Client che NON segue i redirect automaticamente.
  /// Questo evita che il 302 di Growatt venga seguito perdendo i cookie.
  static http.Client _buildNoRedirectClient() {
    final httpClient = HttpClient()
      ..followRedirects = false
      ..maxConnectionsPerHost = 4;
    return IOClient(httpClient);
  }

  bool get isLoggedIn => _sessionCookie != null;

  // Estrae tutti i cookie nome=valore scartando gli attributi HTTP
  static String _extractCookies(String rawSetCookie) {
    final attributeNames = {
      'path', 'httponly', 'secure', 'samesite',
      'max-age', 'expires', 'domain',
    };
    final tokens = rawSetCookie.split(RegExp(r',(?=\s*\w+=)'));
    final cookiePairs = <String>{};
    for (final token in tokens) {
      for (final part in token.split(';')) {
        final trimmed = part.trim();
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx <= 0) continue;
        final name = trimmed.substring(0, eqIdx).trim().toLowerCase();
        if (attributeNames.contains(name)) continue;
        cookiePairs.add(trimmed);
      }
    }
    return cookiePairs.join('; ');
  }

  // -------------------------------------------------------------------------
  // LOGIN
  // -------------------------------------------------------------------------

  Future<GrowattResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/login'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0',
        },
        body: {
          'account': username,
          'password': password,
          'validateCode': '',
          'isReadPact': '0',
          'lang': 'it',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[GrowattService] login status=${response.statusCode}');
      debugPrint('[GrowattService] login headers=${response.headers}');

      // Con followRedirects=false il login potrebbe rispondere 302 verso /index
      // Il body JSON è comunque nel body della risposta 302 oppure nel 200.
      if (response.statusCode != 200 && response.statusCode != 302) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'Login HTTP ${response.statusCode}',
        );
      }

      // Tenta il parse del body solo se non è vuoto
      if (response.body.isNotEmpty) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final result = body['result'] as int? ?? -1;
          if (result != 1) {
            return const GrowattError(
              GrowattErrorKind.authFailed,
              'Credenziali non valide.',
            );
          }
        } catch (_) {
          // body non JSON (es. HTML redirect) — accettiamo se lo status è 302
          if (response.statusCode != 302) {
            return const GrowattError(
              GrowattErrorKind.authFailed,
              'Risposta login non valida.',
            );
          }
        }
      }

      final rawCookie = response.headers['set-cookie'];
      debugPrint('[GrowattService] set-cookie raw: $rawCookie');
      if (rawCookie == null || rawCookie.isEmpty) {
        return const GrowattError(
          GrowattErrorKind.serverError,
          'Login OK ma nessun cookie ricevuto.',
        );
      }

      _sessionCookie = _extractCookies(rawCookie);
      debugPrint('[GrowattService] cookie estratto: $_sessionCookie');

      return GrowattOk(GrowattData(
        pvTodayKwh: 0, pvPowerW: 0,
        gridImportTodayKwh: 0, gridExportTodayKwh: 0,
        fetchedAt: DateTime.now().toUtc(),
      ));
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // FETCH DATI OGGI
  //
  // Endpoint per impianto type=0 (inverter standard):
  //   POST /newTwoPlantAPI/getPlantCurrentInfo
  //   body: plantId=<id>&type=<type>
  //
  // Risposta attesa:
  // { "result": 1, "obj": { "etoday": "12.5", "currentPower": "1.23", ... } }
  // -------------------------------------------------------------------------

  Future<GrowattResult> fetchToday() async {
    if (_sessionCookie == null) {
      return const GrowattError(
        GrowattErrorKind.sessionExpired,
        'Sessione non attiva.',
      );
    }

    http.Response? response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl/newTwoPlantAPI/getPlantCurrentInfo'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': _sessionCookie!,
          'User-Agent': 'Mozilla/5.0',
          'Referer': '$_baseUrl/index',
        },
        body: {
          'plantId': plantId.toString(),
          'type': plantType.toString(),
        },
      ).timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }

    final status = response.statusCode;
    final rawBody = response.body.length > 600
        ? response.body.substring(0, 600)
        : response.body;

    debugPrint('[GrowattService] fetchToday status=$status');
    debugPrint('[GrowattService] fetchToday body=$rawBody');

    if (status == 302) {
      _sessionCookie = null;
      return GrowattError(
        GrowattErrorKind.sessionExpired,
        '[302] Cookie non accettato. Location: ${response.headers["location"]}',
      );
    }

    if (status != 200) {
      return GrowattError(
        GrowattErrorKind.serverError,
        '[HTTP $status] $rawBody',
      );
    }

    if (response.body.contains('"result":-1')) {
      _sessionCookie = null;
      return GrowattError(
        GrowattErrorKind.sessionExpired,
        '[result:-1] body: $rawBody',
      );
    }

    return _parsePlantData(response.body);
  }

  // -------------------------------------------------------------------------
  // PARSER
  //
  // Struttura attesa da getPlantCurrentInfo:
  // { "result": 1, "obj": { "etoday": "12.5", "currentPower": "1.23",
  //                          "etoGridToday": "3.2", "eUsedToday": "9.3" } }
  // -------------------------------------------------------------------------

  GrowattResult _parsePlantData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final obj = json['obj'] as Map<String, dynamic>?;
      if (obj == null) {
        return GrowattError(
          GrowattErrorKind.parseError,
          '"obj" mancante. body: ${body.substring(0, body.length.clamp(0, 400))}',
        );
      }

      // getPlantCurrentInfo può annidare in obj.plantData o mettere tutto in obj
      final data = (obj['plantData'] as Map<String, dynamic>?) ?? obj;

      double d(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      final pvTodayKwh = d(data['etoday']);
      final pvPowerKw  = d(data['currentPower']);
      final gridExport = d(data['etoGridToday']);
      final usedToday  = d(data['eUsedToday']);
      final selfCons   = (pvTodayKwh - gridExport).clamp(0.0, double.infinity);
      final gridImport = (usedToday - selfCons).clamp(0.0, double.infinity);

      return GrowattOk(GrowattData(
        pvTodayKwh: pvTodayKwh,
        pvPowerW: pvPowerKw * 1000,
        gridImportTodayKwh: gridImport,
        gridExportTodayKwh: gridExport,
        fetchedAt: DateTime.now().toUtc(),
      ));
    } catch (e) {
      return GrowattError(
        GrowattErrorKind.parseError,
        'Parsing error: $e | body: ${body.substring(0, body.length.clamp(0, 300))}',
      );
    }
  }

  void dispose() => _client.close();
}
