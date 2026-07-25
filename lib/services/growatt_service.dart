// lib/services/growatt_service.dart
//
// Flusso OpenAPI Growatt (openapi.growatt.com):
//
//  STEP 1 — GET /v1/plant/list
//            Header: token: <API_TOKEN>
//            Restituisce la lista impianti con plantId
//
//  STEP 2 — GET /v1/plant/{plantId}/devices
//            Header: token: <API_TOKEN>
//            Restituisce la lista device con deviceSn
//
//  STEP 3 — GET /v1/device/{deviceSn}/energy?date=YYYY-MM-DD
//            Header: token: <API_TOKEN>
//            Restituisce i dati energetici del giorno
//
// Riferimento: https://openapi.growatt.com/v1

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
  static const String _baseUrl = 'https://openapi.growatt.com';

  final String apiToken;
  final http.Client _client;

  /// Plant ID e Device SN vengono risolti dinamicamente al primo fetch.
  String? _plantId;
  String? _deviceSn;

  GrowattService({
    required this.apiToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'token': apiToken,
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
      };

  String _preview(String s, [int max = 600]) =>
      s.length > max ? s.substring(0, max) : s;

  double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  // -------------------------------------------------------------------------
  // STEP 1 — Recupera il primo plantId
  // GET /v1/plant/list
  // Risposta: { "data": [ { "plant_id": "...", ... } ], "error_code": 0 }
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _fetchPlantId() async {
    try {
      final uri = Uri.parse('$_baseUrl/v1/plant/list');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      final rawBody = _preview(response.body);
      debugPrint('[Growatt] GET /v1/plant/list status=${response.statusCode}');
      debugPrint('[Growatt] GET /v1/plant/list body=$rawBody');

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const GrowattError(
          GrowattErrorKind.authFailed,
          'Token API non valido o scaduto.',
        );
      }
      if (response.statusCode != 200) {
        return GrowattError(
          GrowattErrorKind.serverError,
          '[plant/list HTTP ${response.statusCode}] $rawBody',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errorCode = json['error_code'] as int? ?? -1;
      if (errorCode != 0) {
        return GrowattError(
          GrowattErrorKind.authFailed,
          'error_code=$errorCode msg=${json['error_msg']}',
        );
      }

      final dataList = json['data'] as List<dynamic>?;
      if (dataList == null || dataList.isEmpty) {
        return const GrowattError(
          GrowattErrorKind.plantNotFound,
          'Nessun impianto trovato per questo token.',
        );
      }

      final first = dataList.first as Map<String, dynamic>;
      _plantId = (first['plant_id'] ?? first['plantId'])?.toString();

      if (_plantId == null || _plantId!.isEmpty) {
        return GrowattError(
          GrowattErrorKind.parseError,
          'plant_id non trovato. data[0]=$first',
        );
      }

      debugPrint('[Growatt] plantId: $_plantId');
      return null; // successo
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 2 — Recupera il primo deviceSn
  // GET /v1/plant/{plantId}/devices
  // Risposta: { "data": [ { "device_sn": "...", ... } ], "error_code": 0 }
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _fetchDeviceSn() async {
    try {
      final uri = Uri.parse('$_baseUrl/v1/plant/$_plantId/devices');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      final rawBody = _preview(response.body);
      debugPrint('[Growatt] GET /v1/plant/$_plantId/devices status=${response.statusCode}');
      debugPrint('[Growatt] GET /v1/plant/$_plantId/devices body=$rawBody');

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const GrowattError(
          GrowattErrorKind.authFailed,
          'Token API non valido o scaduto.',
        );
      }
      if (response.statusCode != 200) {
        return GrowattError(
          GrowattErrorKind.serverError,
          '[plant/devices HTTP ${response.statusCode}] $rawBody',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errorCode = json['error_code'] as int? ?? -1;
      if (errorCode != 0) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'error_code=$errorCode msg=${json['error_msg']}',
        );
      }

      final dataList = json['data'] as List<dynamic>?;
      if (dataList == null || dataList.isEmpty) {
        return GrowattError(
          GrowattErrorKind.plantNotFound,
          'Nessun device trovato per plantId=$_plantId.',
        );
      }

      final first = dataList.first as Map<String, dynamic>;
      _deviceSn = (first['device_sn'] ?? first['deviceSn'] ?? first['sn'])?.toString();

      if (_deviceSn == null || _deviceSn!.isEmpty) {
        return GrowattError(
          GrowattErrorKind.parseError,
          'device_sn non trovato. data[0]=$first',
        );
      }

      debugPrint('[Growatt] deviceSn: $_deviceSn');
      return null; // successo
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 3 — Dati energetici del giorno
  // GET /v1/device/{deviceSn}/energy?date=YYYY-MM-DD
  // Risposta: { "data": { "etoday": "12.5", "pac": "1230", ... }, "error_code": 0 }
  // -------------------------------------------------------------------------

  Future<GrowattResult> fetchToday() async {
    // Risolvi plantId e deviceSn se non ancora in cache
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
      final uri = Uri.parse(
          '$_baseUrl/v1/device/$_deviceSn/energy?date=$dateStr');
      response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }

    final rawBody = _preview(response.body);
    debugPrint('[Growatt] GET /v1/device/$_deviceSn/energy status=${response.statusCode}');
    debugPrint('[Growatt] GET /v1/device/$_deviceSn/energy body=$rawBody');

    if (response.statusCode == 401 || response.statusCode == 403) {
      return const GrowattError(
        GrowattErrorKind.authFailed,
        'Token API non valido o scaduto.',
      );
    }
    if (response.statusCode != 200) {
      return GrowattError(
        GrowattErrorKind.serverError,
        '[energy HTTP ${response.statusCode}] $rawBody',
      );
    }

    return _parseEnergyData(response.body);
  }

  // -------------------------------------------------------------------------
  // PARSER
  // -------------------------------------------------------------------------

  GrowattResult _parseEnergyData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final errorCode = json['error_code'] as int? ?? -1;
      if (errorCode != 0) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'error_code=$errorCode msg=${json['error_msg']} | body: ${_preview(body, 300)}',
        );
      }

      final obj = json['data'] as Map<String, dynamic>?;
      if (obj == null) {
        return GrowattError(
          GrowattErrorKind.parseError,
          '"data" mancante. body: ${_preview(body, 400)}',
        );
      }

      final pvTodayKwh = _d(obj['etoday']);
      final pvPowerW = _d(obj['pac']);
      final gridExport = _d(obj['etoGridToday'] ?? obj['export_energy']);
      final usedToday = _d(obj['eUsedToday'] ?? obj['consume_energy']);
      final selfCons = (pvTodayKwh - gridExport).clamp(0.0, double.infinity);
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
