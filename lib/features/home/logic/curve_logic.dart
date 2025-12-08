// lib/features/home/logic/curve_logic.dart

import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import '../../../models/daily_record_dto.dart';

enum SystemMode { heating, cooling }

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
  final double comfortScore; // 0.0 - 1.0 (1.0 ottimo)
  final double energyScore;  // > 1.0 significa che stiamo consumando troppo
  final String smartTip;
  final bool isLearning;
  final int learningProgress; // 0-5 giorni minimi

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

/// Calcola la temperatura di mandata target basata sulla curva climatica
/// IMPORTANTE: Offset deve essere inteso come correzione relativa (es. 0.0, +2.0, -1.5)
double computeMandata(double tExt, double slope, double offset, SystemMode mode) {
  if (mode == SystemMode.heating) {
    // Heating (Inverno)
    // Target ambiente fittizio 20°C.
    double targetAmbiente = 20.0;
    double rawMandata = targetAmbiente + (targetAmbiente - tExt) * slope + offset;

    // LIMITI RISCALDAMENTO (Fan Coil)
    if (rawMandata < 35.0) rawMandata = 35.0; // Minimo per ventilazione
    if (rawMandata > 60.0) rawMandata = 60.0; // Massimo sicurezza

    return rawMandata;
  } else {
    // Cooling (Estate)
    // Target ambiente fittizio 26°C. Base mandata 18°C.
    // Formula: 18 + (T_est - 26) * Slope + Offset
    // Più fa caldo fuori, più l'acqua deve essere fredda?
    // NO, attenzione: La curva standard raffrescamento abbassa la mandata se fa caldo.
    // Formula tipica: 18 - (Text - 26) * Slope

    double targetAmbiente = 26.0;
    double rawMandata = 18.0 - (tExt - targetAmbiente) * slope + offset;

    // LIMITI RAFFRESCAMENTO
    if (rawMandata < 7.0) rawMandata = 7.0; // Minimo anti-condensa
    if (rawMandata > 25.0) rawMandata = 25.0; // Massimo inutile

    return rawMandata;
  }
}

CurveStats computeCurveStats(List<DailyRecordDTO> records) {
  if (records.isEmpty) {
    return CurveStats(avgConsumption: 0, minExternalTemp: 0, maxExternalTemp: 0, totalDays: 0);
  }

  double totalCons = 0;
  double minT = 100;
  double maxT = -100;

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

List<DailyRecordDTO> filterRecordsByMode(List<DailyRecordDTO> records, SystemMode mode) {
  if (mode == SystemMode.heating) {
    return records.where((r) => r.externalTemp < 18.0).toList();
  } else {
    return records.where((r) => r.externalTemp >= 18.0).toList();
  }
}

/// CORE LOGIC: Calcola il suggerimento "Prudente"
CurveSuggestion computeOptimalCurveSuggestion(
    List<DailyRecordDTO> allRecords,
    double currentSlope,
    double currentOffset,
    SystemMode mode,
    ) {
  final records = filterRecordsByMode(allRecords, mode);

  // FASE 1: APPRENDIMENTO
  if (records.length < 5) {
    return CurveSuggestion(
      suggestedSlope: currentSlope,
      suggestedOffset: currentOffset,
      comfortScore: 0.5,
      energyScore: 1.0,
      smartTip: "Sto imparando come reagisce la tua casa. Continua a registrare dati per almeno ${5 - records.length} giorni.",
      isLearning: true,
      learningProgress: records.length,
    );
  }

  // FASE 2: ANALISI
  int coldComplaints = 0;
  int hotComplaints = 0;
  int okDays = 0;

  for (var r in records) {
    bool dayCold = r.comfortRatings.values.contains('freddo');
    bool dayHot = r.comfortRatings.values.contains('caldo');

    if (dayCold) coldComplaints++;
    else if (dayHot) hotComplaints++;
    else okDays++;
  }

  double comfortScore = okDays / records.length;

  double targetSlope = currentSlope;
  double targetOffset = currentOffset;
  String tip = "";

  if (coldComplaints > hotComplaints) {
    // Fa freddo -> Alziamo la temperatura (Offset +)
    targetOffset += 1.0;
    if (coldComplaints > records.length * 0.3) {
      if (mode == SystemMode.heating) targetSlope += 0.1;
      // In estate, slope alto = acqua più fredda col caldo, quindi slope+ ok
      else targetSlope += 0.1;
    }
    tip = "Rilevati giorni con comfort insufficiente (freddo/caldo). Aumento la potenza.";

  } else if (hotComplaints > coldComplaints) {
    // Fa caldo -> Abbassiamo la temperatura (Offset -)
    targetOffset -= 1.0;
    if (hotComplaints > records.length * 0.3) {
      if (mode == SystemMode.heating) targetSlope -= 0.1;
      else targetSlope -= 0.1;
    }
    tip = "Rilevato eccesso di calore/freddo. Riduco la potenza per risparmiare.";

  } else {
    // Comfort OK -> Fine Tuning per risparmio
    if (mode == SystemMode.heating) targetOffset -= 0.5; // Inverno: abbassa T
    else targetOffset += 0.5; // Estate: alza T (acqua meno gelida)
    tip = "Comfort ottimale! Ottimizzo i consumi.";
  }

  // FASE 3: PRUDENZA (Damping)
  const double MAX_SLOPE_STEP = 0.1;
  const double MAX_OFFSET_STEP = 1.0;

  double diffSlope = targetSlope - currentSlope;
  double diffOffset = targetOffset - currentOffset;

  if (diffSlope.abs() > MAX_SLOPE_STEP) {
    targetSlope = currentSlope + (diffSlope.sign * MAX_SLOPE_STEP);
  }
  if (diffOffset.abs() > MAX_OFFSET_STEP) {
    targetOffset = currentOffset + (diffOffset.sign * MAX_OFFSET_STEP);
  }

  // Arrotondamento
  targetSlope = (targetSlope * 100).round() / 100.0;
  targetOffset = (targetOffset * 10).round() / 10.0;

  // FASE 4: CHECK INUTILITÀ
  if ((targetSlope - currentSlope).abs() < 0.01 && (targetOffset - currentOffset).abs() < 0.1) {
    targetSlope = currentSlope;
    targetOffset = currentOffset;
    tip = "Parametri attuali ottimali. Nessuna modifica necessaria al momento.";
  }

  return CurveSuggestion(
    suggestedSlope: targetSlope,
    suggestedOffset: targetOffset,
    comfortScore: comfortScore,
    energyScore: 1.0,
    smartTip: tip,
    isLearning: false,
    learningProgress: 5,
  );
}

// Genera i punti per il grafico (LineChart)
List<FlSpot> buildCurveSpots({
  required double slope,
  required double offset,
  required SystemMode mode,
  required double minExternalTemp,
  required double maxExternalTemp,
  double step = 1.0,
}) {
  final List<FlSpot> spots = [];
  for (double t = minExternalTemp; t <= maxExternalTemp; t += step) {
    final double mandata = computeMandata(t, slope, offset, mode);
    spots.add(FlSpot(t, mandata));
  }
  return spots;
}
