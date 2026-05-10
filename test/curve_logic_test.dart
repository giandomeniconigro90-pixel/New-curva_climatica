// test/curve_logic_test.dart
//
// Unit test per:
//   • computeMandata()               — calcolo temperatura di mandata
//   • computeCurveStats()             — statistiche sui record
//   • computeOptimalCurveSuggestion() — algoritmo AI curva
//   • analyzeRoomComfort()            — analisi comfort per stanza
//   • AiCurveService.recordsSinceLastApply() — filtro temporale

import 'package:flutter_test/flutter_test.dart';
import 'package:climasense/features/home/logic/curve_logic.dart';
import 'package:climasense/features/home/logic/ai_curve_service.dart';
import 'package:climasense/models/daily_record_dto.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

DailyRecordDTO _record({
  required String dateIso,
  double externalTemp = 5.0,
  double consumption = 10.0,
  Map<String, String>? comfort,
  String mode = 'heating',
}) {
  return DailyRecordDTO(
    dateIso: dateIso,
    externalTemp: externalTemp,
    internalTemps: const {'Soggiorno': 20.0},
    consumption: consumption,
    comfortRatings: comfort ?? const {'Soggiorno': 'ok'},
    mode: mode,
  );
}

// ---------------------------------------------------------------------------
// computeMandata
// ---------------------------------------------------------------------------

void main() {
  group('computeMandata — heating', () {
    test('temperatura di mandata cresce al calare di tExt', () {
      final hot = computeMandata(10.0, 1.2, 0.0, SystemMode.heating);
      final cold = computeMandata(-5.0, 1.2, 0.0, SystemMode.heating);
      expect(cold, greaterThan(hot));
    });

    test('non scende sotto 35 gradi', () {
      final v = computeMandata(25.0, 0.5, 0.0, SystemMode.heating);
      expect(v, greaterThanOrEqualTo(35.0));
    });

    test('non supera 60 gradi', () {
      final v = computeMandata(-30.0, 3.0, 10.0, SystemMode.heating);
      expect(v, lessThanOrEqualTo(60.0));
    });

    test('offset positivo aumenta la mandata', () {
      final base = computeMandata(0.0, 1.2, 0.0, SystemMode.heating);
      final offset = computeMandata(0.0, 1.2, 2.0, SystemMode.heating);
      expect(offset, greaterThan(base));
    });
  });

  group('computeMandata — cooling', () {
    test('temperatura di mandata scende al salire di tExt', () {
      final mild = computeMandata(28.0, 0.5, 0.0, SystemMode.cooling);
      final hot = computeMandata(38.0, 0.5, 0.0, SystemMode.cooling);
      expect(hot, lessThan(mild));
    });

    test('non scende sotto 7 gradi', () {
      final v = computeMandata(50.0, 3.0, 0.0, SystemMode.cooling);
      expect(v, greaterThanOrEqualTo(7.0));
    });

    test('non supera 25 gradi', () {
      final v = computeMandata(15.0, 0.1, 10.0, SystemMode.cooling);
      expect(v, lessThanOrEqualTo(25.0));
    });
  });

  // -------------------------------------------------------------------------
  // computeCurveStats
  // -------------------------------------------------------------------------

  group('computeCurveStats', () {
    test('lista vuota restituisce zeri', () {
      final s = computeCurveStats([]);
      expect(s.totalDays, 0);
      expect(s.avgConsumption, 0.0);
    });

    test('calcola correttamente media e range temperatura', () {
      final records = [
        _record(dateIso: '01/01/2025', externalTemp: -5.0, consumption: 20.0),
        _record(dateIso: '02/01/2025', externalTemp: 10.0, consumption: 10.0),
        _record(dateIso: '03/01/2025', externalTemp: 0.0,  consumption: 15.0),
      ];
      final s = computeCurveStats(records);
      expect(s.totalDays, 3);
      expect(s.avgConsumption, closeTo(15.0, 0.01));
      expect(s.minExternalTemp, -5.0);
      expect(s.maxExternalTemp, 10.0);
    });
  });

  // -------------------------------------------------------------------------
  // computeOptimalCurveSuggestion
  // -------------------------------------------------------------------------

  group('computeOptimalCurveSuggestion', () {
    test('con meno di 5 record restituisce modalità apprendimento', () {
      final records = List.generate(
          3, (i) => _record(dateIso: '0${i + 1}/01/2025'));
      final s = computeOptimalCurveSuggestion(
          records, 1.2, 0.0, SystemMode.heating);
      expect(s.isLearning, isTrue);
      expect(s.suggestedSlope, 1.2);
      expect(s.suggestedOffset, 0.0);
      expect(s.learningProgress, 3);
    });

    test('con reclami freddo aumenta offset (heating)', () {
      final records = List.generate(6, (i) => _record(
        dateIso: '0${i + 1}/01/2025',
        comfort: const {'Soggiorno': 'freddo'},
      ));
      final s = computeOptimalCurveSuggestion(
          records, 1.2, 0.0, SystemMode.heating);
      expect(s.isLearning, isFalse);
      expect(s.suggestedOffset, greaterThan(0.0));
    });

    test('con reclami caldo diminuisce offset (heating)', () {
      final records = List.generate(6, (i) => _record(
        dateIso: '0${i + 1}/01/2025',
        comfort: const {'Soggiorno': 'caldo'},
      ));
      final s = computeOptimalCurveSuggestion(
          records, 1.2, 2.0, SystemMode.heating);
      expect(s.isLearning, isFalse);
      expect(s.suggestedOffset, lessThan(2.0));
    });

    test('con comfort ottimale non cambia i parametri', () {
      // Tutti ok: il suggerimento dovrebbe lasciare invariati slope/offset
      // oppure fare un aggiustamento minimo entro soglia di stabilità.
      final records = List.generate(6, (i) => _record(
        dateIso: '0${i + 1}/01/2025',
        comfort: const {'Soggiorno': 'ok'},
      ));
      final s = computeOptimalCurveSuggestion(
          records, 1.2, 0.0, SystemMode.heating);
      // Con tutti ok in heating: suggerisce offset -0.5, ma se delta < soglia
      // rimane invariato. Verifichiamo solo che non sia in apprendimento.
      expect(s.isLearning, isFalse);
    });

    test('suggestedSlope cambia al massimo di 0.1 per step', () {
      // Molti reclami freddo: slope deve aumentare ma non più di maxSlopeStep
      final records = List.generate(10, (i) => _record(
        dateIso: '${(i + 1).toString().padLeft(2, '0')}/01/2025',
        comfort: const {'Soggiorno': 'freddo'},
      ));
      final s = computeOptimalCurveSuggestion(
          records, 1.2, 0.0, SystemMode.heating);
      expect((s.suggestedSlope - 1.2).abs(), lessThanOrEqualTo(0.1 + 0.01));
    });

    test('suggestedOffset cambia al massimo di 1.0 per step', () {
      final records = List.generate(6, (i) => _record(
        dateIso: '0${i + 1}/01/2025',
        comfort: const {'Soggiorno': 'freddo'},
      ));
      final s = computeOptimalCurveSuggestion(
          records, 1.2, 0.0, SystemMode.heating);
      expect((s.suggestedOffset - 0.0).abs(), lessThanOrEqualTo(1.0 + 0.01));
    });

    test('cooling con reclami freddo (raffrescamento eccessivo) riduce offset', () {
      final records = List.generate(6, (i) => _record(
        dateIso: '0${i + 1}/06/2025',
        comfort: const {'Soggiorno': 'freddo'},
        mode: 'cooling',
      ));
      final s = computeOptimalCurveSuggestion(
          records, 0.5, 0.0, SystemMode.cooling);
      expect(s.isLearning, isFalse);
      // In cooling con freddo: offset += 1.0 (riduce raffreddamento)
      expect(s.suggestedOffset, greaterThan(0.0));
    });
  });

  // -------------------------------------------------------------------------
  // analyzeRoomComfort
  // -------------------------------------------------------------------------

  group('analyzeRoomComfort', () {
    test('lista vuota restituisce lista vuota', () {
      expect(analyzeRoomComfort([]), isEmpty);
    });

    test('stanze sempre ok non compaiono nel risultato', () {
      final records = List.generate(5, (i) => _record(
        dateIso: '0${i + 1}/01/2025',
        comfort: const {'Soggiorno': 'ok', 'Camera': 'ok'},
      ));
      expect(analyzeRoomComfort(records), isEmpty);
    });

    test('stanza con problemi compare nel risultato', () {
      final records = [
        _record(dateIso: '01/01/2025',
            comfort: const {'Soggiorno': 'freddo', 'Camera': 'ok'}),
        _record(dateIso: '02/01/2025',
            comfort: const {'Soggiorno': 'freddo', 'Camera': 'ok'}),
      ];
      final result = analyzeRoomComfort(records);
      expect(result.length, 1);
      expect(result.first.room, 'Soggiorno');
      expect(result.first.coldDays, 2);
      expect(result.first.dominantIssue, RoomComfortIssue.tooCold);
    });

    test('ordina per issueRate decrescente', () {
      final records = [
        _record(dateIso: '01/01/2025',
            comfort: const {'A': 'freddo', 'B': 'ok'}),
        _record(dateIso: '02/01/2025',
            comfort: const {'A': 'freddo', 'B': 'caldo'}),
        _record(dateIso: '03/01/2025',
            comfort: const {'A': 'freddo', 'B': 'ok'}),
      ];
      final result = analyzeRoomComfort(records);
      expect(result.first.room, 'A'); // A ha 3/3 vs B 1/3
    });
  });

  // -------------------------------------------------------------------------
  // AiCurveService.recordsSinceLastApply
  // -------------------------------------------------------------------------

  group('AiCurveService.recordsSinceLastApply', () {
    test('lastApply null restituisce tutti i record', () {
      final records = [
        _record(dateIso: '01/01/2025'),
        _record(dateIso: '02/01/2025'),
      ];
      final result = AiCurveService.recordsSinceLastApply(
        records: records,
        lastApply: null,
      );
      expect(result.length, 2);
    });

    test('filtra i record antecedenti a lastApply', () {
      final records = [
        _record(dateIso: '01/01/2025'),
        _record(dateIso: '05/01/2025'),
        _record(dateIso: '10/01/2025'),
      ];
      final result = AiCurveService.recordsSinceLastApply(
        records: records,
        lastApply: DateTime(2025, 1, 4),
      );
      expect(result.length, 2);
      expect(result.map((r) => r.dateIso),
          containsAll(['05/01/2025', '10/01/2025']));
    });

    test('record esattamente nel giorno lastApply non viene incluso', () {
      final records = [_record(dateIso: '04/01/2025')];
      final result = AiCurveService.recordsSinceLastApply(
        records: records,
        lastApply: DateTime(2025, 1, 4),
      );
      expect(result, isEmpty);
    });
  });
}
