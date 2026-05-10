// test/record_form_validator_test.dart
//
// Unit test per RecordFormValidator:
//   • validateField() — validazione real-time singolo campo
//   • validate()      — validazione form completo al salvataggio

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climasense/features/home/logic/record_form_validator.dart';

// Helper: crea un TextEditingController con valore preset
TextEditingController _ctrl(String value) =>
    TextEditingController(text: value);

void main() {
  // -------------------------------------------------------------------------
  // validateField — externalTemp
  // -------------------------------------------------------------------------

  group('validateField — externalTemp', () {
    test('campo vuoto restituisce errore obbligatorio', () {
      expect(
        RecordFormValidator.validateField('',
            kind: FieldKind.externalTemp),
        isNotNull,
      );
    });

    test('valore non numerico restituisce errore', () {
      expect(
        RecordFormValidator.validateField('abc',
            kind: FieldKind.externalTemp),
        isNotNull,
      );
    });

    test('valore fuori range max restituisce errore', () {
      expect(
        RecordFormValidator.validateField('51',
            kind: FieldKind.externalTemp),
        isNotNull,
      );
    });

    test('valore fuori range min restituisce errore', () {
      expect(
        RecordFormValidator.validateField('-41',
            kind: FieldKind.externalTemp),
        isNotNull,
      );
    });

    test('valore valido restituisce null', () {
      expect(
        RecordFormValidator.validateField('5.5',
            kind: FieldKind.externalTemp),
        isNull,
      );
    });

    test('virgola come separatore decimale accettata', () {
      expect(
        RecordFormValidator.validateField('5,5',
            kind: FieldKind.externalTemp),
        isNull,
      );
    });

    test('boundary min (-40) accettato', () {
      expect(
        RecordFormValidator.validateField('-40',
            kind: FieldKind.externalTemp),
        isNull,
      );
    });

    test('boundary max (50) accettato', () {
      expect(
        RecordFormValidator.validateField('50',
            kind: FieldKind.externalTemp),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // validateField — consumption
  // -------------------------------------------------------------------------

  group('validateField — consumption', () {
    test('consumo negativo restituisce errore', () {
      expect(
        RecordFormValidator.validateField('-1',
            kind: FieldKind.consumption),
        isNotNull,
      );
    });

    test('consumo 0 accettato', () {
      expect(
        RecordFormValidator.validateField('0',
            kind: FieldKind.consumption),
        isNull,
      );
    });

    test('consumo 9999 accettato', () {
      expect(
        RecordFormValidator.validateField('9999',
            kind: FieldKind.consumption),
        isNull,
      );
    });

    test('consumo > 9999 restituisce errore', () {
      expect(
        RecordFormValidator.validateField('10000',
            kind: FieldKind.consumption),
        isNotNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // validateField — campi opzionali
  // -------------------------------------------------------------------------

  group('validateField — campi opzionali', () {
    for (final kind in [
      FieldKind.consumptionAcs,
      FieldKind.energyFromGrid,
      FieldKind.pvProduction,
    ]) {
      test('$kind vuoto è valido (opzionale)', () {
        expect(
          RecordFormValidator.validateField('', kind: kind),
          isNull,
        );
      });

      test('$kind con valore valido accettato', () {
        expect(
          RecordFormValidator.validateField('12.5', kind: kind),
          isNull,
        );
      });

      test('$kind con valore fuori range restituisce errore', () {
        expect(
          RecordFormValidator.validateField('10000', kind: kind),
          isNotNull,
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // validateField — internalTemp
  // -------------------------------------------------------------------------

  group('validateField — internalTemp', () {
    test('temperatura stanza fuori range basso restituisce errore', () {
      expect(
        RecordFormValidator.validateField('4',
            kind: FieldKind.internalTemp, label: 'Soggiorno'),
        isNotNull,
      );
    });

    test('temperatura stanza fuori range alto restituisce errore', () {
      expect(
        RecordFormValidator.validateField('41',
            kind: FieldKind.internalTemp, label: 'Camera'),
        isNotNull,
      );
    });

    test('temperatura stanza valida restituisce null', () {
      expect(
        RecordFormValidator.validateField('20',
            kind: FieldKind.internalTemp, label: 'Soggiorno'),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // validate — form completo
  // -------------------------------------------------------------------------

  group('validate — form completo', () {
    test('form valido restituisce RecordValidationOk', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl('5.0'),
        consumptionController: _ctrl('12.5'),
        internalTempControllers: {'Soggiorno': _ctrl('20.0')},
      );
      expect(result, isA<RecordValidationOk>());
      final ok = result as RecordValidationOk;
      expect(ok.externalTemp, 5.0);
      expect(ok.consumption, 12.5);
      expect(ok.internalTemps['Soggiorno'], 20.0);
    });

    test('temperatura esterna vuota restituisce errore', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl(''),
        consumptionController: _ctrl('12.5'),
        internalTempControllers: {'Soggiorno': _ctrl('20.0')},
      );
      expect(result, isA<RecordValidationError>());
    });

    test('consumo vuoto restituisce errore', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl('5.0'),
        consumptionController: _ctrl(''),
        internalTempControllers: {'Soggiorno': _ctrl('20.0')},
      );
      expect(result, isA<RecordValidationError>());
    });

    test('temperatura stanza vuota restituisce errore con nome stanza', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl('5.0'),
        consumptionController: _ctrl('12.5'),
        internalTempControllers: {'Camera': _ctrl('')},
      );
      expect(result, isA<RecordValidationError>());
      final err = result as RecordValidationError;
      expect(err.message, contains('Camera'));
    });

    test('temperatura esterna non numerica restituisce errore', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl('abc'),
        consumptionController: _ctrl('12.5'),
        internalTempControllers: {'Soggiorno': _ctrl('20.0')},
      );
      expect(result, isA<RecordValidationError>());
    });

    test('temperatura esterna fuori range restituisce errore', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl('99'),
        consumptionController: _ctrl('12.5'),
        internalTempControllers: {'Soggiorno': _ctrl('20.0')},
      );
      expect(result, isA<RecordValidationError>());
    });

    test('virgola decimale accettata in tutti i campi numerici', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl('5,5'),
        consumptionController: _ctrl('12,5'),
        internalTempControllers: {'Soggiorno': _ctrl('20,0')},
      );
      expect(result, isA<RecordValidationOk>());
    });

    test('più stanze tutte valide restituisce ok con tutte le temp', () {
      final result = RecordFormValidator.validate(
        externalTempController: _ctrl('3.0'),
        consumptionController: _ctrl('8.0'),
        internalTempControllers: {
          'Soggiorno': _ctrl('21.0'),
          'Camera': _ctrl('19.0'),
          'Bagno': _ctrl('22.0'),
        },
      );
      expect(result, isA<RecordValidationOk>());
      final ok = result as RecordValidationOk;
      expect(ok.internalTemps.length, 3);
    });
  });
}
