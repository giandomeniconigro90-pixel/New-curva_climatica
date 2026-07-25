// lib/services/growatt_service.dart
//
// Flusso OpenAPI Growatt (openapi.growatt.com):
//
//  STEP 1 — GET /v1/plant/list
//            Risposta: { "data": { "plants": [...] }, "error_code": 0 }
//
//  STEP 2 — GET /v1/device/list?plant_id={plantId}
//            Risposta: { "data": { "devices": [{"device_sn":"...","type":7,...}] } }
//
//  STEP 3 — POST /v1/device/tlx/tlx_data   (per type=7 MIN/TLX)
//            Content-Type: application/json
//            body JSON: { device_sn, start_date, end_date, timezone_id }
//            Risposta: { "data": { "tlx": [{"eacToday":...,"pac":...}] } }
//
// Riferimento: https://www.showdoc.com.cn/262556420217021/8559849784929961

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

  String? _plantId;
  String? _deviceSn;

  GrowattService({
    required this.apiToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  // Header per GET (nessun body)
  Map<String, String> get _getHeaders => {
        'token': apiToken,
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
      };

  // Header per POST con body JSON
  Map<String, String> get _postJsonHeaders => {
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
  // STEP 1 — GET /v1/plant/list
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _fetchPlantId() async {
    try {
      final uri = Uri.parse('$_baseUrl/v1/plant/list');
      final response = await _client
          .get(uri, headers: _getHeaders)
          .timeout(const Duration(seconds: 15));

      final rawBody = _preview(response.body);
      debugPrint('[Growatt] GET /v1/plant/list status=${response.statusCode}');
      debugPrint('[Growatt] GET /v1/plant/list body=$rawBody');

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const GrowattError(GrowattErrorKind.authFailed, 'Token API non valido o scaduto.');
      }
      if (response.statusCode != 200) {
        return GrowattError(GrowattErrorKind.serverError, '[plant/list HTTP ${response.statusCode}] $rawBody');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errorCode = json['error_code'] as int? ?? -1;
      if (errorCode != 0) {
        return GrowattError(GrowattErrorKind.authFailed, 'error_code=$errorCode msg=${json["error_msg"]}');
      }

      List<dynamic>? plantList;
      final dataField = json['data'];
      if (dataField is Map<String, dynamic>) {
        plantList = dataField['plants'] as List<dynamic>?;
      } else if (dataField is List<dynamic>) {
        plantList = dataField;
      }

      if (plantList == null || plantList.isEmpty) {
        return const GrowattError(GrowattErrorKind.plantNotFound, 'Nessun impianto trovato per questo token.');
      }

      final first = plantList.first as Map<String, dynamic>;
      _plantId = (first['plant_id'] ?? first['plantId'])?.toString();

      if (_plantId == null || _plantId!.isEmpty) {
        return GrowattError(GrowattErrorKind.parseError, 'plant_id non trovato. plants[0]=$first');
      }

      debugPrint('[Growatt] plantId: $_plantId');
      return null;
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 2 — GET /v1/device/list?plant_id={plantId}
  // -------------------------------------------------------------------------

  Future<GrowattResult?> _fetchDeviceSn() async {
    try {
      final uri = Uri.parse('$_baseUrl/v1/device/list').replace(
        queryParameters: {'plant_id': _plantId},
      );
      final response = await _client
          .get(uri, headers: _getHeaders)
          .timeout(const Duration(seconds: 15));

      final rawBody = _preview(response.body);
      debugPrint('[Growatt] GET /v1/device/list?plant_id=$_plantId status=${response.statusCode}');
      debugPrint('[Growatt] GET /v1/device/list body=$rawBody');

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const GrowattError(GrowattErrorKind.authFailed, 'Token API non valido o scaduto.');
      }
      if (response.statusCode != 200) {
        return GrowattError(GrowattErrorKind.serverError, '[device/list HTTP ${response.statusCode}] $rawBody');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errorCode = json['error_code'] as int? ?? -1;
      if (errorCode != 0) {
        return GrowattError(GrowattErrorKind.serverError, 'error_code=$errorCode msg=${json["error_msg"]}');
      }

      List<dynamic>? deviceList;
      final dataField = json['data'];
      if (dataField is Map<String, dynamic>) {
        deviceList = (dataField['devices'] ?? dataField['device']) as List<dynamic>?;
      } else if (dataField is List<dynamic>) {
        deviceList = dataField;
      }

      if (deviceList == null || deviceList.isEmpty) {
        return GrowattError(GrowattErrorKind.plantNotFound, 'Nessun device trovato per plantId=$_plantId.');
      }

      // Preferisci il device di tipo 7 (MIN/TLX inverter), fallback al primo
      final Map<String, dynamic> target = deviceList
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => (d['type'] as int? ?? 0) == 7,
              orElse: () => deviceList!.first as Map<String, dynamic>);

      _deviceSn = (target['device_sn'] ?? target['deviceSn'] ?? target['sn'])?.toString();

      if (_deviceSn == null || _deviceSn!.isEmpty) {
        return GrowattError(GrowattErrorKind.parseError, 'device_sn non trovato. target=$target');
      }

      debugPrint('[Growatt] deviceSn: $_deviceSn (type=${target["type"]})');
      return null;
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // STEP 3 — POST /v1/device/tlx/tlx_data  (MIN/TLX inverter, type=7)
  // Content-Type: application/json
  // Body: { "device_sn": "...", "start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD", "timezone_id": "Europe/Rome" }
  // Risposta: { "data": { "tlx": [ { "eacToday": 12.5, "pac": 1230, ... } ] }, "error_code": 0 }
  // -------------------------------------------------------------------------

  Future<GrowattResult> fetchToday() async {
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
        Uri.parse('$_baseUrl/v1/device/tlx/tlx_data'),
        headers: _postJsonHeaders,
        body: jsonEncode({
          'device_sn': _deviceSn!,
          'start_date': dateStr,
          'end_date': dateStr,
          'timezone_id': 'Europe/Rome',
        }),
      ).timeout(const Duration(seconds: 15));
    } on Exception catch (e) {
      return GrowattError(GrowattErrorKind.networkError, e.toString());
    }

    final rawBody = _preview(response.body);
    debugPrint('[Growatt] POST /v1/device/tlx/tlx_data status=${response.statusCode}');
    debugPrint('[Growatt] POST /v1/device/tlx/tlx_data body=$rawBody');

    if (response.statusCode == 401 || response.statusCode == 403) {
      return const GrowattError(GrowattErrorKind.authFailed, 'Token API non valido o scaduto.');
    }
    if (response.statusCode != 200) {
      return GrowattError(GrowattErrorKind.serverError, '[tlx_data HTTP ${response.statusCode}] $rawBody');
    }

    return _parseTlxData(response.body);
  }

  // -------------------------------------------------------------------------
  // PARSER — /v1/device/tlx/tlx_data
  // L'array tlx contiene un record ogni 5 minuti.
  // Ultimo elemento = dato più recente del giorno.
  // Campi: eacToday (kWh prodotti), pac (W istantanei),
  //        etoGridToday (kWh immessi), etoUserToday (kWh consumati da rete)
  // -------------------------------------------------------------------------

  GrowattResult _parseTlxData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final errorCode = json['error_code'] as int? ?? -1;
      if (errorCode != 0) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'error_code=$errorCode msg=${json["error_msg"]} | body: ${_preview(body, 300)}',
        );
      }

      final dataObj = json['data'] as Map<String, dynamic>?;
      if (dataObj == null) {
        return GrowattError(GrowattErrorKind.parseError, '"data" mancante. body: ${_preview(body, 400)}');
      }

      final tlxList = dataObj['tlx'] as List<dynamic>?;
      if (tlxList == null || tlxList.isEmpty) {
        debugPrint('[Growatt] tlx list vuota — nessun dato per oggi');
        return GrowattOk(GrowattData(
          pvTodayKwh: 0,
          pvPowerW: 0,
          gridImportTodayKwh: 0,
          gridExportTodayKwh: 0,
          fetchedAt: DateTime.now().toUtc(),
        ));
      }

      final last = tlxList.last as Map<String, dynamic>;

      final pvTodayKwh = _d(last['eacToday']);
      final pvPowerW   = _d(last['pac']);
      final gridExport = _d(last['etoGridToday']);
      final gridImport = _d(last['etoUserToday']);

      debugPrint('[Growatt] parsed: pv=$pvTodayKwh kWh, power=$pvPowerW W, export=$gridExport kWh, import=$gridImport kWh');

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
