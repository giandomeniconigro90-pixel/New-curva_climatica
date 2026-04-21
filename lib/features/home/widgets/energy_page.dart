// lib/features/home/widgets/energy_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../../../utils/date_utils.dart';

// ---------------------------------------------------------------------------
// Enum periodo
// ---------------------------------------------------------------------------
enum _Period { days7, days30, months3, all }

extension _PeriodLabel on _Period {
  String get label {
    switch (this) {
      case _Period.days7:
        return '7 giorni';
      case _Period.days30:
        return '30 giorni';
      case _Period.months3:
        return '3 mesi';
      case _Period.all:
        return 'Tutto';
    }
  }
}

// ---------------------------------------------------------------------------
// Modello barra aggregata
// ---------------------------------------------------------------------------
class _BarEntry {
  final String label;
  final double consumption;
  final double consumptionACS;
  final double energyFromGrid;
  final double pvProduction;

  const _BarEntry({
    required this.label,
    required this.consumption,
    required this.consumptionACS,
    required this.energyFromGrid,
    required this.pvProduction,
  });
}

// ---------------------------------------------------------------------------
// Widget principale
// ---------------------------------------------------------------------------
class EnergyPage extends StatefulWidget {
  final List<DailyRecordDTO> records;

  const EnergyPage({super.key, required this.records});

  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends State<EnergyPage> {
  _Period _period = _Period.days30;
  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final price = AppStorage.getCostPerKwh();
    _priceController.text = price.toStringAsFixed(4);
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  // ---- Filtra e ordina record per periodo selezionato ----
  List<DailyRecordDTO> get _filteredRecords {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    List<DailyRecordDTO> sorted = List.from(widget.records)
      ..sort((a, b) {
        final dA = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
        final dB = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
        return dA.compareTo(dB);
      });

    if (_period == _Period.all) return sorted;

    final cutoff = _period == _Period.days7
        ? today.subtract(const Duration(days: 6))
        : _period == _Period.days30
            ? today.subtract(const Duration(days: 29))
            : today.subtract(const Duration(days: 89));

    return sorted.where((r) {
      final d = parseItalianDateSafe(r.dateIso);
      return d != null && !d.isBefore(cutoff);
    }).toList();
  }

  // ---- Aggregazione: giornaliera o mensile ----
  bool get _useMonthly => _period == _Period.all || _period == _Period.months3;

  List<_BarEntry> get _entries {
    final filtered = _filteredRecords;
    if (!_useMonthly) {
      return filtered.map((r) {
        final d = parseItalianDateSafe(r.dateIso);
        final label = d != null
            ? '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}'
            : r.dateIso;
        return _BarEntry(
          label: label,
          consumption: r.consumption,
          consumptionACS: r.consumptionACS ?? 0,
          energyFromGrid: r.energyFromGrid ?? 0,
          pvProduction: r.pvProduction ?? 0,
        );
      }).toList();
    }

    // Aggregazione mensile
    final Map<String, _MutableBarEntry> monthly = {};
    for (final r in filtered) {
      final d = parseItalianDateSafe(r.dateIso);
      if (d == null) continue;
      final key =
          '${d.month.toString().padLeft(2, '0')}/${d.year.toString().substring(2)}';
      monthly.putIfAbsent(key, () => _MutableBarEntry(key));
      monthly[key]!.consumption += r.consumption;
      monthly[key]!.consumptionACS += r.consumptionACS ?? 0;
      monthly[key]!.energyFromGrid += r.energyFromGrid ?? 0;
      monthly[key]!.pvProduction += r.pvProduction ?? 0;
    }
    return monthly.values
        .map((e) => _BarEntry(
              label: e.label,
              consumption: e.consumption,
              consumptionACS: e.consumptionACS,
              energyFromGrid: e.energyFromGrid,
              pvProduction: e.pvProduction,
            ))
        .toList();
  }

  // ---- KPI aggregati ----
  double get _totalConsumption =>
      _filteredRecords.fold(0, (s, r) => s + r.consumption);
  double get _totalACS =>
      _filteredRecords.fold(0, (s, r) => s + (r.consumptionACS ?? 0));
  double get _totalGrid =>
      _filteredRecords.fold(0, (s, r) => s + (r.energyFromGrid ?? 0));
  double get _totalPv =>
      _filteredRecords.fold(0, (s, r) => s + (r.pvProduction ?? 0));

  double get _costPerKwh =>
      double.tryParse(_priceController.text.replaceAll(',', '.')) ??
      AppStorage.getCostPerKwh();

  double get _estimatedCost => _totalGrid * _costPerKwh;

  double get _selfConsumptionPct {
    if (_totalPv <= 0) return 0;
    final selfConsumed = (_totalPv - (_totalGrid > _totalPv
            ? 0
            : _totalPv - (_totalConsumption + _totalACS - _totalGrid)
                .clamp(0, _totalPv)))
        .clamp(0, _totalPv);
    return (selfConsumed / _totalPv * 100).clamp(0, 100);
  }

  // ---- Colori serie ----
  static const Color _colConsumption = Color(0xFFFF7043);
  static const Color _colACS = Color(0xFFFFB300);
  static const Color _colGrid = Color(0xFF42A5F5);
  static const Color _colPv = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = _entries;
    final hasData = entries.isNotEmpty;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Titolo + prezzo kWh ----
            Row(
              children: [
                Icon(Icons.bolt_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 6),
                Text(
                  'Energia & Costi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: '€/kWh',
                      labelStyle: const TextStyle(fontSize: 12),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onEditingComplete: () async {
                      final v = double.tryParse(
                          _priceController.text.replaceAll(',', '.'));
                      if (v != null && v > 0) {
                        await AppStorage.saveCostPerKwh(v);
                      }
                      FocusScope.of(context).unfocus();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ---- Filtri periodo ----
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _Period.values.map((p) {
                  final sel = p == _period;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(p.label,
                          style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (_) => setState(() => _period = p),
                      selectedColor: cs.primary,
                      labelStyle: TextStyle(
                          color: sel ? cs.onPrimary : cs.onSurfaceVariant),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // ---- KPI cards ----
            _KpiRow(
              totalConsumption: _totalConsumption,
              totalPv: _totalPv,
              estimatedCost: _estimatedCost,
              selfPct: _selfConsumptionPct,
            ),
            const SizedBox(height: 16),

            // ---- Legenda ----
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: const [
                _LegendDot(color: _colConsumption, label: 'PdC (kWh)'),
                _LegendDot(color: _colACS, label: 'ACS (kWh)'),
                _LegendDot(color: _colGrid, label: 'Rete (kWh)'),
                _LegendDot(color: _colPv, label: 'FV (kWh)'),
              ],
            ),
            const SizedBox(height: 10),

            // ---- Grafico ----
            if (!hasData)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.bar_chart_outlined,
                          size: 48, color: cs.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text(
                        'Nessun dato nel periodo selezionato',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              _EnergyBarChart(entries: entries),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grafico a barre raggruppate
// ---------------------------------------------------------------------------
class _EnergyBarChart extends StatelessWidget {
  final List<_BarEntry> entries;

  const _EnergyBarChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = entries.length;
    final barWidth = count > 20 ? 4.0 : count > 10 ? 6.0 : 8.0;
    final groupWidth = count > 20 ? 22.0 : count > 10 ? 30.0 : 38.0;
    final chartWidth = (count * groupWidth).clamp(300.0, double.infinity);

    double maxY = 0;
    for (final e in entries) {
      final m = [e.consumption, e.consumptionACS, e.energyFromGrid, e.pvProduction]
          .fold(0.0, (a, b) => a > b ? a : b);
      if (m > maxY) maxY = m;
    }
    maxY = ((maxY * 1.2) / 5).ceil() * 5.0;
    if (maxY < 5) maxY = 5;

    final groups = entries.asMap().entries.map((e) {
      final i = e.key;
      final entry = e.value;
      return BarChartGroupData(
        x: i,
        groupVertically: false,
        barRods: [
          _rod(entry.consumption, _EnergyPage._colConsumption, barWidth),
          _rod(entry.consumptionACS, _EnergyPage._colACS, barWidth),
          _rod(entry.energyFromGrid, _EnergyPage._colGrid, barWidth),
          _rod(entry.pvProduction, _EnergyPage._colPv, barWidth),
        ],
        barsSpace: 2,
      );
    }).toList();

    return SizedBox(
      height: 220,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              barGroups: groups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: cs.outlineVariant.withOpacity(0.4),
                  strokeWidth: 0.8,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: maxY / 4,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= entries.length) {
                        return const SizedBox.shrink();
                      }
                      // Mostra etichetta solo ogni N per non sovrapporre
                      final step = count > 20 ? 5 : count > 10 ? 3 : 1;
                      if (idx % step != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          entries[idx].label,
                          style: TextStyle(
                              fontSize: 9, color: cs.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => cs.surfaceContainerHighest,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final labels = ['PdC', 'ACS', 'Rete', 'FV'];
                    final label = labels[rodIndex];
                    return BarTooltipItem(
                      '$label\n${rod.toY.toStringAsFixed(1)} kWh',
                      TextStyle(color: cs.onSurface, fontSize: 11),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  BarChartRodData _rod(double y, Color color, double width) {
    return BarChartRodData(
      toY: y,
      color: color,
      width: width,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI Row
// ---------------------------------------------------------------------------
class _KpiRow extends StatelessWidget {
  final double totalConsumption;
  final double totalPv;
  final double estimatedCost;
  final double selfPct;

  const _KpiRow({
    required this.totalConsumption,
    required this.totalPv,
    required this.estimatedCost,
    required this.selfPct,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _KpiCard(
          icon: Icons.bolt_rounded,
          color: _EnergyPage._colConsumption,
          label: 'Consumo PdC',
          value: '${totalConsumption.toStringAsFixed(1)} kWh',
        )),
        const SizedBox(width: 6),
        Expanded(
            child: _KpiCard(
          icon: Icons.solar_power_rounded,
          color: _EnergyPage._colPv,
          label: 'Fotovoltaico',
          value: '${totalPv.toStringAsFixed(1)} kWh',
        )),
        const SizedBox(width: 6),
        Expanded(
            child: _KpiCard(
          icon: Icons.euro_rounded,
          color: const Color(0xFF26C6DA),
          label: 'Costo stimato',
          value: '€ ${estimatedCost.toStringAsFixed(2)}',
        )),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _KpiCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Legenda dot
// ---------------------------------------------------------------------------
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helper mutabile per aggregazione mensile
// ---------------------------------------------------------------------------
class _MutableBarEntry {
  final String label;
  double consumption = 0;
  double consumptionACS = 0;
  double energyFromGrid = 0;
  double pvProduction = 0;

  _MutableBarEntry(this.label);
}
