// test/date_utils_test.dart
//
// Unit test per:
//   • parseItalianDateSafe() — parsing date italiano e ISO
//   • formatItalianDate()    — formattazione in dd/MM/yyyy

import 'package:flutter_test/flutter_test.dart';
import 'package:climasense/utils/date_utils.dart';

void main() {
  group('parseItalianDateSafe', () {
    test('formato italiano dd/MM/yyyy valido', () {
      final dt = parseItalianDateSafe('15/03/2025');
      expect(dt, isNotNull);
      expect(dt!.day, 15);
      expect(dt.month, 3);
      expect(dt.year, 2025);
    });

    test('formato ISO yyyy-MM-dd valido', () {
      final dt = parseItalianDateSafe('2025-03-15');
      expect(dt, isNotNull);
      expect(dt!.day, 15);
      expect(dt.month, 3);
    });

    test('formato ISO con orario valido', () {
      final dt = parseItalianDateSafe('2025-03-15T10:30:00');
      expect(dt, isNotNull);
    });

    test('stringa vuota restituisce null', () {
      expect(parseItalianDateSafe(''), isNull);
    });

    test('formato non riconosciuto restituisce null', () {
      expect(parseItalianDateSafe('domani'), isNull);
      expect(parseItalianDateSafe('15-03-2025'), isNull);
    });

    test('mese non valido restituisce null', () {
      expect(parseItalianDateSafe('15/13/2025'), isNull);
      expect(parseItalianDateSafe('15/00/2025'), isNull);
    });

    test('giorno non valido restituisce null', () {
      expect(parseItalianDateSafe('32/01/2025'), isNull);
      expect(parseItalianDateSafe('00/01/2025'), isNull);
    });

    test('giorno 29 febbraio anno bisestile valido', () {
      expect(parseItalianDateSafe('29/02/2024'), isNotNull);
    });

    test('giorno 29 febbraio anno non bisestile restituisce null', () {
      expect(parseItalianDateSafe('29/02/2025'), isNull);
    });

    test('anno fuori range restituisce null', () {
      expect(parseItalianDateSafe('01/01/1800'), isNull);
      expect(parseItalianDateSafe('01/01/2200'), isNull);
    });

    test('parti non numeriche restituiscono null', () {
      expect(parseItalianDateSafe('aa/01/2025'), isNull);
      expect(parseItalianDateSafe('01/bb/2025'), isNull);
    });
  });

  group('formatItalianDate', () {
    test('formatta correttamente con padding zero', () {
      final result = formatItalianDate(DateTime(2025, 3, 5));
      expect(result, '05/03/2025');
    });

    test('formatta correttamente senza padding necessario', () {
      final result = formatItalianDate(DateTime(2025, 12, 25));
      expect(result, '25/12/2025');
    });

    test('round-trip: format poi parse restituisce stessa data', () {
      final original = DateTime(2025, 7, 14);
      final formatted = formatItalianDate(original);
      final parsed = parseItalianDateSafe(formatted);
      expect(parsed, isNotNull);
      expect(parsed!.year, original.year);
      expect(parsed.month, original.month);
      expect(parsed.day, original.day);
    });
  });
}
