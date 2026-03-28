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
  // -------------------------------------------------------------------------
  // Range ammessi
  // -------------------------------------------------------------------------

  /// Temperatura esterna: copre climi da polare a desertico.
  static const double extTempMin = -40.0;
  static const double extTempMax = 50.0;

  /// Temperature interne: al di sotto di 5° o sopra 40° è quasi certamente
  /// un errore di digitazione.
  static const double intTempMin = 5.0;
  static const double intTempMax = 40.0;

  /// Consumo giornaliero: 0 è ammesso (giorno di fermo impianto),
  /// 9999 kWh è un tetto molto generoso per qualsiasi impianto domestico.
  static const double consumptionMin = 0.0;
  static const double consumptionMax = 9999.0;

  // -------------------------------------------------------------------------
  // Validazione principale
  // -------------------------------------------------------------------------

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

    // 4. Range temperatura esterna
    if (extTemp < extTempMin || extTemp > extTempMax) {
      return RecordValidationError(
        'Temperatura esterna fuori range '
        '($extTempMin°C ÷ $extTempMax°C).',
      );
    }

    // 5. Conversione consumo
    final double? cons = double.tryParse(
      consumptionController.text.replaceAll(',', '.'),
    );
    if (cons == null) {
      return RecordValidationError('Valore consumo non valido.');
    }

    // 6. Range consumo
    if (cons < consumptionMin || cons > consumptionMax) {
      return RecordValidationError(
        'Consumo fuori range '
        '($consumptionMin ÷ $consumptionMax kWh).',
      );
    }

    // 7. Conversione e range temperature interne
    final Map<String, double> internalTemps = {};
    for (final entry in internalTempControllers.entries) {
      final val = double.tryParse(entry.value.text.replaceAll(',', '.'));
      if (val == null) {
        return RecordValidationError(
          'Errore: La temperatura di ${entry.key} non è un numero valido.',
        );
      }
      if (val < intTempMin || val > intTempMax) {
        return RecordValidationError(
          'Temperatura di ${entry.key} fuori range '
          '($intTempMin°C ÷ $intTempMax°C).',
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
