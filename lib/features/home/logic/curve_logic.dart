// lib/features/home/logic/curve_logic.dart

import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import '../../../models/daily_record_dto.dart';
import '../../../utils/date_utils.dart';

enum SystemMode { heating, cooling }

/// Extension per convertire SystemMode in stringa persistita su Hive/JSON.
/// Usare sempre questo invece di stringhe hardcoded.
extension SystemModeX on SystemMode {
  String toModeString() => this == SystemMode.heating ? 'heating' : 'cooling';

  static SystemMode fromString(String s) =>
      s == 'cooling' ? SystemMode.cooling : SystemMode.heating;
}

class CurveStats {
  final double avgConsumption;
  final double minExternalTemp;
  final double maxExternalTemp;
  final int totalDays;

  CurveStats({
    required this.avgConsumption,
    required this.minExternalTemp,
    required this.maxExternalTemp,
    required this.totalDays,
  });
}

class CurveSuggestion {
  final double suggestedSlope;
  final double suggestedOffset;
  final double comfortScore;
  final double energyScore;
  final String smartTip;
  final bool isLearning;
  final int learningProgress;

  CurveSuggestion({
    required this.suggestedSlope,
    required this.suggestedOffset,
    required this.comfortScore,
    required this.energyScore,
    required this.smartTip,
    required this.isLearning,
    required this.learningProgress,
  });
}

/// Calcola la temperatura di mandata target basata sulla curva climatica.
double computeMandata(double tExt, double slope, double offset, SystemMode mode) {
  if (mode == SystemMode.heating) {
    double targetAmbiente = 20.0;
    double rawMandata = targetAmbiente + (targetAmbiente - tExt) * slope + offset;
    if (rawMandata < 35.0) rawMandata = 35.0;
    if (rawMandata > 60.0) rawMandata = 60.0;
    return rawMandata;
  } else {
    double targetAmbiente = 26.0;
    double rawMandata = 18.0 - (tExt - targetAmbiente) * slope + offset;
    if (rawMandata < 7.0) rawMandata = 7.0;
    if (rawMandata > 25.0) rawMandata = 25.0;
    return rawMandata;
  }
}

CurveStats computeCurveStats(List<DailyRecordDTO> records) {
  if (records.isEmpty) {
    return CurveStats(avgConsumption: 0, minExternalTemp: 0, maxExternalTemp: 0, totalDays: 0);
  }

  double totalCons = 0;
  double minT = double.infinity;
  double maxT = double.negativeInfinity;

  for (var r in records) {
    totalCons += r.consumption;
    if (r.externalTemp < minT) minT = r.externalTemp;
    if (r.externalTemp > maxT) maxT = r.externalTemp;
  }

  return CurveStats(
    avgConsumption: totalCons / records.length,
    minExternalTemp: minT,
    maxExternalTemp: maxT,
    totalDays: records.length,
  );
}

/// Calcola la curva ottimale suggerita dall'AI.
///
/// Responsabilità di questa funzione:
/// - Filtrare i record successivi a [lastAppliedDate] (finestra temporale AI)
/// - Analizzare comfort ed energia
/// - Suggerire slope/offset con passo prudenziale
///
/// Il filtro per modalità (heating/cooling) è responsabilità del chiamante:
/// passare [HomeNotifier.records] o [HomeNotifier.recordsSinceLastApply],
/// che sono già filtrati per modalità corrente.
CurveSuggestion computeOptimalCurveSuggestion(
    List<DailyRecordDTO> records,
    double currentSlope,
    double currentOffset,
    SystemMode mode,
    [DateTime? lastAppliedDate]) {
  var filteredRecords = records;
  if (lastAppliedDate != null) {
    final lastDay = DateTime(
        lastAppliedDate.year, lastAppliedDate.month, lastAppliedDate.day);
    filteredRecords = records.where((r) {
      final rDate = parseItalianDateSafe(r.dateIso);
      if (rDate == null) return false;
      return rDate.isAfter(lastDay);
    }).toList();
  }

  // FASE 1: APPRENDIMENTO
  if (filteredRecords.length < 5) {
    final String message;
    if (lastAppliedDate == null) {
      message =
          'Sto imparando come reagisce la tua casa. Continua a registrare dati per almeno ${5 - filteredRecords.length} giorni.';
    } else {
      message =
          'Hai modificato la curva di recente. Attendo 5 giorni di NUOVI dati per valutare le modifiche. (Giorni validi: ${filteredRecords.length}/5)';
    }
    return CurveSuggestion(
      suggestedSlope: currentSlope,
      suggestedOffset: currentOffset,
      comfortScore: 0.5,
      energyScore: 1.0,
      smartTip: message,
      isLearning: true,
      learningProgress: filteredRecords.length,
    );
  }

  // FASE 2: ANALISI
  int coldComplaints = 0;
  int hotComplaints = 0;
  int okDays = 0;

  for (var r in filteredRecords) {
    final bool dayCold = r.comfortRatings.values.contains('freddo');
    final bool dayHot = r.comfortRatings.values.contains('caldo');
    if (dayCold) {
      coldComplaints++;
    } else if (dayHot) {
      hotComplaints++;
    } else {
      okDays++;
    }
  }

  final double comfortScore = okDays / filteredRecords.length;
  double targetSlope = currentSlope;
  double targetOffset = currentOffset;
  String tip;

  if (coldComplaints > hotComplaints) {
    targetOffset += 1.0;
    if (coldComplaints > filteredRecords.length * 0.3) targetSlope += 0.1;
    tip = 'Rilevati giorni con comfort insufficiente (freddo). Aumento la potenza.';
  } else if (hotComplaints > coldComplaints) {
    targetOffset -= 1.0;
    if (hotComplaints > filteredRecords.length * 0.3) targetSlope -= 0.1;
    tip = 'Rilevato eccesso di calore. Riduco la potenza per risparmiare.';
  } else {
    if (mode == SystemMode.heating) {
      targetOffset -= 0.5;
    } else {
      targetOffset += 0.5;
    }
    tip = 'Comfort ottimale! Ottimizzo i consumi.';
  }

  // FASE 3: PRUDENZA — limita il passo massimo per evitare salti bruschi
  const double maxSlopeStep = 0.1;
  const double maxOffsetStep = 1.0;

  final double diffSlope = targetSlope - currentSlope;
  final double diffOffset = targetOffset - currentOffset;

  if (diffSlope.abs() > maxSlopeStep) {
    targetSlope = currentSlope + (diffSlope.sign * maxSlopeStep);
  }
  if (diffOffset.abs() > maxOffsetStep) {
    targetOffset = currentOffset + (diffOffset.sign * maxOffsetStep);
  }

  targetSlope = (targetSlope * 100).round() / 100.0;
  targetOffset = (targetOffset * 10).round() / 10.0;

  if ((targetSlope - currentSlope).abs() < 0.01 &&
      (targetOffset - currentOffset).abs() < 0.1) {
    targetSlope = currentSlope;
    targetOffset = currentOffset;
    tip = 'Parametri attuali ottimali con i nuovi dati. Mantieni così.';
  }

  return CurveSuggestion(
    suggestedSlope: targetSlope,
    suggestedOffset: targetOffset,
    comfortScore: comfortScore,
    energyScore: 1.0,
    smartTip: tip,
    isLearning: false,
    learningProgress: filteredRecords.length, // conteggio reale, non hardcoded
  );
}

/// Costruisce i punti della curva climatica per il grafico.
///
/// Guard: se il range è degenere (min > max oppure min == max),
/// viene usato il range di default per la modalità per evitare
/// un grafico vuoto o un loop infinito.
List<FlSpot> buildCurveSpots({
  required double slope,
  required double offset,
  required SystemMode mode,
  required double minExternalTemp,
  required double maxExternalTemp,
  double step = 1.0,
}) {
  double effectiveMin = minExternalTemp;
  double effectiveMax = maxExternalTemp;

  // Range degenere: usa fallback per modalità
  if (effectiveMin >= effectiveMax) {
    effectiveMin = mode == SystemMode.heating ? -10.0 : 20.0;
    effectiveMax = mode == SystemMode.heating ? 20.0 : 40.0;
  }

  // Un solo punto: allarga di ±5 per avere una curva visibile
  if ((effectiveMax - effectiveMin) < step) {
    effectiveMin -= 5.0;
    effectiveMax += 5.0;
  }

  final List<FlSpot> spots = [];
  for (double t = effectiveMin; t <= effectiveMax; t += step) {
    final double mandata = computeMandata(t, slope, offset, mode);
    spots.add(FlSpot(t, mandata));
  }
  return spots;
}
