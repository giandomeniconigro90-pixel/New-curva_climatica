// lib/services/growatt_service.dart
//
// Flusso corretto (reverse-engineered dalla libreria growattServer Python):
//
//  STEP 1 — GET /device/getDevicesByPlantList?plantId=<id>
//            Restituisce la lista inverter con i serial number (sn)
//
//  STEP 2 — POST /newInverterAPI.do
//            body: action=getInverterData&inverterId=<sn>&type=1
//            Restituisce dati energetici dell'inverter
//
// Riferimento: https://github.com/indykoning/PyPi_GrowattServer

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
  String? _sessionCookie;

  /// Serial number dell'inverter, ricavato al primo fetchToday()
  String? _inverterSn;

  GrowattService({
    this.plantId = defaultPlantId,
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

  String _preview(String s, [int max = 600]) =>
      s.length > max ? s.substring(0, max) : s;

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
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        },
        body: {
          'account': username,
          'password': password,
          'validateCode': '',
          'isReadPact': '0',
          'lang': 'it',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[Growatt] login status=${response.statusCode}');

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
      debugPrint('[Growatt] set-cookie raw: $rawCookie');
      if (rawCookie == null || rawCookie.isEmpty) {
        return const GrowattError(
          GrowattErrorKind.serverError,
          'Login OK ma nessun cookie ricevuto.',
        );
      }

      _sessionCookie = _extractCookies(rawCookie);
      _inverterSn = null; // reset SN ad ogni login
      debugPrint('[Growatt] cookie: $_sessionCookie');

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
  // STEP 1 — Ricava il serial number dell'inverter
  //
  // GET /device/getDevicesByPlantList?plantId=<id>&currPage=1
  // Risposta: { "result": 1, "obj": { "datas": [ { "sn": "...", ... } ] } }
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _fetchInverterSn() async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/device/getDevicesByPlantList?plantId=$plantId&currPage=1',
      );
      final response = await _client.get(
        uri,
        headers: {
          'Cookie': _sessionCookie!,
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          'Referer': '$_baseUrl/index',
        },
      ).timeout(const Duration(seconds: 15));

      final rawBody = _preview(response.body);
      debugPrint('[Growatt] getDevicesByPlantList status=${response.statusCode}');
      debugPrint('[Growatt] getDevicesByPlantList body=$rawBody');

      if (response.statusCode != 200) {
        return GrowattError(
          GrowattErrorKind.serverError,
          '[step1 HTTP ${response.statusCode}] $rawBody',
        );
      }

      if (response.body.trimLeft().startsWith('<') ||
          response.body.contains('"result":-1')) {
        _sessionCookie = null;
        return const GrowattError(
          GrowattErrorKind.sessionExpired,
          'Sessione scaduta al recupero SN inverter.',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final obj = json['obj'] as Map<String, dynamic>?;
      final datas = obj?['datas'] as List<dynamic>?;

      if (datas == null || datas.isEmpty) {
        return GrowattError(
          GrowattErrorKind.plantNotFound,
          'Nessun inverter trovato per plantId=$plantId. body=$rawBody',
        );
      }

      final first = datas.first as Map<String, dynamic>;
      _inverterSn = (first['sn'] ?? first['deviceSn'] ?? first['datalogSn'])
          ?.toString();

      if (_inverterSn == null || _inverterSn!.isEmpty) {
        return GrowattError(
          GrowattErrorKind.parseError,
          'SN inverter non trovato. datas[0]=$first',
        );
      }

      debugPrint('[Growatt] inverter SN: $_inverterSn');
      return null; // null = successo, continua
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 2 — Dati energetici dell'inverter
  //
  // POST /newInverterAPI.do
  // body: action=getInverterData&inverterId=<sn>&type=1
  // Risposta: { "result": 1, "obj": { "etoday": "12.5", ... } }
  // -------------------------------------------------------------------------

  Future<GrowattResult> fetchToday() async {
    if (_sessionCookie == null) {
      return const GrowattError(
        GrowattErrorKind.sessionExpired,
        'Sessione non attiva.',
      );
    }

    // Step 1: ricava SN se non ancora in cache
    if (_inverterSn == null) {
      final snError = await _fetchInverterSn();
      if (snError != null) return snError;
    }

    // Step 2: dati inverter
    http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl/newInverterAPI.do'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': _sessionCookie!,
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          'Referer': '$_baseUrl/index',
        },
        body: {
          'action': 'getInverterData',
          'inverterId': _inverterSn!,
          'type': '1',
        },
      ).timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }

    final rawBody = _preview(response.body);
    debugPrint('[Growatt] newInverterAPI status=${response.statusCode}');
    debugPrint('[Growatt] newInverterAPI body=$rawBody');

    if (response.statusCode != 200) {
      return GrowattError(
        GrowattErrorKind.serverError,
        '[HTTP ${response.statusCode}] $rawBody',
      );
    }

    if (response.body.trimLeft().startsWith('<') ||
        response.body.contains('"result":-1')) {
      _sessionCookie = null;
      return GrowattError(
        GrowattErrorKind.sessionExpired,
        '[result:-1] $rawBody',
      );
    }

    return _parsePlantData(response.body);
  }

  // -------------------------------------------------------------------------
  // PARSER
  //
  // Struttura da /newInverterAPI.do:
  // { "result": 1, "obj": { "etoday": "12.5", "pac": "1230",
  //                          "etoGridToday": "3.2", ... } }
  // -------------------------------------------------------------------------

  GrowattResult _parsePlantData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final obj = json['obj'] as Map<String, dynamic>?;
      if (obj == null) {
        return GrowattError(
          GrowattErrorKind.parseError,
          '"obj" mancante. body: ${_preview(body, 400)}',
        );
      }

      double d(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      final pvTodayKwh = d(obj['etoday']);
      // pac = potenza istantanea in W
      final pvPowerW   = d(obj['pac']);
      final gridExport = d(obj['etoGridToday']);
      final usedToday  = d(obj['eUsedToday']);
      final selfCons   = (pvTodayKwh - gridExport).clamp(0.0, double.infinity);
      final gridImport = (usedToday - selfCons).clamp(0.0, double.infinity);

      debugPrint('[Growatt] parsed: pv=$pvTodayKwh kWh, power=$pvPowerW W');

      return GrowattOk(GrowattData(
        pvTodayKwh: pvTodayKwh,
        pvPowerW: pvPowerW,
        gridImportTodayKwh: gridImport,
        gridExportTodayKwh: gridExport,
        fetchedAt: DateTime.now().toUtc(),
      ));
    } catch (e) {
      return GrowattError(
        GrowattErrorKind.parseError,
        'Parsing error: $e | body: ${_preview(body, 300)}',
      );
    }
  }

  void dispose() => _client.close();
}
