// lib/services/growatt_notifier.dart
//
// ChangeNotifier che gestisce il polling periodico dei dati Growatt.
//
// Ciclo di vita:
//   1. All'avvio legge il token API da GrowattCredentialsService.
//   2. Se esiste, fa subito un fetchToday() e avvia il timer (ogni 10 minuti).
//   3. Ad ogni tick aggiorna [data] e notifica i listener.
//   4. dispose() cancella il timer e chiude il client HTTP.
//
// Uso in main.dart / ClimateCurveOfflineHome:
//   ChangeNotifierProvider(
//     create: (_) => GrowattNotifier()..init(),
//     child: ...
//   )

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

  /// Intervallo di polling (default 10 minuti)
  final Duration pollInterval;

  GrowattNotifier({this.pollInterval = const Duration(minutes: 10)});

  // -------------------------------------------------------------------------
  // Init — chiamato una volta all'avvio
  // -------------------------------------------------------------------------

  Future<void> init() async {
    final token = await GrowattCredentialsService.load();
    if (token == null || token.isEmpty) {
      state = GrowattPollingState.notConfigured;
      notifyListeners();
      return;
    }

    _service = GrowattService(apiToken: token);

    // Fetch immediato poi avvia timer
    await _fetch();
    _timer = Timer.periodic(pollInterval, (_) => _fetch());
  }

  // -------------------------------------------------------------------------
  // Fetch singolo
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
      // Se token non valido, segnala subito senza retry
      if (result.kind == GrowattErrorKind.authFailed) {
        _timer?.cancel();
        _timer = null;
        state = GrowattPollingState.error;
        errorMessage = _describe(result);
        notifyListeners();
        return;
      }
      state = GrowattPollingState.error;
      errorMessage = _describe(result);
    }

    notifyListeners();
  }

  /// Forza un aggiornamento manuale immediato.
  Future<void> refresh() => _fetch();

  // -------------------------------------------------------------------------
  // Riconfigura dopo aver salvato un nuovo token
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
        return 'Token non valido. Riconfigura in Impostazioni > Fotovoltaico.';
      case GrowattErrorKind.networkError:
        return 'Nessuna connessione. Riprovo al prossimo aggiornamento.';
      case GrowattErrorKind.sessionExpired:
        return 'Token scaduto. Rigenera il token su server.growatt.com.';
      case GrowattErrorKind.plantNotFound:
        return 'Nessun impianto trovato per questo token.';
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
