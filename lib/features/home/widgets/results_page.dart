// lib/features/home/widgets/results_page.dart

import 'package:flutter/material.dart';

import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../../../utils/app_toast.dart';
import '../../../utils/date_utils.dart';
import '../logic/curve_logic.dart';

class ResultsPage extends StatefulWidget {
  final List<DailyRecordDTO> records;
  final double? slope;
  final double? offset;
  final CurveSuggestion? suggestion;
  final CurveStats? stats;
  final VoidCallback? onApplyAiCurve;
  final void Function(String dateIso)? onEditRecordByDateIso;
  final Future<void> Function(String dateIso)? onDeleteRecordByDateIso;

  const ResultsPage({
    super.key,
    required this.records,
    this.slope,
    this.offset,
    this.suggestion,
    this.stats,
    this.onApplyAiCurve,
    this.onEditRecordByDateIso,
    this.onDeleteRecordByDateIso,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  Future<void> _handleDelete(BuildContext context, DailyRecordDTO record) async {
    final date = parseItalianDateSafe(record.dateIso) ?? DateTime.now();
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 10),
            Text('Elimina registrazione'),
          ],
        ),
        content: Text(
          'Vuoi eliminare la registrazione del $dateStr?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await widget.onDeleteRecordByDateIso?.call(record.dateIso);

    if (context.mounted) {
      AppToast.show(
        context,
        'Registrazione del $dateStr eliminata',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    }
  }

  (IconData, Color) _heatpumpIconAndColor(String mode) {
    switch (mode.toLowerCase()) {
      case 'riscaldamento':
        return (Icons.local_fire_department, Colors.deepOrange);
      case 'raffrescamento':
        return (Icons.ac_unit, Colors.lightBlue);
      default:
        return (Icons.power_off, Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bool hasPv = AppStorage.getHasPv();
    final bool hasGridMeter = AppStorage.getHasGridMeter();

    if (widget.records.isEmpty) {
      return const Center(
        child: Text('Nessun dato registrato',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final sortedRecords = List<DailyRecordDTO>.from(widget.records)
      ..sort((a, b) {
        final da = parseItalianDateSafe(a.dateIso) ?? DateTime.now();
        final db = parseItalianDateSafe(b.dateIso) ?? DateTime.now();
        return db.compareTo(da);
      });

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Riepilogo',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              if (widget.suggestion != null) ...[
                _buildAiCard(context, widget.suggestion!),
                const SizedBox(height: 24),
              ],
              Text(
                'Storico Recente',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedRecords.length,
                itemBuilder: (context, index) {
                  final r = sortedRecords[index];
                  final date =
                      parseItalianDateSafe(r.dateIso) ?? DateTime.now();
                  final hasAcs = r.consumptionACS != null;
                  final hasMode = r.heatpumpMode != null && r.heatpumpMode!.isNotEmpty;
                  final showGrid = hasGridMeter && r.energyFromGrid != null;
                  final showPv = hasPv && r.pvProduction != null;

                  return InkWell(
                    onTap: widget.onEditRecordByDateIso != null
                        ? () => widget.onEditRecordByDateIso!(r.dateIso)
                        : null,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                                Text(
                                  '${date.month}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.thermostat,
                                        size: 14, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Esterna: ${r.externalTemp}°C',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.flash_on,
                                        size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Consumo: ${r.consumption} kWh',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                if (hasAcs) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.water_drop,
                                          size: 14, color: Colors.blueAccent),
                                      const SizedBox(width: 4),
                                      Text(
                                        'ACS: ${r.consumptionACS} kWh',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (showGrid) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.electrical_services_outlined,
                                          size: 14, color: Color(0xFFFFB74D)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Rete: ${r.energyFromGrid!.toStringAsFixed(1)} kWh',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (showPv) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.wb_sunny_outlined,
                                          size: 14, color: Color(0xFF66BB6A)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'FV: ${r.pvProduction!.toStringAsFixed(1)} kWh',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (hasMode) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        _heatpumpIconAndColor(r.heatpumpMode!).$1,
                                        size: 14,
                                        color: _heatpumpIconAndColor(r.heatpumpMode!).$2,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'PDC: ${r.heatpumpMode}',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (r.note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(Icons.sticky_note_2_outlined,
                                  color: cs.onSurfaceVariant, size: 18),
                            ),
                          if (widget.onEditRecordByDateIso != null)
                            IconButton(
                              onPressed: () =>
                                  widget.onEditRecordByDateIso!(r.dateIso),
                              icon: Icon(Icons.edit,
                                  size: 20, color: cs.primary),
                              tooltip: 'Modifica',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          if (widget.onDeleteRecordByDateIso != null) ...[
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: () =>
                                  _handleDelete(context, r),
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: cs.error),
                              tooltip: 'Elimina',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiCard(BuildContext context, CurveSuggestion suggestion) {
    final cs = Theme.of(context).colorScheme;
    final int recentRecordsCount = widget.records.length;
    final bool hasEnoughData = recentRecordsCount >= 5;
    final bool valuesAreEqual = widget.slope != null &&
        widget.offset != null &&
        (suggestion.suggestedSlope - widget.slope!).abs() < 0.05 &&
        (suggestion.suggestedOffset - widget.offset!).abs() < 0.05;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome,
                    color: cs.onSecondaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'AI Advisor',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: hasEnoughData
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasEnoughData ? Colors.green : Colors.orange,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasEnoughData ? Icons.check_circle : Icons.schedule,
                  size: 16,
                  color: hasEnoughData
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  'Rilevamenti: $recentRecordsCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: hasEnoughData
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.smartTip,
            style: TextStyle(
                fontSize: 14, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (widget.onApplyAiCurve != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: hasEnoughData && !valuesAreEqual
                    ? widget.onApplyAiCurve
                    : null,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  valuesAreEqual
                      ? 'Valori identici (nessuna modifica)'
                      : hasEnoughData
                          ? 'Applica Curva (S:${suggestion.suggestedSlope.toStringAsFixed(1)} O:${suggestion.suggestedOffset.toStringAsFixed(1)})'
                          : 'Serve 5+ rilevamenti ($recentRecordsCount)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasEnoughData && !valuesAreEqual
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  foregroundColor: hasEnoughData && !valuesAreEqual
                      ? cs.onPrimary
                      : cs.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
