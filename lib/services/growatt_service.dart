// lib/services/growatt_service.dart
//
// Integrazione Growatt cloud API per leggere i dati del fotovoltaico.
//
// Dati disponibili:
//   • Produzione PV oggi (kWh)            → GrowattData.pvTodayKwh
//   • Potenza PV istantanea (W)            → GrowattData.pvPowerW
//   • Energia importata da rete oggi (kWh) → GrowattData.gridImportTodayKwh
//   • Energia esportata in rete oggi (kWh) → GrowattData.gridExportTodayKwh
//   • Autoconsumo oggi (kWh)               → GrowattData.selfConsumptionTodayKwh
//
// Uso:
//   final service = GrowattService();
//   await service.login(username: 'email@example.com', password: 'password');
//   final result = await service.fetchToday();
//   result.when(
//     ok: (data) => print(data.pvTodayKwh),
//     error: (e) => print(e),
//   );
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
// Result sealed (stesso pattern di WeatherResult)
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
  /// Credenziali errate
  authFailed,
  /// Sessione scaduta — serve ri-login
  sessionExpired,
  /// Errore di rete (nessuna connessione)
  networkError,
  /// Risposta API non parsabile o struttura cambiata
  parseError,
  /// Impianto non trovato con il Plant ID fornito
  plantNotFound,
  /// Errore generico server Growatt
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

  /// Cookie di sessione ottenuto dopo il login
  String? _sessionCookie;

  GrowattService({
    this.plantId = defaultPlantId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  bool get isLoggedIn => _sessionCookie != null;

  // -------------------------------------------------------------------------
  // LOGIN
  // -------------------------------------------------------------------------

  /// Autentica con le credenziali Shine Phone.
  ///
  /// Restituisce [GrowattOk] con dati vuoti (pvTodayKwh = 0) se il login
  /// va a buon fine — i dati reali si ottengono con [fetchToday].
  /// Restituisce [GrowattError] con [GrowattErrorKind.authFailed] se le
  /// credenziali sono errate.
  ///
  /// Le credenziali NON devono essere hardcodate — passarle da
  /// flutter_secure_storage o da un form di configurazione.
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
          'Credenziali non valide. Verifica email e password di Shine Phone.',
        );
      }

      // Estrai il cookie di sessione
      final setCookie = response.headers['set-cookie'];
      if (setCookie == null) {
        return const GrowattError(
          GrowattErrorKind.serverError,
          'Login OK ma nessun cookie di sessione ricevuto.',
        );
      }
      // Il cookie ha formato: "JSESSIONID=xxxx; Path=/; HttpOnly"
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
  // -------------------------------------------------------------------------

  /// Recupera i dati energetici di oggi per l'impianto [plantId].
  ///
  /// Richiede che [login] sia stato chiamato con successo.
  /// Se la sessione è scaduta, restituisce [GrowattErrorKind.sessionExpired]
  /// — in quel caso ri-chiama [login] e poi riprova.
  Future<GrowattResult> fetchToday() async {
    if (_sessionCookie == null) {
      return const GrowattError(
        GrowattErrorKind.sessionExpired,
        'Sessione non attiva. Eseguire il login prima di fetchToday().',
      );
    }

    try {
      // Endpoint che restituisce i dati energetici del giorno corrente
      final uri = Uri.parse(
        '$_baseUrl/panel/plant/getPlantData?plantId=$plantId',
      );

      final response = await _client.get(
        uri,
        headers: {
          'Cookie': _sessionCookie!,
          'User-Agent': 'Mozilla/5.0',
          'Referer': '$_baseUrl/index',
        },
      ).timeout(const Duration(seconds: 15));

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
  // -------------------------------------------------------------------------

  GrowattResult _parsePlantData(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;

      // La risposta ha struttura: { "result": 1, "obj": { ... } }
      final obj = json['obj'] as Map<String, dynamic>?;
      if (obj == null) {
        return const GrowattError(
          GrowattErrorKind.parseError,
          'Campo "obj" mancante nella risposta Growatt.',
        );
      }

      double _d(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      // Campi principali dell'endpoint getPlantData
      final double pvTodayKwh       = _d(obj['etoday']);       // kWh prodotti oggi
      final double pvPowerW         = _d(obj['currentPower']); // W istantanei (kW × 1000)
      final double gridImport        = _d(obj['etoGridToday']); // kWh importati da rete
      final double gridExport        = _d(obj['etoday']) - _d(obj['eselfToday']); // kWh esportati

      return GrowattOk(GrowattData(
        pvTodayKwh: pvTodayKwh,
        pvPowerW: pvPowerW * 1000, // l'API restituisce kW, convertiamo in W
        gridImportTodayKwh: gridImport,
        gridExportTodayKwh: gridExport.clamp(0.0, double.infinity),
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
