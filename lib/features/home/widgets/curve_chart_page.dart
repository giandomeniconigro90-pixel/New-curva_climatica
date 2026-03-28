// lib/features/home/widgets/curve_chart_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../models/daily_record_dto.dart';
import '../logic/curve_logic.dart';

class CurveChartPage extends StatelessWidget {
  final double slope;
  final double offset;
  final SystemMode mode;
  final List<DailyRecordDTO> windowRecords;
  final GlobalKey chartKey;

  const CurveChartPage({
    super.key,
    required this.slope,
    required this.offset,
    required this.mode,
    required this.windowRecords,
    required this.chartKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suggestion =
        computeOptimalCurveSuggestion(windowRecords, slope, offset, mode);

    final isHeating = mode == SystemMode.heating;
    final double minExt = isHeating ? -10 : 20;
    final double maxExt = isHeating ? 20 : 40;
    final double minY = isHeating ? 25.0 : 5.0;
    final double maxY = isHeating ? 65.0 : 25.0;
    final double unsafeZoneLimit = isHeating ? 35.0 : 15.0;

    final List<FlSpot> currentSpots = buildCurveSpots(
      slope: slope,
      offset: offset,
      mode: mode,
      minExternalTemp: minExt,
      maxExternalTemp: maxExt,
      step: 1,
    );

    List<FlSpot>? suggestedSpots;
    if (!suggestion.isLearning) {
      suggestedSpots = buildCurveSpots(
        slope: suggestion.suggestedSlope,
        offset: suggestion.suggestedOffset,
        mode: mode,
        minExternalTemp: minExt,
        maxExternalTemp: maxExt,
        step: 1,
      );
    }

    final gridColor = cs.outlineVariant.withOpacity(0.4);
    final labelColor = cs.onSurfaceVariant;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              const SizedBox(height: 16),
              RepaintBoundary(
                key: chartKey,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Curva Climatica',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                isHeating
                                    ? 'Inverno (Riscaldamento)'
                                    : 'Estate (Raffrescamento)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _buildLegendItem(
                                  'Attuale', cs.primary, false, cs),
                              if (suggestedSpots != null) ...[
                                const SizedBox(width: 16),
                                _buildLegendItem(
                                    'AI Consigliata', Colors.green, true, cs),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AspectRatio(
                        aspectRatio: 1.4,
                        child: LineChart(
                          LineChartData(
                            minX: minExt,
                            maxX: maxExt,
                            minY: minY,
                            maxY: maxY,
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) => cs.inverseSurface,
                                getTooltipItems: (spots) => spots
                                    .map((s) => LineTooltipItem(
                                          'Est ${s.x.toInt()}°C: ${s.y.toStringAsFixed(1)}°C',
                                          TextStyle(
                                            color: cs.onInverseSurface,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                            rangeAnnotations: RangeAnnotations(
                              horizontalRangeAnnotations: [
                                HorizontalRangeAnnotation(
                                  y1: minY,
                                  y2: unsafeZoneLimit,
                                  color: Colors.red.withOpacity(0.10),
                                ),
                              ],
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              horizontalInterval: 5,
                              verticalInterval: 5,
                              getDrawingHorizontalLine: (_) =>
                                  FlLine(color: gridColor, strokeWidth: 1),
                              getDrawingVerticalLine: (_) =>
                                  FlLine(color: gridColor, strokeWidth: 1),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                axisNameWidget: Text(
                                  'Temp. Mandata Acqua °C',
                                  style: TextStyle(
                                      fontSize: 10, color: labelColor),
                                ),
                                axisNameSize: 20,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 35,
                                  interval: 5,
                                  getTitlesWidget: (val, m) => Text(
                                    val.toInt().toString(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: labelColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                axisNameWidget: Text(
                                  'Temp. Esterna °C',
                                  style: TextStyle(
                                      fontSize: 10, color: labelColor),
                                ),
                                axisNameSize: 20,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 5,
                                  getTitlesWidget: (val, m) => Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      val.toInt().toString(),
                                      style: TextStyle(
                                          fontSize: 11, color: labelColor),
                                    ),
                                  ),
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border:
                                  Border.all(color: cs.outlineVariant),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: currentSpots,
                                isCurved: true,
                                color: cs.primary,
                                barWidth: 4,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: cs.primary.withOpacity(0.05),
                                ),
                              ),
                              if (suggestedSpots != null)
                                LineChartBarData(
                                  spots: suggestedSpots,
                                  isCurved: true,
                                  color: Colors.green,
                                  barWidth: 3,
                                  dashArray: const [6, 6],
                                  dotData: const FlDotData(show: false),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                              width: 12,
                              height: 12,
                              color: Colors.red.withOpacity(0.1)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isHeating
                                  ? 'Zona Rossa (>35°C): Efficienza ridotta per Ventilconvettori.'
                                  : 'Zona Rossa (<15°C): Alto rischio condensa.',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(
      String text, Color color, bool isDashed, ColorScheme cs) {
    return Row(
      children: [
        if (isDashed)
          Row(children: [
            Container(width: 6, height: 3, color: color),
            const SizedBox(width: 2),
            Container(width: 6, height: 3, color: color),
          ])
        else
          Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
