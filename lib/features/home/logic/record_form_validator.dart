import 'package:flutter/material.dart';

/// Risultato della validazione del form di inserimento record.
/// [RecordValidationOk] contiene i valori già convertiti, pronti all'uso.
/// [RecordValidationError] contiene il messaggio di errore da mostrare.
sealed class RecordValidationResult {}

final class RecordValidationOk extends RecordValidationResult {
  final double externalTemp;
  final double consumption;
  final Map<String, double> internalTemps;

  RecordValidationOk({
    required this.externalTemp,
    required this.consumption,
    required this.internalTemps,
  });
}

final class RecordValidationError extends RecordValidationResult {
  final String message;
  RecordValidationError(this.message);
}

/// Valida i campi del form di inserimento/modifica record.
/// È una classe pura senza dipendenze Flutter (tranne [TextEditingController])
/// e può essere testata in isolamento senza widget.
class RecordFormValidator {
  /// Esegue la validazione completa del form.
  ///
  /// [externalTempController] e [consumptionController] sono obbligatori.
  /// [internalTempControllers] è la mappa stanza -> controller.
  ///
  /// Restituisce [RecordValidationOk] con i valori convertiti se tutto è valido,
  /// oppure [RecordValidationError] con il primo errore trovato.
  static RecordValidationResult validate({
    required TextEditingController externalTempController,
    required TextEditingController consumptionController,
    required Map<String, TextEditingController> internalTempControllers,
  }) {
    // 1. Campi obbligatori presenti
    if (externalTempController.text.trim().isEmpty ||
        consumptionController.text.trim().isEmpty) {
      return RecordValidationError(
        'Errore: Temperatura Esterna e Consumo sono obbligatori!',
      );
    }

    // 2. Temperature interne tutte compilate
    for (final entry in internalTempControllers.entries) {
      if (entry.value.text.trim().isEmpty) {
        return RecordValidationError(
          'Errore: Manca la temperatura per ${entry.key}!',
        );
      }
    }

    // 3. Conversione temperatura esterna
    final double? extTemp = double.tryParse(
      externalTempController.text.replaceAll(',', '.'),
    );
    if (extTemp == null) {
      return RecordValidationError('Temperatura esterna non valida.');
    }

    // 4. Conversione consumo
    final double? cons = double.tryParse(
      consumptionController.text.replaceAll(',', '.'),
    );
    if (cons == null) {
      return RecordValidationError('Valore consumo non valido.');
    }

    // 5. Conversione temperature interne
    final Map<String, double> internalTemps = {};
    for (final entry in internalTempControllers.entries) {
      final val = double.tryParse(entry.value.text.replaceAll(',', '.'));
      if (val == null) {
        return RecordValidationError(
          'Errore: La temperatura di ${entry.key} non è un numero valido.',
        );
      }
      internalTemps[entry.key] = val;
    }

    return RecordValidationOk(
      externalTemp: extTemp,
      consumption: cons,
      internalTemps: internalTemps,
    );
  }
}
