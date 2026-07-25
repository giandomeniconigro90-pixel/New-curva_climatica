// lib/services/growatt_service.dart
//
// Flusso autenticazione Growatt (server.growatt.com):
//
//  STEP 1 — POST https://server.growatt.com/newLoginAPI.do
//            body form: userName=<user>&password=<growattMd5(pass)>
//            Growatt MD5: md5 normale ma ogni byte hex che inizia con '0' → 'c'
//            Risposta: { "result": 1, "back": { "user": { "id": ... } } }
//            Cookie: JSESSIONID=...
//
//  STEP 2 — POST https://server.growatt.com/index/getPlantListTitle
//            Cookie: JSESSIONID=...
//            Risposta: { "result": 1, "back": { "data": [{"id":"11037032",...}] } }
//
//  STEP 3 — POST https://server.growatt.com/panel/getDevicesByPlantList
//            body form: plantId=11037032&currPage=1
//            Risposta: { "result": 1, "obj": { "datas": [{"sn":"MVP1EZ5054",...}] } }
//
//  STEP 4 — POST https://server.growatt.com/panel/min/getMinEnergyDayChart
//            body form: sn=MVP1EZ5054&date=2026-07-25
//            Risposta: { "result": 1, "obj": { "eacToday": "12.5", "pac": "1230", ... } }
//
// Riferimento: https://github.com/Sjord/growatt_api_client
// MD5 Growatt: ogni coppia hex che inizia con '0' viene sostituita da 'c' + cifra

import 'dart:convert';
import 'package:crypto/crypto.dart';
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

  final String username;
  final String password;
  final http.Client _client;

  String? _sessionCookie;
  String? _plantId;
  String? _deviceSn;

  GrowattService({
    required this.username,
    required this.password,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String _preview(String s, [int max = 600]) =>
      s.length > max ? s.substring(0, max) : s;

  double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Growatt MD5: MD5 normale, ma ogni byte hex che inizia con '0' → 'c'
  /// Es: "0a" → "ca", "0f" → "cf", "1a" → "1a" (invariato)
  /// Riferimento: https://github.com/Sjord/growatt_api_client
  String _growattMd5(String input) {
    final hash = md5.convert(utf8.encode(input)).toString();
    final buf = StringBuffer();
    for (var i = 0; i < hash.length; i += 2) {
      final pair = hash.substring(i, i + 2);
      buf.write(pair[0] == '0' ? 'c${pair[1]}' : pair);
    }
    return buf.toString();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        if (_sessionCookie != null) 'Cookie': _sessionCookie!,
      };

  // -------------------------------------------------------------------------
  // STEP 1 — Login
  // POST /newLoginAPI.do  body: userName=<user>&password=<growattMd5>
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _login() async {
    try {
      final hashedPass = _growattMd5(password);
      debugPrint('[Growatt] POST /newLoginAPI.do (user=$username)');

      final response = await _client.post(
        Uri.parse('$_baseUrl/newLoginAPI.do'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        },
        body: {
          'userName': username,
          'password': hashedPass,
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('[Growatt] POST /newLoginAPI.do status=${response.statusCode}');
      debugPrint('[Growatt] POST /newLoginAPI.do body=${_preview(response.body)}');

      if (response.statusCode != 200) {
        return GrowattError(GrowattErrorKind.authFailed,
            'Login HTTP ${response.statusCode}');
      }

      // Estrai cookie JSESSIONID
      final setCookie = response.headers['set-cookie'] ?? '';
      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie);
      if (match != null) {
        _sessionCookie = 'JSESSIONID=${match.group(1)}';
        debugPrint('[Growatt] session cookie ok');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // newLoginAPI.do: { "result": 1, "back": { "success": true, ... } }
      final topResult = json['result'] as int?;
      final back = json['back'] as Map<String, dynamic>?;
      final success = back?['success'] as bool?;

      final ok = (topResult == 1) || (success == true);
      if (!ok) {
        _sessionCookie = null;
        final msg = back?['msg'] ?? json['msg'] ?? 'credenziali non valide';
        return GrowattError(GrowattErrorKind.authFailed, 'Login fallito: $msg');
      }

      return null;
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 2 — Ottieni plantId
  // POST /index/getPlantListTitle
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _fetchPlantId() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/index/getPlantListTitle'),
        headers: _headers,
        body: {},
      ).timeout(const Duration(seconds: 15));

      debugPrint('[Growatt] POST /getPlantListTitle status=${response.statusCode}');
      debugPrint('[Growatt] POST /getPlantListTitle body=${_preview(response.body)}');

      if (response.statusCode == 302 || response.statusCode == 401) {
        return const GrowattError(GrowattErrorKind.sessionExpired, 'Sessione scaduta.');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final back = json['back'] as Map<String, dynamic>?;
      final dataList = back?['data'] as List<dynamic>?;

      if (dataList == null || dataList.isEmpty) {
        return const GrowattError(
            GrowattErrorKind.plantNotFound, 'Nessun impianto trovato.');
      }

      final first = dataList.first as Map<String, dynamic>;
      _plantId = (first['id'] ?? first['plantId'])?.toString();
      debugPrint('[Growatt] plantId: $_plantId');
      return null;
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 3 — Ottieni serial number
  // POST /panel/getDevicesByPlantList  body: plantId=...&currPage=1
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _fetchDeviceSn() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/panel/getDevicesByPlantList'),
        headers: _headers,
        body: {'plantId': _plantId!, 'currPage': '1'},
      ).timeout(const Duration(seconds: 15));

      debugPrint('[Growatt] POST /getDevicesByPlantList status=${response.statusCode}');
      debugPrint('[Growatt] POST /getDevicesByPlantList body=${_preview(response.body)}');

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final obj = json['obj'] as Map<String, dynamic>?;
      final datas = obj?['datas'] as List<dynamic>?;

      if (datas == null || datas.isEmpty) {
        return GrowattError(GrowattErrorKind.plantNotFound,
            'Nessun device trovato per plantId=$_plantId.');
      }

      final Map<String, dynamic> target = datas
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => (d['deviceType']?.toString() ?? '') == '3',
              orElse: () => datas.first as Map<String, dynamic>);

      _deviceSn = (target['sn'] ?? target['deviceSn'])?.toString();
      debugPrint('[Growatt] deviceSn: $_deviceSn (deviceType=${target["deviceType"]})');
      return null;
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 4 — Dati energetici
  // POST /panel/min/getMinEnergyDayChart  body: sn=...&date=YYYY-MM-DD
  // -------------------------------------------------------------------------

  Future<GrowattResult> fetchToday() async {
    if (_sessionCookie == null) {
      final err = await _login();
      if (err != null) return err;
    }
    if (_plantId == null) {
      final err = await _fetchPlantId();
      if (err != null) return err;
    }
    if (_deviceSn == null) {
      final err = await _fetchDeviceSn();
      if (err != null) return err;
    }

    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl/panel/min/getMinEnergyDayChart'),
        headers: _headers,
        body: {'sn': _deviceSn!, 'date': dateStr},
      ).timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }

    final rawBody = _preview(response.body);
    debugPrint('[Growatt] POST /getMinEnergyDayChart status=${response.statusCode}');
    debugPrint('[Growatt] POST /getMinEnergyDayChart body=$rawBody');

    if (response.statusCode == 302 || response.statusCode == 401) {
      _sessionCookie = null;
      _plantId = null;
      _deviceSn = null;
      return const GrowattError(GrowattErrorKind.sessionExpired,
          'Sessione scaduta, verrà rinnovata al prossimo aggiornamento.');
    }
    if (response.statusCode != 200) {
      return GrowattError(GrowattErrorKind.serverError,
          '[getMinEnergyDayChart HTTP ${response.statusCode}] $rawBody');
    }

    return _parseEnergyData(response.body);
  }

  // -------------------------------------------------------------------------
  // PARSER
  // -------------------------------------------------------------------------

  GrowattResult _parseEnergyData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final result = json['result'] as int? ?? 0;
      if (result != 1) {
        return GrowattError(GrowattErrorKind.serverError,
            'result=$result | body: ${_preview(body, 300)}');
      }

      final obj = json['obj'] as Map<String, dynamic>?;
      if (obj == null) {
        return GrowattError(GrowattErrorKind.parseError,
            '"obj" mancante. body: ${_preview(body, 400)}');
      }

      final pvTodayKwh = _d(obj['eacToday'] ?? obj['etoday']);
      final pvPowerW   = _d(obj['pac']);
      final gridExport = _d(obj['etoGridToday'] ?? obj['epvtoGridToday']);
      final gridImport = _d(obj['etoUserToday'] ?? obj['etouserToday']);

      debugPrint('[Growatt] parsed: pv=$pvTodayKwh kWh, power=$pvPowerW W, '
          'export=$gridExport kWh, import=$gridImport kWh');

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

  void invalidateSession() {
    _sessionCookie = null;
    _plantId = null;
    _deviceSn = null;
  }

  void dispose() => _client.close();
}
