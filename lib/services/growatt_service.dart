// lib/services/growatt_service.dart
//
// Integrazione Growatt cloud API per leggere i dati del fotovoltaico.
//
// Endpoint reali:
//   POST /login                          → login, raccoglie Set-Cookie multipli
//   POST /newTwoPlantAPI/getPlantData    → dati impianto oggi
//
// BUG FIX: http.Client di Dart consolida gli header duplicati con la
// virgola (RFC 7230 §3.2.2), ma alcuni server Growatt richiedono che
// JSESSIONID e SERVERID vengano inviati come cookie separati.
// Usiamo response.headers che in Dart è case-insensitive e unisce
// i valori con virgola. Splittiamo su virgola E punto-e-virgola per
// estrarre tutti i token nome=valore.

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

  final int plantId;
  final http.Client _client;

  /// Stringa cookie completa da inviare nell'header Cookie.
  /// Contiene tutti i token ricevuti nei Set-Cookie del login,
  /// es. "JSESSIONID=abc123; SERVERID=tomcat1"
  String? _sessionCookie;

  GrowattService({
    this.plantId = defaultPlantId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  bool get isLoggedIn => _sessionCookie != null;

  // -------------------------------------------------------------------------
  // Estrae tutti i cookie nome=valore da un header set-cookie.
  //
  // Dart's http.Response.headers unisce gli header duplicati con ", ".
  // Ogni direttiva Set-Cookie ha formato:
  //   name=value; Path=/; HttpOnly[; altri attributi]
  //
  // Strategia: splittiamo su "; " per separare le direttive, poi
  // teniamo solo i token che contengono "=" e non sono attributi noti
  // (Path, HttpOnly, Secure, SameSite, Max-Age, Expires, Domain).
  // -------------------------------------------------------------------------
  static String _extractCookies(String rawSetCookie) {
    final attributeNames = {
      'path', 'httponly', 'secure', 'samesite',
      'max-age', 'expires', 'domain',
    };

    final tokens = rawSetCookie.split(RegExp(r',(?=\s*\w+=)'));
    final cookiePairs = <String>{};

    for (final token in tokens) {
      final parts = token.split(';');
      for (final part in parts) {
        final trimmed = part.trim();
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx <= 0) continue;
        final name = trimmed.substring(0, eqIdx).trim().toLowerCase();
        if (attributeNames.contains(name)) continue;
        cookiePairs.add(trimmed.substring(0, trimmed.length)); // name=value originale
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

      if (response.statusCode != 200) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'HTTP ${response.statusCode}',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as int? ?? -1;

      if (result != 1) {
        return const GrowattError(
          GrowattErrorKind.authFailed,
          'Credenziali non valide. Verifica username/email e password di Shine Phone.',
        );
      }

      // Raccoglie TUTTI i Set-Cookie (JSESSIONID, SERVERID, ecc.)
      final rawCookie = response.headers['set-cookie'];
      debugPrint('[GrowattService] set-cookie raw: $rawCookie');

      if (rawCookie == null || rawCookie.isEmpty) {
        return const GrowattError(
          GrowattErrorKind.serverError,
          'Login OK ma nessun cookie di sessione ricevuto.',
        );
      }

      _sessionCookie = _extractCookies(rawCookie);
      debugPrint('[GrowattService] cookie estratto: $_sessionCookie');

      return GrowattOk(GrowattData(
        pvTodayKwh: 0,
        pvPowerW: 0,
        gridImportTodayKwh: 0,
        gridExportTodayKwh: 0,
        fetchedAt: DateTime.now().toUtc(),
      ));
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // FETCH DATI OGGI
  // -------------------------------------------------------------------------

  Future<GrowattResult> fetchToday() async {
    if (_sessionCookie == null) {
      return const GrowattError(
        GrowattErrorKind.sessionExpired,
        'Sessione non attiva. Eseguire il login prima di fetchToday().',
      );
    }

    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/newTwoPlantAPI/getPlantData'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': _sessionCookie!,
          'User-Agent': 'Mozilla/5.0',
          'Referer': '$_baseUrl/index',
        },
        body: {
          'plantId': plantId.toString(),
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[GrowattService] fetchToday status=${response.statusCode}');
      final preview = response.body.length > 400
          ? response.body.substring(0, 400)
          : response.body;
      debugPrint('[GrowattService] fetchToday body=$preview');

      if (response.statusCode == 302) {
        _sessionCookie = null;
        return const GrowattError(
          GrowattErrorKind.sessionExpired,
          'Sessione scaduta (redirect 302). Eseguire nuovamente il login.',
        );
      }

      if (response.statusCode != 200) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'HTTP ${response.statusCode}',
        );
      }

      // Controlla result:-1 SOLO dopo aver verificato che il body sia JSON
      if (response.body.contains('"result":-1')) {
        _sessionCookie = null;
        return const GrowattError(
          GrowattErrorKind.sessionExpired,
          'Sessione non riconosciuta dal server (result:-1). Eseguire nuovamente il login.',
        );
      }

      return _parsePlantData(response.body);
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // PARSER
  //
  // Struttura attesa:
  // { "result": 1, "obj": { "plantData": { "etoday": "12.5", ... } } }
  // Se plantData non esiste, prova a leggere obj direttamente.
  // -------------------------------------------------------------------------

  GrowattResult _parsePlantData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;

      final obj = json['obj'] as Map<String, dynamic>?;
      if (obj == null) {
        return GrowattError(
          GrowattErrorKind.parseError,
          'Campo "obj" mancante. Body: ${body.substring(0, body.length.clamp(0, 300))}',
        );
      }

      final plantData = (obj['plantData'] as Map<String, dynamic>?) ?? obj;

      double d(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      final double pvTodayKwh = d(plantData['etoday']);
      final double pvPowerKw  = d(plantData['currentPower']);
      final double gridExport = d(plantData['etoGridToday']);
      final double usedToday  = d(plantData['eUsedToday']);
      final double selfCons   = (pvTodayKwh - gridExport).clamp(0.0, double.infinity);
      final double gridImport = (usedToday - selfCons).clamp(0.0, double.infinity);

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
        'Errore parsing risposta Growatt: $e',
      );
    }
  }

  void dispose() => _client.close();
}
