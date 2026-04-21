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

  // indice barra toccata per tooltip
  int _touchedIndex = -1;

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

  // ── record con almeno uno dei campi energia valorizzato ──
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
    // ultimi 14 giorni per leggibilità
    return sorted.length > 14 ? sorted.sublist(sorted.length - 14) : sorted;
  }

  // ── KPI aggregati ──
  double get _totalGrid => _energyRecords.fold(
      0.0, (s, r) => s + (r.energyFromGrid ?? 0.0));
  double get _totalPv =>
      _energyRecords.fold(0.0, (s, r) => s + (r.pvProduction ?? 0.0));
  double get _totalConsumption =>
      _energyRecords.fold(0.0, (s, r) => s + r.consumption);
  double get _totalCost => _totalGrid * _costPerKwh;
  double get _savedCost => _totalPv * _costPerKwh;

  Future<void> _editPrice() async {
    _priceController.text = _costPerKwh.toStringAsFixed(4);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prezzo €/kWh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Offerta A2A Click Luce – Monoraria\n'
              'Tutte le componenti variabili IVA incl.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Prezzo (€/kWh)',
                border: OutlineInputBorder(),
                suffixText: '€/kWh',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              final v = double.tryParse(
                  _priceController.text.replaceAll(',', '.'));
              if (v != null && v > 0) {
                await AppStorage.saveCostPerKwh(v);
                if (mounted) setState(() => _costPerKwh = v);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final records = _energyRecords;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: records.isEmpty
          ? _buildEmpty(cs)
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Text(
                          'Energia & Costi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        const Spacer(),
                        // pulsante modifica prezzo
                        InkWell(
                          onTap: _editPrice,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined,
                                    size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '${_costPerKwh.toStringAsFixed(4)} €/kWh',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── KPI cards ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        _KpiCard(
                          label: 'Rete',
                          value: '${_totalGrid.toStringAsFixed(1)} kWh',
                          sub: '${_totalCost.toStringAsFixed(2)} €',
                          icon: Icons.electrical_services_outlined,
                          color: const Color(0xFFFFB74D),
                        ),
                        const SizedBox(width: 8),
                        _KpiCard(
                          label: 'Fotovoltaico',
                          value: '${_totalPv.toStringAsFixed(1)} kWh',
                          sub: '${_savedCost.toStringAsFixed(2)} € risparmiati',
                          icon: Icons.wb_sunny_outlined,
                          color: const Color(0xFF81C784),
                        ),
                        const SizedBox(width: 8),
                        _KpiCard(
                          label: 'Consumo PDC',
                          value:
                              '${_totalConsumption.toStringAsFixed(1)} kWh',
                          sub:
                              '${(_totalConsumption * _costPerKwh).toStringAsFixed(2)} €',
                          icon: Icons.heat_pump_outlined,
                          color: const Color(0xFF4DB6AC),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Grafico a barre raggruppate ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: _buildBarChart(records, cs),
                  ),
                ),
                // ── Grafico costi ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: _buildCostChart(records, cs),
                  ),
                ),
                // ── Tabella dettaglio ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    child: _buildTable(records, cs),
                  ),
                ),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────
  // Grafico a barre: rete / FV / consumo PDC
  // ─────────────────────────────────────────
  Widget _buildBarChart(
      List<DailyRecordDTO> records, ColorScheme cs) {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      groups.add(BarChartGroupData(
        x: i,
        barsSpace: 2,
        barRods: [
          BarChartRodData(
            toY: r.energyFromGrid ?? 0.0,
            color: const Color(0xFFFFB74D),
            width: 6,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3)),
          ),
          BarChartRodData(
            toY: r.pvProduction ?? 0.0,
            color: const Color(0xFF81C784),
            width: 6,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3)),
          ),
          BarChartRodData(
            toY: r.consumption,
            color: const Color(0xFF4DB6AC),
            width: 6,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3)),
          ),
        ],
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              'Energia giornaliera (kWh)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
            ),
          ),
          // legenda
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Wrap(
              spacing: 16,
              children: [
                _LegendDot(
                    color: const Color(0xFFFFB74D), label: 'Rete'),
                _LegendDot(
                    color: const Color(0xFF81C784), label: 'FV'),
                _LegendDot(
                    color: const Color(0xFF4DB6AC), label: 'PDC'),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                barGroups: groups,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: cs.outlineVariant.withOpacity(0.3),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= records.length) {
                          return const SizedBox.shrink();
                        }
                        final dateStr = records[idx].dateIso;
                        // mostra solo giorno/mese
                        final parts = dateStr.split('/');
                        final label = parts.length >= 2
                            ? '${parts[0]}/${parts[1]}'
                            : dateStr;
                        return Transform.rotate(
                          angle: -0.5,
                          child: Text(
                            label,
                            style: TextStyle(
                                fontSize: 9,
                                color: cs.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final labels = ['Rete', 'FV', 'PDC'];
                      return BarTooltipItem(
                        '${labels[rodIndex]}: ${rod.toY.toStringAsFixed(1)} kWh',
                        const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // Grafico costi (linea)
  // ─────────────────────────────────────────
  Widget _buildCostChart(
      List<DailyRecordDTO> records, ColorScheme cs) {
    final gridSpots = <FlSpot>[];
    final pvSpots = <FlSpot>[];

    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      gridSpots.add(FlSpot(
          i.toDouble(), (r.energyFromGrid ?? 0.0) * _costPerKwh));
      pvSpots.add(
          FlSpot(i.toDouble(), (r.pvProduction ?? 0.0) * _costPerKwh));
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              'Costi giornalieri (€)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Wrap(
              spacing: 16,
              children: [
                _LegendDot(
                    color: const Color(0xFFFFB74D),
                    label: 'Costo rete'),
                _LegendDot(
                    color: const Color(0xFF81C784),
                    label: 'Risparmio FV'),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: cs.outlineVariant.withOpacity(0.3),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toStringAsFixed(2)}€',
                        style: TextStyle(
                            fontSize: 9,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 ||
                            idx >= records.length ||
                            idx % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        final parts =
                            records[idx].dateIso.split('/');
                        final label = parts.length >= 2
                            ? '${parts[0]}/${parts[1]}'
                            : records[idx].dateIso;
                        return Transform.rotate(
                          angle: -0.5,
                          child: Text(
                            label,
                            style: TextStyle(
                                fontSize: 9,
                                color: cs.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: gridSpots,
                    isCurved: true,
                    color: const Color(0xFFFFB74D),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color:
                          const Color(0xFFFFB74D).withOpacity(0.1),
                    ),
                  ),
                  LineChartBarData(
                    spots: pvSpots,
                    isCurved: true,
                    color: const Color(0xFF81C784),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color:
                          const Color(0xFF81C784).withOpacity(0.1),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(3)} €',
                              const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // Tabella dettaglio
  // ─────────────────────────────────────────
  Widget _buildTable(
      List<DailyRecordDTO> records, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Dettaglio giornaliero',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
            ),
          ),
          // header
          Container(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _TH('Data', flex: 2),
                _TH('Rete kWh'),
                _TH('FV kWh'),
                _TH('PDC kWh'),
                _TH('Costo €'),
              ],
            ),
          ),
          // righe (più recenti in cima)
          ...records.reversed.map((r) {
            final cost =
                (r.energyFromGrid ?? 0.0) * _costPerKwh;
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.2)),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      r.dateIso,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurface),
                    ),
                  ),
                  _TD(r.energyFromGrid?.toStringAsFixed(1) ?? '-',
                      color: const Color(0xFFFFB74D)),
                  _TD(r.pvProduction?.toStringAsFixed(1) ?? '-',
                      color: const Color(0xFF81C784)),
                  _TD(r.consumption.toStringAsFixed(1),
                      color: const Color(0xFF4DB6AC)),
                  _TD(cost.toStringAsFixed(3),
                      color: cs.onSurface),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_outlined, size: 56,
              color: cs.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'Nessun dato energia',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Inserisci kWh rete e FV nella scheda\n"Registra" per vedere i grafici.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─── widget helper ───────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface),
            ),
            Text(
              sub,
              style: TextStyle(
                  fontSize: 10, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
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

class _TH extends StatelessWidget {
  final String text;
  final int flex;
  const _TH(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}
