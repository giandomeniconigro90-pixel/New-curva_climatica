// lib/services/growatt_service.dart
//
// Integrazione Growatt cloud API per leggere i dati del fotovoltaico.
//
// Endpoint reali utilizzati (documentazione community Growatt):
//   POST /login                                      → login + JSESSIONID
//   POST /newTwoPlantAPI/getPlantData                → dati impianto oggi
//   POST /panel/plant/getPlantData (DEPRECATO/404)   → non usare
//
// Dati disponibili:
//   • Produzione PV oggi (kWh)            → GrowattData.pvTodayKwh
//   • Potenza PV istantanea (W)            → GrowattData.pvPowerW
//   • Energia importata da rete oggi (kWh) → GrowattData.gridImportTodayKwh
//   • Energia esportata in rete oggi (kWh) → GrowattData.gridExportTodayKwh
//   • Autoconsumo oggi (kWh)               → GrowattData.selfConsumptionTodayKwh
//
// NOTA SICUREZZA: non hardcodare mai username/password nel codice.
// Usare flutter_secure_storage per persistere le credenziali.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class GrowattData {
  /// Produzione fotovoltaica totale oggi (kWh)
  final double pvTodayKwh;

  /// Potenza fotovoltaica istantanea (W)
  final double pvPowerW;

  /// Energia importata dalla rete oggi (kWh)
  final double gridImportTodayKwh;

  /// Energia esportata in rete oggi (kWh)
  final double gridExportTodayKwh;

  /// Autoconsumo oggi = produzione - esportazione (kWh)
  double get selfConsumptionTodayKwh =>
      (pvTodayKwh - gridExportTodayKwh).clamp(0.0, double.infinity);

  /// Timestamp dell'ultimo aggiornamento (UTC)
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

  /// Plant ID dell'impianto Nigro — SantAgata Bolognese, 6000W
  static const int defaultPlantId = 11037032;

  final int plantId;
  final http.Client _client;

  String? _sessionCookie;

  GrowattService({
    this.plantId = defaultPlantId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  bool get isLoggedIn => _sessionCookie != null;

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

      final setCookie = response.headers['set-cookie'];
      if (setCookie == null) {
        return const GrowattError(
          GrowattErrorKind.serverError,
          'Login OK ma nessun cookie di sessione ricevuto.',
        );
      }
      _sessionCookie = setCookie.split(';').first.trim();

      debugPrint('[GrowattService] Login OK — sessione attiva.');
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
  //
  // Endpoint corretto: POST /newTwoPlantAPI/getPlantData
  // Body form: plantId=<id>
  // Risposta: { "result": 1, "obj": { "plantData": { ... } } }
  //
  // Campi rilevanti in obj.plantData:
  //   etoday        → kWh prodotti oggi
  //   currentPower  → kW istantanei (moltiplicare ×1000 per W)
  //   etoGridToday  → kWh esportati in rete oggi
  //   eUsedToday    → kWh consumati oggi
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
      debugPrint('[GrowattService] fetchToday body=${response.body.substring(0, response.body.length.clamp(0, 300))}');

      if (response.statusCode == 302 ||
          response.body.contains('"result":-1')) {
        _sessionCookie = null;
        return const GrowattError(
          GrowattErrorKind.sessionExpired,
          'Sessione scaduta. Eseguire nuovamente il login.',
        );
      }

      if (response.statusCode != 200) {
        return GrowattError(
          GrowattErrorKind.serverError,
          'HTTP ${response.statusCode}',
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
  // La risposta di /newTwoPlantAPI/getPlantData ha struttura:
  // {
  //   "result": 1,
  //   "obj": {
  //     "plantData": {
  //       "etoday": "12.5",
  //       "currentPower": "1.23",   ← kW
  //       "etoGridToday": "3.2",
  //       "eUsedToday": "9.3"
  //     }
  //   }
  // }
  // -------------------------------------------------------------------------

  GrowattResult _parsePlantData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;

      final obj = json['obj'] as Map<String, dynamic>?;
      if (obj == null) {
        return GrowattError(
          GrowattErrorKind.parseError,
          'Campo "obj" mancante. Risposta: ${body.substring(0, body.length.clamp(0, 200))}',
        );
      }

      // /newTwoPlantAPI/getPlantData annida i dati in obj.plantData
      final plantData = (obj['plantData'] as Map<String, dynamic>?) ?? obj;

      double _d(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      final double pvTodayKwh    = _d(plantData['etoday']);
      final double pvPowerKw     = _d(plantData['currentPower']); // kW
      final double gridExport    = _d(plantData['etoGridToday']);
      final double usedToday     = _d(plantData['eUsedToday']);
      // gridImport = consumo - (produzione - esportazione)
      final double selfCons      = (pvTodayKwh - gridExport).clamp(0.0, double.infinity);
      final double gridImport    = (usedToday - selfCons).clamp(0.0, double.infinity);

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

  // -------------------------------------------------------------------------
  // DISPOSE
  // -------------------------------------------------------------------------

  void dispose() {
    _client.close();
  }
}
