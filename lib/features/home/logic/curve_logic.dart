// lib/features/home/logic/curve_logic.dart

import 'package:fl_chart/fl_chart.dart';
import '../../../models/daily_record_dto.dart';

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
  final String smartTip;
  final bool isLearning;
  final int learningProgress;

  CurveSuggestion({
    required this.suggestedSlope,
    required this.suggestedOffset,
    required this.comfortScore,
    required this.smartTip,
    required this.isLearning,
    required this.learningProgress,
  });
}

// ---------------------------------------------------------------------------
// F3 — Analisi comfort per stanza
// ---------------------------------------------------------------------------

enum RoomComfortIssue { tooCold, tooHot, ok }

class RoomComfortStat {
  final String room;
  final int coldDays;
  final int hotDays;
  final int okDays;
  final int totalDays;

  RoomComfortStat({
    required this.room,
    required this.coldDays,
    required this.hotDays,
    required this.okDays,
    required this.totalDays,
  });

  /// Percentuale di giorni con problemi (freddo o caldo)
  double get issueRate => totalDays == 0 ? 0 : (coldDays + hotDays) / totalDays;

  /// Issue dominante della stanza
  RoomComfortIssue get dominantIssue {
    if (coldDays == 0 && hotDays == 0) return RoomComfortIssue.ok;
    return coldDays >= hotDays ? RoomComfortIssue.tooCold : RoomComfortIssue.tooHot;
  }
}

/// Analizza il comfort di ogni stanza nei [records] forniti.
///
/// Restituisce solo le stanze che hanno almeno un segnalazione di
/// disagio, ordinate per [issueRate] decrescente (peggiore prima).
/// Le stanze sempre confortevoli vengono omesse per non affollare la UI.
List<RoomComfortStat> analyzeRoomComfort(List<DailyRecordDTO> records) {
  if (records.isEmpty) return [];

  // Aggrega i conteggi per ogni stanza
  final Map<String, _RoomCounter> counters = {};

  for (final r in records) {
    for (final entry in r.comfortRatings.entries) {
      final room = entry.key;
      final rating = entry.value.toLowerCase().trim();
      counters.putIfAbsent(room, () => _RoomCounter(room));
      switch (rating) {
        case 'freddo':
          counters[room]!.cold++;
          break;
        case 'caldo':
          counters[room]!.hot++;
          break;
        default:
          counters[room]!.ok++;
      }
    }
  }

  // Converti in RoomComfortStat e filtra solo le stanze con problemi
  final result = counters.values
      .map((c) => RoomComfortStat(
            room: c.room,
            coldDays: c.cold,
            hotDays: c.hot,
            okDays: c.ok,
            totalDays: c.cold + c.hot + c.ok,
          ))
      .where((s) => s.coldDays > 0 || s.hotDays > 0)
      .toList()
    ..sort((a, b) => b.issueRate.compareTo(a.issueRate));

  return result;
}

class _RoomCounter {
  final String room;
  int cold = 0;
  int hot = 0;
  int ok = 0;
  _RoomCounter(this.room);
}

// ---------------------------------------------------------------------------

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
/// FIX #3 — Il parametro opzionale [lastAppliedDate] è stato RIMOSSO.
///
/// Motivazione: [HomeNotifier] passa già una lista pre-filtrata tramite
/// [recordsSinceLastApply], che esclude i record precedenti all'ultimo
/// apply AI. Mantenere qui un secondo filtro sullo stesso criterio era
/// ridondante e pericoloso: se per errore si passava sia la lista
/// filtrata sia lastAppliedDate, i record venivano filtrati due volte
/// e la finestra risultava vuota o troppo corta, bloccando l'AI in
/// modalità "apprendimento" anche con dati sufficienti.
///
/// Contratto attuale:
///   - [records] deve essere già filtrato per modalità (heating/cooling)
///     e per finestra temporale (dopo l'ultimo apply AI).
///   - Questa funzione NON applica nessun filtro temporale interno.
///   - Il messaggio di apprendimento usa sempre il ramo senza data,
///     più chiaro per l'utente.
CurveSuggestion computeOptimalCurveSuggestion(
    List<DailyRecordDTO> records,
    double currentSlope,
    double currentOffset,
    SystemMode mode) {
  // FASE 1: APPRENDIMENTO
  if (records.length < 5) {
    return CurveSuggestion(
      suggestedSlope: currentSlope,
      suggestedOffset: currentOffset,
      comfortScore: 0.5,
      smartTip:
          'Sto imparando come reagisce la tua casa. '
          'Continua a registrare dati per almeno ${5 - records.length} giorni.',
      isLearning: true,
      learningProgress: records.length,
    );
  }

  // FASE 2: ANALISI
  int coldComplaints = 0;
  int hotComplaints = 0;
  int okDays = 0;

  for (var r in records) {
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

  final double comfortScore = okDays / records.length;
  double targetSlope = currentSlope;
  double targetOffset = currentOffset;
  String tip;

  if (coldComplaints > hotComplaints) {
    targetOffset += 1.0;
    if (coldComplaints > records.length * 0.3) targetSlope += 0.1;
    tip = mode == SystemMode.heating
        ? 'Rilevati giorni freddi. Aumento la potenza di riscaldamento.'
        : 'Raffrescamento eccessivo. Riduco l\'intensità di raffreddamento.';
  } else if (hotComplaints > coldComplaints) {
    targetOffset -= 1.0;
    if (hotComplaints > records.length * 0.3) targetSlope -= 0.1;
    tip = mode == SystemMode.heating
        ? 'Rilevato eccesso di calore. Riduco la potenza per risparmiare.'
        : 'Raffrescamento insufficiente. Aumento la potenza di raffreddamento.';
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
    smartTip: tip,
    isLearning: false,
    learningProgress: records.length,
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

  if (effectiveMin >= effectiveMax) {
    effectiveMin = mode == SystemMode.heating ? -10.0 : 20.0;
    effectiveMax = mode == SystemMode.heating ? 20.0 : 40.0;
  }

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
