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

/// Calcola la temperatura di mandata target basata sulla curva climatica
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

/// Filtra per campo mode (non più per temperatura esterna)
List<DailyRecordDTO> filterRecordsByMode(List<DailyRecordDTO> records, SystemMode mode) {
  final modeStr = mode == SystemMode.heating ? 'heating' : 'cooling';
  return records.where((r) => r.mode == modeStr).toList();
}

/// Parsa date in formato dd/MM/yyyy o ISO yyyy-MM-dd
DateTime? _parseDateSafe(String dateIso) {
  // Formato italiano dd/MM/yyyy
  final slashParts = dateIso.split('/');
  if (slashParts.length == 3) {
    final d = int.tryParse(slashParts[0]);
    final m = int.tryParse(slashParts[1]);
    final y = int.tryParse(slashParts[2]);
    if (d != null && m != null && y != null) return DateTime(y, m, d);
  }
  // Formato ISO yyyy-MM-dd o yyyy-MM-ddTHH:mm:ss
  try {
    return DateTime.parse(dateIso);
  } catch (_) {}
  return null;
}

CurveSuggestion computeOptimalCurveSuggestion(
    List<DailyRecordDTO> allRecords,
    double currentSlope,
    double currentOffset,
    SystemMode mode,
    [DateTime? lastAppliedDate]
    ) {

  // 1. Filtra per mode usando il campo mode (non la temperatura)
  var records = filterRecordsByMode(allRecords, mode);

  // 2. Filtra per data con parser robusto (gestisce dd/MM/yyyy e ISO)
  if (lastAppliedDate != null) {
    final lastDay = DateTime(lastAppliedDate.year, lastAppliedDate.month, lastAppliedDate.day);
    records = records.where((r) {
      final rDate = _parseDateSafe(r.dateIso);
      if (rDate == null) return false;
      return rDate.isAfter(lastDay);
    }).toList();
  }

  // FASE 1: APPRENDIMENTO
  if (records.length < 5) {
    String message;
    if (lastAppliedDate == null) {
      message = "Sto imparando come reagisce la tua casa. Continua a registrare dati per almeno ${5 - records.length} giorni.";
    } else {
      message = "Hai modificato la curva di recente. Attendo 5 giorni di NUOVI dati per valutare le modifiche. (Giorni validi: ${records.length}/5)";
    }

    return CurveSuggestion(
      suggestedSlope: currentSlope,
      suggestedOffset: currentOffset,
      comfortScore: 0.5,
      energyScore: 1.0,
      smartTip: message,
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
    targetOffset += 1.0;
    if (coldComplaints > records.length * 0.3) {
      targetSlope += 0.1;
    }
    tip = "Rilevati giorni con comfort insufficiente (freddo). Aumento la potenza.";
  } else if (hotComplaints > coldComplaints) {
    targetOffset -= 1.0;
    if (hotComplaints > records.length * 0.3) {
      targetSlope -= 0.1;
    }
    tip = "Rilevato eccesso di calore. Riduco la potenza per risparmiare.";
  } else {
    if (mode == SystemMode.heating) targetOffset -= 0.5;
    else targetOffset += 0.5;
    tip = "Comfort ottimale! Ottimizzo i consumi.";
  }

  // FASE 3: PRUDENZA
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

  targetSlope = (targetSlope * 100).round() / 100.0;
  targetOffset = (targetOffset * 10).round() / 10.0;

  if ((targetSlope - currentSlope).abs() < 0.01 && (targetOffset - currentOffset).abs() < 0.1) {
    targetSlope = currentSlope;
    targetOffset = currentOffset;
    tip = "Parametri attuali ottimali con i nuovi dati. Mantieni cos\u00ec.";
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
