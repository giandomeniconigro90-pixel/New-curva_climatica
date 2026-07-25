// lib/services/growatt_notifier.dart
//
// ChangeNotifier che gestisce il polling periodico dei dati Growatt.
//
// Ciclo di vita:
//   1. All'avvio legge username+password da GrowattCredentialsService.
//   2. Se esistono, fa subito un fetchToday() e avvia il timer (ogni 10 minuti).
//   3. Ad ogni tick aggiorna [data] e notifica i listener.
//   4. dispose() cancella il timer e chiude il client HTTP.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'growatt_credentials_service.dart';
import 'growatt_service.dart';

enum GrowattPollingState { idle, loading, ok, error, notConfigured }

class GrowattNotifier extends ChangeNotifier {
  GrowattService? _service;
  Timer? _timer;

  GrowattData? data;
  GrowattPollingState state = GrowattPollingState.idle;
  String? errorMessage;

  final Duration pollInterval;

  GrowattNotifier({this.pollInterval = const Duration(minutes: 10)});

  // -------------------------------------------------------------------------
  // Init
  // -------------------------------------------------------------------------

  Future<void> init() async {
    final creds = await GrowattCredentialsService.load();
    if (creds == null) {
      state = GrowattPollingState.notConfigured;
      notifyListeners();
      return;
    }

    _service = GrowattService(
      username: creds.username,
      password: creds.password,
    );

    await _fetch();
    _timer = Timer.periodic(pollInterval, (_) => _fetch());
  }

  // -------------------------------------------------------------------------
  // Fetch
  // -------------------------------------------------------------------------

  Future<void> _fetch() async {
    if (_service == null) return;
    state = GrowattPollingState.loading;
    notifyListeners();

    final result = await _service!.fetchToday();

    if (result is GrowattOk) {
      data = result.data;
      state = GrowattPollingState.ok;
      errorMessage = null;
    } else if (result is GrowattError) {
      if (result.kind == GrowattErrorKind.authFailed) {
        _timer?.cancel();
        _timer = null;
      }
      // Sessione scaduta: il prossimo fetchToday() farà re-login automatico
      state = GrowattPollingState.error;
      errorMessage = _describe(result);
    }

    notifyListeners();
  }

  Future<void> refresh() => _fetch();

  // -------------------------------------------------------------------------
  // Riconfigura dopo aver salvato nuove credenziali
  // -------------------------------------------------------------------------

  Future<void> reconfigure() async {
    _timer?.cancel();
    _timer = null;
    _service?.dispose();
    _service = null;
    data = null;
    errorMessage = null;
    state = GrowattPollingState.idle;
    await init();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _describe(GrowattError e) {
    switch (e.kind) {
      case GrowattErrorKind.authFailed:
        return 'Credenziali non valide. Riconfigura in Impostazioni > Fotovoltaico.';
      case GrowattErrorKind.networkError:
        return 'Nessuna connessione. Riprovo al prossimo aggiornamento.';
      case GrowattErrorKind.sessionExpired:
        return 'Sessione rinnovata automaticamente.';
      case GrowattErrorKind.plantNotFound:
        return 'Nessun impianto trovato per questo account.';
      default:
        return e.message;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service?.dispose();
    super.dispose();
  }
}
