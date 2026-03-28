// test/curve_logic_test.dart
//
// Esegui con: flutter test test/curve_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:curva_climatica/features/home/logic/curve_logic.dart';
import 'package:curva_climatica/models/daily_record_dto.dart';

void main() {
  // ---------------------------------------------------------------------------
  // computeMandata — modalità RISCALDAMENTO
  // ---------------------------------------------------------------------------
  group('computeMandata [heating]', () {
    const slope = 1.2;
    const offset = 0.0;
    const mode = SystemMode.heating;

    test('temperatura esterna tipica invernale (0°C)', () {
      // tExt=0 → rawMandata = 20 + (20-0)*1.2 + 0 = 44
      final result = computeMandata(0, slope, offset, mode);
      expect(result, closeTo(44.0, 0.01));
    });

    test('temperatura esterna mite (15°C)', () {
      // rawMandata = 20 + (20-15)*1.2 = 26 → clamp a 35
      final result = computeMandata(15, slope, offset, mode);
      expect(result, 35.0);
    });

    test('clamp inferiore: temperature esterne alte producono min 35°C', () {
      final result = computeMandata(25, slope, offset, mode);
      expect(result, 35.0);
    });

    test('clamp superiore: temperature molto basse producono max 60°C', () {
      // tExt=-20 → rawMandata = 20 + 40*1.2 = 68 → clamp a 60
      final result = computeMandata(-20, slope, offset, mode);
      expect(result, 60.0);
    });

    test('offset positivo aumenta la mandata', () {
      final withoutOffset = computeMandata(0, slope, 0.0, mode);
      final withOffset = computeMandata(0, slope, 3.0, mode);
      expect(withOffset, greaterThan(withoutOffset));
    });

    test('offset negativo diminuisce la mandata', () {
      final withoutOffset = computeMandata(0, slope, 0.0, mode);
      final withOffset = computeMandata(0, slope, -3.0, mode);
      expect(withOffset, lessThan(withoutOffset));
    });

    test('slope più alta = mandata più alta a parità di tExt fredda', () {
      final low = computeMandata(0, 1.0, 0.0, mode);
      final high = computeMandata(0, 1.5, 0.0, mode);
      expect(high, greaterThan(low));
    });
  });

  // ---------------------------------------------------------------------------
  // computeMandata — modalità RAFFRESCAMENTO
  // ---------------------------------------------------------------------------
  group('computeMandata [cooling]', () {
    const slope = 0.5;
    const offset = 0.0;
    const mode = SystemMode.cooling;

    test('temperatura esterna tipica estiva (35°C)', () {
      // rawMandata = 18 - (35-26)*0.5 = 18 - 4.5 = 13.5
      final result = computeMandata(35, slope, offset, mode);
      expect(result, closeTo(13.5, 0.01));
    });

    test('clamp superiore: temperature esterne basse producono max 25°C', () {
      // tExt=10 → rawMandata = 18 - (10-26)*0.5 = 18 + 8 = 26 → clamp a 25
      final result = computeMandata(10, slope, offset, mode);
      expect(result, 25.0);
    });

    test('clamp inferiore: temperature molto alte producono min 7°C', () {
      // tExt=60 → rawMandata = 18 - (60-26)*0.5 = 18 - 17 = 1 → clamp a 7
      final result = computeMandata(60, slope, offset, mode);
      expect(result, 7.0);
    });

    test('offset positivo aumenta la mandata in cooling', () {
      final withoutOffset = computeMandata(35, slope, 0.0, mode);
      final withOffset = computeMandata(35, slope, 2.0, mode);
      expect(withOffset, greaterThan(withoutOffset));
    });
  });

  // ---------------------------------------------------------------------------
  // computeCurveStats
  // ---------------------------------------------------------------------------
  group('computeCurveStats', () {
    test('lista vuota restituisce tutti zeri', () {
      final stats = computeCurveStats([]);
      expect(stats.totalDays, 0);
      expect(stats.avgConsumption, 0.0);
      expect(stats.minExternalTemp, 0.0);
      expect(stats.maxExternalTemp, 0.0);
    });

    test('un solo record', () {
      final records = [
        DailyRecordDTO(
          dateIso: '01/01/2026',
          externalTemp: -5.0,
          internalTemps: {},
          consumption: 20.0,
          comfortRatings: {},
        ),
      ];
      final stats = computeCurveStats(records);
      expect(stats.totalDays, 1);
      expect(stats.avgConsumption, 20.0);
      expect(stats.minExternalTemp, -5.0);
      expect(stats.maxExternalTemp, -5.0);
    });

    test('più record: media, min, max corretti', () {
      final records = [
        DailyRecordDTO(
          dateIso: '01/01/2026',
          externalTemp: -10.0,
          internalTemps: {},
          consumption: 30.0,
          comfortRatings: {},
        ),
        DailyRecordDTO(
          dateIso: '02/01/2026',
          externalTemp: 5.0,
          internalTemps: {},
          consumption: 10.0,
          comfortRatings: {},
        ),
        DailyRecordDTO(
          dateIso: '03/01/2026',
          externalTemp: 0.0,
          internalTemps: {},
          consumption: 20.0,
          comfortRatings: {},
        ),
      ];
      final stats = computeCurveStats(records);
      expect(stats.totalDays, 3);
      expect(stats.avgConsumption, closeTo(20.0, 0.01));
      expect(stats.minExternalTemp, -10.0);
      expect(stats.maxExternalTemp, 5.0);
    });

    test('temperature estreme oltre i vecchi valori magici ±100', () {
      final records = [
        DailyRecordDTO(
          dateIso: '01/07/2026',
          externalTemp: -40.0,
          internalTemps: {},
          consumption: 50.0,
          comfortRatings: {},
        ),
        DailyRecordDTO(
          dateIso: '02/07/2026',
          externalTemp: 50.0,
          internalTemps: {},
          consumption: 5.0,
          comfortRatings: {},
        ),
      ];
      final stats = computeCurveStats(records);
      expect(stats.minExternalTemp, -40.0);
      expect(stats.maxExternalTemp, 50.0);
    });
  });
}
