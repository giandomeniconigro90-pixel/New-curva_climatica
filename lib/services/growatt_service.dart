// lib/services/growatt_service.dart
//
// Fix build Android: HttpClient.followRedirects non esiste su dart:_http mobile.
// Invece di IOClient, usiamo http.Client() standard e gestiamo il 302
// manualmente nel codice (non seguiamo il redirect, restituiamo errore leggibile).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  static const int defaultPlantType = 0;

  final int plantId;
  final int plantType;
  final http.Client _client;
  String? _sessionCookie;

  GrowattService({
    this.plantId = defaultPlantId,
    this.plantType = defaultPlantType,
    http.Client? client,
  }) : _client = client ?? http.Client();

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

      if (response.statusCode != 200) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'Login HTTP ${response.statusCode}',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as int? ?? -1;
      if (result != 1) {
        return const GrowattError(
          GrowattErrorKind.authFailed,
          'Credenziali non valide.',
        );
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
  // NOTA: http.Client di Dart segue i redirect automaticamente.
  // Se il server risponde 302, il client lo segue e la risposta finale
  // potrebbe essere la pagina di login HTML (status 200 ma body HTML).
  // Per questo controlliamo se il body inizia con '<' (HTML) prima
  // di tentare il parse JSON.
  //
  // Endpoint: POST /newTwoPlantAPI/getPlantCurrentInfo
  // body: plantId=<id>&type=<plantType>
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

    if (status != 200) {
      return GrowattError(
        GrowattErrorKind.serverError,
        '[HTTP $status] $rawBody',
      );
    }

    // Se il body e' HTML il client ha seguito un redirect verso la pagina di login
    final trimmed = response.body.trimLeft();
    if (trimmed.startsWith('<')) {
      _sessionCookie = null;
      return GrowattError(
        GrowattErrorKind.sessionExpired,
        'Il server ha reindirizzato al login (risposta HTML).\n'
        'Probabilmente il cookie non viene accettato.\n'
        'body preview: ${rawBody.substring(0, rawBody.length.clamp(0, 200))}',
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
