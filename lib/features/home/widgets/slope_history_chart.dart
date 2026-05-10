// lib/features/home/widgets/slope_history_chart.dart
//
// Grafico a linee che mostra l'evoluzione di Slope e Offset nel tempo.
// I punti sono ricavati dai DailyRecordDTO: per ogni giornata si calcola
// la curva "teorica" attesa (temp. mandata @ 0°C esterna) usando slope/offset
// attivi in quel momento. In assenza di uno storico applicazioni AI granulare,
// usiamo i valori correnti come riferimento e mostriamo l'andamento della
// temperatura esterna registrata vs consumo come proxy della curva.
//
// Approccio scelto: grafico "Slope & Offset nel tempo" con 2 serie,
// dove ogni punto X = indice record (dal più vecchio al più recente)
// e Y = valore slope o offset di quel giorno calcolato da externalTemp
// e consumo tramite regressione locale.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../models/daily_record_dto.dart';
import '../../../utils/date_utils.dart';
import '../logic/curve_logic.dart';

class SlopeHistoryChart extends StatelessWidget {
  final List<DailyRecordDTO> allRecords;
  final double currentSlope;
  final double currentOffset;
  final SystemMode mode;

  const SlopeHistoryChart({
    super.key,
    required this.allRecords,
    required this.currentSlope,
    required this.currentOffset,
    required this.mode,
  });

  /// Costruisce finestre scorrevoli di 5 record e per ognuna calcola
  /// la suggestion AI: ogni punto del grafico = slope/offset "ottimale"
  /// suggerito da quella finestra, mostrando come è evoluta la curva.
  List<_HistoryPoint> _buildHistory() {
    final modeStr = mode == SystemMode.heating ? 'heating' : 'cooling';
    final sorted = allRecords
        .where((r) => r.mode == modeStr)
        .toList()
      ..sort((a, b) {
        final da = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
        final db = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
        return da.compareTo(db);
      });

    if (sorted.length < 3) return [];

    final points = <_HistoryPoint>[];
    const windowSize = 5;
    final effectiveWindow = sorted.length < windowSize ? sorted.length : windowSize;

    for (int i = effectiveWindow - 1; i < sorted.length; i++) {
      final window = sorted.sublist(
        (i - effectiveWindow + 1).clamp(0, sorted.length),
        i + 1,
      );
      // Stima slope/offset usando la finestra: regressione lineare
      // tra externalTemp e consumo come proxy della risposta termica
      final s = _estimateSlope(window);
      final o = _estimateOffset(window, s);
      final date = parseItalianDateSafe(sorted[i].dateIso) ?? DateTime(2000);
      points.add(_HistoryPoint(date: date, slope: s, offset: o));
    }
    return points;
  }

  /// Stima slope: regressione lineare externalTemp → consumo (normalizzato)
  /// Più la temperatura esterna scende, più il consumo sale: il coefficiente
  /// angolare (negativo) scalato approssima la pendenza della curva climatica.
  double _estimateSlope(List<DailyRecordDTO> window) {
    if (window.length < 2) return currentSlope;
    final n = window.length.toDouble();
    final sumX = window.fold(0.0, (s, r) => s + r.externalTemp);
    final sumY = window.fold(0.0, (s, r) => s + r.consumption);
    final sumXY = window.fold(0.0, (s, r) => s + r.externalTemp * r.consumption);
    final sumX2 = window.fold(0.0, (s, r) => s + r.externalTemp * r.externalTemp);
    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-9) return currentSlope;
    final rawSlope = (n * sumXY - sumX * sumY) / denom;
    // Normalizziamo: slope curva climatica è tipicamente 0.3-2.5
    // rawSlope consumo/°C è negativo (più freddo = più consumi)
    // Mappa -rawSlope nell'intervallo [0.3, 2.5]
    final mapped = (-rawSlope).clamp(0.3, 2.5);
    return double.parse(mapped.toStringAsFixed(2));
  }

  /// Stima offset: valore medio di (consumo - slope * externalTemp)
  double _estimateOffset(List<DailyRecordDTO> window, double slope) {
    if (window.isEmpty) return currentOffset;
    final avg = window.fold(0.0, (s, r) => s + (r.consumption - slope * r.externalTemp)) / window.length;
    return double.parse(avg.clamp(-5.0, 5.0).toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final history = _buildHistory();

    if (history.length < 2) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.show_chart, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Storico curva disponibile dopo almeno 3 registrazioni.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final slopeSpots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.slope))
        .toList();
    final offsetSpots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.offset))
        .toList();

    final allSlopes = history.map((h) => h.slope).toList();
    final allOffsets = history.map((h) => h.offset).toList();
    final minY = ([...allSlopes, ...allOffsets].reduce((a, b) => a < b ? a : b) - 0.3).clamp(-5.5, 5.0);
    final maxY = ([...allSlopes, ...allOffsets].reduce((a, b) => a > b ? a : b) + 0.3).clamp(0.3, 3.0);

    final labelColor = cs.onSurfaceVariant;
    final gridColor = cs.outlineVariant.withValues(alpha: 0.4);

    // Etichette asse X: mostra data solo ogni N punti per non affollare
    final labelStep = (history.length / 5).ceil().clamp(1, 99);

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evoluzione Curva nel Tempo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    'Slope e Offset stimati per finestra mobile (5 gg)',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              // Valori correnti
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Chip(label: 'S: ${currentSlope.toStringAsFixed(2)}', color: cs.primary),
                  const SizedBox(height: 4),
                  _Chip(label: 'O: ${currentOffset.toStringAsFixed(2)}', color: Colors.teal),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1.7,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (history.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                clipData: const FlClipData.all(),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    getTooltipItems: (spots) {
                      return spots.map((s) {
                        final idx = s.x.toInt().clamp(0, history.length - 1);
                        final d = history[idx].date;
                        final label = s.barIndex == 0 ? 'Slope' : 'Offset';
                        return LineTooltipItem(
                          '${d.day}/${d.month}\n$label: ${s.y.toStringAsFixed(2)}',
                          TextStyle(
                            color: cs.onInverseSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 0.5,
                  getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1),
                  getDrawingVerticalLine: (_) => FlLine(color: gridColor, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 0.5,
                      getTitlesWidget: (val, _) => Text(
                        val.toStringAsFixed(1),
                        style: TextStyle(fontSize: 10, color: labelColor),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                        if (idx % labelStep != 0) return const SizedBox.shrink();
                        final d = history[idx].date;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${d.day}/${d.month}',
                            style: TextStyle(fontSize: 9, color: labelColor),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: cs.outlineVariant),
                ),
                lineBarsData: [
                  // Slope
                  LineChartBarData(
                    spots: slopeSpots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: cs.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 3,
                        color: cs.primary,
                        strokeWidth: 0,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: cs.primary.withValues(alpha: 0.06),
                    ),
                  ),
                  // Offset
                  LineChartBarData(
                    spots: offsetSpots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: Colors.teal,
                    barWidth: 2,
                    dashArray: const [5, 4],
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 3,
                        color: Colors.teal,
                        strokeWidth: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legenda
          Row(
            children: [
              _LegendDot(color: cs.primary, label: 'Slope'),
              const SizedBox(width: 20),
              _LegendDash(color: Colors.teal, label: 'Offset'),
              const Spacer(),
              Text(
                '${history.length} finestre',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryPoint {
  final DateTime date;
  final double slope;
  final double offset;
  const _HistoryPoint({required this.date, required this.slope, required this.offset});
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _LegendDash extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDash({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Row(children: [
          Container(width: 5, height: 3, color: color),
          const SizedBox(width: 2),
          Container(width: 5, height: 3, color: color),
        ]),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
