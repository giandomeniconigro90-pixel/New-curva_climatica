// lib/features/home/logic/record_form_validator.dart
//
// Refactor #6 — validazione in tempo reale:
//   • RecordFormValidator.validateField() — valida un singolo campo
//     e restituisce null (OK) o una stringa di errore
//   • RecordFormValidator.validate() — invariato, valida tutto il form
//   • RecordFormValidator.hasErrors() — comodo per disabilitare il FAB

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sealed result type (invariato)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Tipi di campo — usati da validateField()
// ─────────────────────────────────────────────────────────────────────────────

enum FieldKind {
  /// Temperatura esterna [-40 ÷ +50 °C], obbligatoria.
  externalTemp,

  /// Consumo pompa di calore [0 ÷ 9999 kWh], obbligatorio.
  consumption,

  /// Temperatura stanza [5 ÷ 40 °C], obbligatoria se la stanza esiste.
  internalTemp,

  /// Consumo ACS [0 ÷ 9999 kWh], opzionale (campo vuoto = nessun errore).
  consumptionAcs,

  /// Energia da rete [0 ÷ 9999 kWh], opzionale.
  energyFromGrid,

  /// Produzione FV [0 ÷ 9999 kWh], opzionale.
  pvProduction,
}

// ─────────────────────────────────────────────────────────────────────────────
// RecordFormValidator
// ─────────────────────────────────────────────────────────────────────────────

class RecordFormValidator {
  // -------------------------------------------------------------------------
  // Range ammessi
  // -------------------------------------------------------------------------

  static const double extTempMin = -40.0;
  static const double extTempMax = 50.0;
  static const double intTempMin = 5.0;
  static const double intTempMax = 40.0;
  static const double consumptionMin = 0.0;
  static const double consumptionMax = 9999.0;

  // -------------------------------------------------------------------------
  // validateField — real-time, singolo campo
  // -------------------------------------------------------------------------

  /// Valida il valore testuale di un singolo campo.
  ///
  /// Restituisce `null` se il valore è valido,
  /// oppure una stringa di errore breve da mostrare inline.
  ///
  /// I campi opzionali ([FieldKind.consumptionAcs], [FieldKind.energyFromGrid],
  /// [FieldKind.pvProduction]) non generano errori se vuoti.
  ///
  /// [label] è il nome del campo, usato nei messaggi (es. "Soggiorno").
  static String? validateField(
    String rawValue, {
    required FieldKind kind,
    String label = '',
  }) {
    final text = rawValue.replaceAll(',', '.').trim();

    // Campi opzionali: vuoto = ok.
    final isOptional = kind == FieldKind.consumptionAcs ||
        kind == FieldKind.energyFromGrid ||
        kind == FieldKind.pvProduction;

    if (text.isEmpty) {
      if (isOptional) return null;
      return 'Campo obbligatorio';
    }

    final val = double.tryParse(text);
    if (val == null) return 'Valore non valido';

    switch (kind) {
      case FieldKind.externalTemp:
        if (val < extTempMin || val > extTempMax) {
          return 'Fuori range ($extTempMin\u00b0 \u00f7 $extTempMax\u00b0C)';
        }

      case FieldKind.consumption:
        if (val < consumptionMin || val > consumptionMax) {
          return 'Fuori range (0 \u00f7 9999 kWh)';
        }

      case FieldKind.internalTemp:
        if (val < intTempMin || val > intTempMax) {
          return '$label: fuori range ($intTempMin\u00b0 \u00f7 $intTempMax\u00b0C)';
        }

      case FieldKind.consumptionAcs:
      case FieldKind.energyFromGrid:
      case FieldKind.pvProduction:
        if (val < consumptionMin || val > consumptionMax) {
          return 'Fuori range (0 \u00f7 9999 kWh)';
        }
    }

    return null; // OK
  }

  // -------------------------------------------------------------------------
  // hasErrors — comodo per disabilitare il FAB
  // -------------------------------------------------------------------------

  /// Restituisce `true` se almeno uno dei controller ha un valore non valido.
  /// Considera i campi opzionali come facoltativo (nessun errore se vuoti).
  static bool hasErrors({
    required TextEditingController externalTempController,
    required TextEditingController consumptionController,
    required Map<String, TextEditingController> internalTempControllers,
    TextEditingController? consumptionAcsController,
    TextEditingController? energyFromGridController,
    TextEditingController? pvProductionController,
  }) {
    if (validateField(externalTempController.text,
            kind: FieldKind.externalTemp) !=
        null) return true;
    if (validateField(consumptionController.text, kind: FieldKind.consumption) !=
        null) return true;

    for (final entry in internalTempControllers.entries) {
      if (validateField(entry.value.text,
              kind: FieldKind.internalTemp, label: entry.key) !=
          null) return true;
    }

    if (consumptionAcsController != null &&
        validateField(consumptionAcsController.text,
                kind: FieldKind.consumptionAcs) !=
            null) return true;
    if (energyFromGridController != null &&
        validateField(energyFromGridController.text,
                kind: FieldKind.energyFromGrid) !=
            null) return true;
    if (pvProductionController != null &&
        validateField(pvProductionController.text,
                kind: FieldKind.pvProduction) !=
            null) return true;

    return false;
  }

  // -------------------------------------------------------------------------
  // validate — invariato, valida tutto il form (usato al salvataggio)
  // -------------------------------------------------------------------------

  static RecordValidationResult validate({
    required TextEditingController externalTempController,
    required TextEditingController consumptionController,
    required Map<String, TextEditingController> internalTempControllers,
  }) {
    if (externalTempController.text.trim().isEmpty ||
        consumptionController.text.trim().isEmpty) {
      return RecordValidationError(
        'Temperatura Esterna e Consumo sono obbligatori.',
      );
    }

    for (final entry in internalTempControllers.entries) {
      if (entry.value.text.trim().isEmpty) {
        return RecordValidationError(
          'Manca la temperatura per ${entry.key}.',
        );
      }
    }

    final double? extTemp = double.tryParse(
      externalTempController.text.replaceAll(',', '.'),
    );
    if (extTemp == null) {
      return RecordValidationError('Temperatura esterna non valida.');
    }
    if (extTemp < extTempMin || extTemp > extTempMax) {
      return RecordValidationError(
        'Temperatura esterna fuori range ($extTempMin\u00b0C \u00f7 $extTempMax\u00b0C).',
      );
    }

    final double? cons = double.tryParse(
      consumptionController.text.replaceAll(',', '.'),
    );
    if (cons == null) {
      return RecordValidationError('Valore consumo non valido.');
    }
    if (cons < consumptionMin || cons > consumptionMax) {
      return RecordValidationError(
        'Consumo fuori range ($consumptionMin \u00f7 $consumptionMax kWh).',
      );
    }

    final Map<String, double> internalTemps = {};
    for (final entry in internalTempControllers.entries) {
      final val = double.tryParse(entry.value.text.replaceAll(',', '.'));
      if (val == null) {
        return RecordValidationError(
          'La temperatura di ${entry.key} non \u00e8 un numero valido.',
        );
      }
      if (val < intTempMin || val > intTempMax) {
        return RecordValidationError(
          'Temperatura di ${entry.key} fuori range ($intTempMin\u00b0C \u00f7 $intTempMax\u00b0C).',
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
