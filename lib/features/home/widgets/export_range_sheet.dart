// lib/features/home/widgets/export_range_sheet.dart
//
// Widget bottom-sheet per la selezione del range date prima dell'export.
// Estratto da home_notifier.dart — refactor #1.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/daily_record_dto.dart';
import '../../../utils/date_utils.dart';

class ExportRangeSheet extends StatefulWidget {
  final List<DailyRecordDTO> records;
  final DateTime firstDate;
  final DateTime lastDate;

  const ExportRangeSheet({
    super.key,
    required this.records,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<ExportRangeSheet> createState() => _ExportRangeSheetState();
}

class _ExportRangeSheetState extends State<ExportRangeSheet> {
  // 0 = tutti, 1 = ultimo mese, 2 = ultimi 3 mesi, 3 = personalizzato
  int _selected = 0;
  DateTimeRange? _customRange;

  final _fmt = DateFormat('dd/MM/yyyy');

  List<DailyRecordDTO> filtered() {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;

    switch (_selected) {
      case 1:
        from = DateTime(now.year, now.month - 1, now.day);
        break;
      case 2:
        from = DateTime(now.year, now.month - 3, now.day);
        break;
      case 3:
        from = _customRange?.start;
        to = _customRange?.end;
        break;
      default:
        break;
    }

    return widget.records.where((r) {
      final d = parseItalianDateSafe(r.dateIso);
      if (d == null) return false;
      if (from != null && d.isBefore(from)) return false;
      if (to != null && d.isAfter(to.add(const Duration(days: 1)))) return false;
      return true;
    }).toList();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: widget.lastDate.subtract(const Duration(days: 30)),
            end: widget.lastDate,
          ),
      locale: const Locale('it', 'IT'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _selected = 3;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = filtered().length;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.date_range_outlined,
                    color: cs.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Seleziona periodo di export',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Opzioni rapide
          ExportRangeOption(
            icon: Icons.all_inclusive_rounded,
            label: 'Tutti i dati',
            subtitle: '${widget.records.length} registrazioni',
            selected: _selected == 0,
            onTap: () => setState(() => _selected = 0),
          ),
          const SizedBox(height: 8),
          ExportRangeOption(
            icon: Icons.calendar_month_outlined,
            label: 'Ultimo mese',
            subtitle: _subtitleForPreset(1),
            selected: _selected == 1,
            onTap: () => setState(() => _selected = 1),
          ),
          const SizedBox(height: 8),
          ExportRangeOption(
            icon: Icons.calendar_today_outlined,
            label: 'Ultimi 3 mesi',
            subtitle: _subtitleForPreset(2),
            selected: _selected == 2,
            onTap: () => setState(() => _selected = 2),
          ),
          const SizedBox(height: 8),

          // Range personalizzato
          ExportRangeOption(
            icon: Icons.tune_rounded,
            label: 'Range personalizzato',
            subtitle: _customRange != null
                ? '${_fmt.format(_customRange!.start)} → ${_fmt.format(_customRange!.end)}'
                : 'Tocca per scegliere',
            selected: _selected == 3,
            onTap: _pickCustomRange,
            trailing: Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ),
          const SizedBox(height: 24),

          // Counter live
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  count == 0
                      ? 'Nessuna registrazione nel periodo selezionato'
                      : '$count registrazioni verranno esportate',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Bottoni azione
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Annulla'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: count == 0
                      ? null
                      : () => Navigator.of(context).pop(filtered()),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Esporta ($count)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitleForPreset(int preset) {
    final now = DateTime.now();
    final months = preset == 1 ? 1 : 3;
    final from = DateTime(now.year, now.month - months, now.day);
    final count = widget.records.where((r) {
      final d = parseItalianDateSafe(r.dateIso);
      return d != null && !d.isBefore(from);
    }).length;
    return '$count registrazioni';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Singola card opzione — usata anche esternamente se necessario.
// ─────────────────────────────────────────────────────────────────────────────

class ExportRangeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const ExportRangeOption({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: selected ? cs.onPrimaryContainer : cs.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (selected && trailing == null)
                Icon(Icons.check_circle_rounded,
                    color: cs.onPrimaryContainer, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
