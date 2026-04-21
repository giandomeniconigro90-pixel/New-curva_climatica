// lib/features/home/widgets/energy_page.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../../../utils/date_utils.dart';

class EnergyPage extends StatefulWidget {
  final List<DailyRecordDTO> records;
  const EnergyPage({super.key, required this.records});

  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends State<EnergyPage> {
  late double _costPerKwh;
  final TextEditingController _priceController = TextEditingController();

  static const Color _colGrid = Color(0xFFFFB74D);
  static const Color _colPv   = Color(0xFF66BB6A);
  static const Color _colPdc  = Color(0xFF4DB6AC);

  @override
  void initState() {
    super.initState();
    _costPerKwh = AppStorage.getCostPerKwh();
    _priceController.text = _costPerKwh.toStringAsFixed(4);
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  List<DailyRecordDTO> get _energyRecords {
    final sorted = widget.records
        .where((r) =>
            r.energyFromGrid != null ||
            r.pvProduction != null ||
            r.consumption != null)
        .toList()
      ..sort((a, b) {
        final da = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
        final db = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
        return da.compareTo(db);
      });
    return sorted.length > 14 ? sorted.sublist(sorted.length - 14) : sorted;
  }

  double get _totalGrid => _energyRecords.fold(0.0, (s, r) => s + (r.energyFromGrid ?? 0.0));
  double get _totalPv   => _energyRecords.fold(0.0, (s, r) => s + (r.pvProduction ?? 0.0));
  double get _totalPdc  => _energyRecords.fold(0.0, (s, r) => s + r.consumption);
  double get _totalCost => _totalGrid * _costPerKwh;
  double get _savedCost => _totalPv * _costPerKwh;

  Future<void> _editPrice() async {
    _priceController.text = _costPerKwh.toStringAsFixed(4);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.bolt, color: _colGrid, size: 20),
            const SizedBox(width: 8),
            const Text('Prezzo energia'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'A2A Click Luce – Monoraria\nTutte le componenti variabili + IVA 10%',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: InputDecoration(
                labelText: 'Prezzo (€/kWh)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixText: '€/kWh',
                prefixIcon: const Icon(Icons.euro_outlined, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Salva'),
            onPressed: () async {
              final v = double.tryParse(_priceController.text.replaceAll(',', '.'));
              if (v != null && v > 0) {
                await AppStorage.saveCostPerKwh(v);
                if (mounted) setState(() => _costPerKwh = v);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final records = _energyRecords;

    if (records.isEmpty) return _buildEmpty(cs);

    return CustomScrollView(
      slivers: [
        // ── Header ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _colGrid.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt, color: _colGrid, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'Energia & Costi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                // chip prezzo
                GestureDetector(
                  onTap: _editPrice,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.primary.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, size: 12, color: cs.primary),
                        const SizedBox(width: 5),
                        Text(
                          '${_costPerKwh.toStringAsFixed(4)} €/kWh',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── KPI Cards ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                _KpiCard(
                  label: 'Rete',
                  value: _totalGrid.toStringAsFixed(1),
                  unit: 'kWh',
                  sub: '${_totalCost.toStringAsFixed(2)} €',
                  icon: Icons.electrical_services_outlined,
                  accentColor: _colGrid,
                ),
                const SizedBox(width: 8),
                _KpiCard(
                  label: 'Fotovoltaico',
                  value: _totalPv.toStringAsFixed(1),
                  unit: 'kWh',
                  sub: '↓ ${_savedCost.toStringAsFixed(2)} €',
                  icon: Icons.wb_sunny_outlined,
                  accentColor: _colPv,
                ),
                const SizedBox(width: 8),
                _KpiCard(
                  label: 'PDC',
                  value: _totalPdc.toStringAsFixed(1),
                  unit: 'kWh',
                  sub: '${(_totalPdc * _costPerKwh).toStringAsFixed(2)} €',
                  icon: Icons.heat_pump_outlined,
                  accentColor: _colPdc,
                ),
              ],
            ),
          ),
        ),

        // ── Grafico barre ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _ChartCard(
              title: 'Energia giornaliera',
              unit: 'kWh',
              icon: Icons.bar_chart_rounded,
              legend: const [
                _LegendDot(color: _colGrid, label: 'Rete'),
                _LegendDot(color: _colPv,   label: 'FV'),
                _LegendDot(color: _colPdc,  label: 'PDC'),
              ],
              child: _buildBarChart(records, cs),
            ),
          ),
        ),

        // ── Grafico costi ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _ChartCard(
              title: 'Costi giornalieri',
              unit: '€',
              icon: Icons.show_chart_rounded,
              legend: const [
                _LegendDot(color: _colGrid, label: 'Costo rete'),
                _LegendDot(color: _colPv,   label: 'Risparmio FV'),
              ],
              child: _buildCostChart(records, cs),
            ),
          ),
        ),

        // ── Tabella ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            child: _buildTable(records, cs),
          ),
        ),
      ],
    );
  }

  // ── Grafico a barre ──────────────────────────────────────────────────────
  Widget _buildBarChart(List<DailyRecordDTO> records, ColorScheme cs) {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      groups.add(BarChartGroupData(
        x: i,
        barsSpace: 2,
        barRods: [
          BarChartRodData(toY: r.energyFromGrid ?? 0.0, color: _colGrid, width: 6,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
          BarChartRodData(toY: r.pvProduction ?? 0.0,   color: _colPv,   width: 6,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
          BarChartRodData(toY: r.consumption,           color: _colPdc,  width: 6,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        ],
      ));
    }
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        barGroups: groups,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: cs.outlineVariant.withOpacity(0.25), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= records.length) return const SizedBox.shrink();
                final parts = records[idx].dateIso.split('/');
                final label = parts.length >= 2 ? '${parts[0]}/${parts[1]}' : records[idx].dateIso;
                return Transform.rotate(
                  angle: -0.5,
                  child: Text(label, style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant)),
                );
              },
            ),
          ),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, rodIndex) {
              final labels = ['Rete', 'FV', 'PDC'];
              return BarTooltipItem(
                '${labels[rodIndex]}: ${rod.toY.toStringAsFixed(1)} kWh',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
      )),
    );
  }

  // ── Grafico costi ────────────────────────────────────────────────────────
  Widget _buildCostChart(List<DailyRecordDTO> records, ColorScheme cs) {
    final gridSpots = <FlSpot>[];
    final pvSpots   = <FlSpot>[];
    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      gridSpots.add(FlSpot(i.toDouble(), (r.energyFromGrid ?? 0.0) * _costPerKwh));
      pvSpots.add(FlSpot(i.toDouble(), (r.pvProduction ?? 0.0) * _costPerKwh));
    }
    return SizedBox(
      height: 180,
      child: LineChart(LineChartData(
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: cs.outlineVariant.withOpacity(0.25), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(2)}€',
                  style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= records.length || idx % 2 != 0) return const SizedBox.shrink();
                final parts = records[idx].dateIso.split('/');
                final label = parts.length >= 2 ? '${parts[0]}/${parts[1]}' : records[idx].dateIso;
                return Transform.rotate(
                  angle: -0.5,
                  child: Text(label, style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant)),
                );
              },
            ),
          ),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: gridSpots,
            isCurved: true,
            color: _colGrid,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: _colGrid.withOpacity(0.08)),
          ),
          LineChartBarData(
            spots: pvSpots,
            isCurved: true,
            color: _colPv,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: _colPv.withOpacity(0.08)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(3)} €',
                      const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
        ),
      )),
    );
  }

  // ── Tabella ──────────────────────────────────────────────────────────────
  Widget _buildTable(List<DailyRecordDTO> records, ColorScheme cs) {
    final rows = records.reversed.toList();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header sezione
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Icon(Icons.table_rows_outlined, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Dettaglio giornaliero',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // intestazioni colonne
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.6),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
            ),
            child: Row(
              children: [
                _TH('Data', flex: 2),
                _TH('Rete', color: _colGrid),
                _TH('FV',   color: _colPv),
                _TH('PDC',  color: _colPdc),
                _TH('€ Costo'),
              ],
            ),
          ),
          // righe zebra
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final r = entry.value;
            final cost = (r.energyFromGrid ?? 0.0) * _costPerKwh;
            final isEven = i % 2 == 0;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isEven
                    ? Colors.transparent
                    : cs.surfaceContainerHighest.withOpacity(0.2),
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withOpacity(0.15),
                  ),
                ),
                borderRadius: i == rows.length - 1
                    ? const BorderRadius.vertical(bottom: Radius.circular(14))
                    : BorderRadius.zero,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      r.dateIso,
                      style: TextStyle(fontSize: 11, color: cs.onSurface, fontWeight: FontWeight.w500),
                    ),
                  ),
                  _TD(r.energyFromGrid?.toStringAsFixed(1) ?? '–', color: _colGrid),
                  _TD(r.pvProduction?.toStringAsFixed(1)   ?? '–', color: _colPv),
                  _TD(r.consumption.toStringAsFixed(1),              color: _colPdc),
                  _TD(cost.toStringAsFixed(3),                       color: cs.onSurface),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────
  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _colGrid.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt_outlined, size: 40, color: _colGrid),
            ),
            const SizedBox(height: 20),
            Text(
              'Nessun dato energia',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Vai nella scheda "Registra" e inserisci\nkWh rete (ShinePhone) e FV (ShinePhone)\nper vedere grafici e costi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Card wrapper per i grafici ──────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final String unit;
  final IconData icon;
  final List<Widget> legend;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.unit,
    required this.icon,
    required this.legend,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  unit,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 14, children: legend),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ─── KPI Card ────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String sub;
  final IconData icon;
  final Color accentColor;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // barra colorata in cima
              Container(height: 4, color: accentColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(icon, size: 12, color: accentColor),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: value,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: ' $unit',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 10,
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  final int flex;
  final Color? color;
  const _TH(this.text, {this.flex = 1, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color ?? cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TD extends StatelessWidget {
  final String text;
  final Color color;
  const _TD(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
