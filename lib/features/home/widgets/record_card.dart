// lib/features/home/widgets/record_card.dart
//
// Card singola registrazione giornaliera con:
//  • Dismissible swipe-to-delete (sinistra/destra) + SnackBar undo
//  • Icona nota, edit e badge modalità pompa
//  • Nessuna dipendenza da HomeNotifier: tutto via callback

import 'package:flutter/material.dart';

import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../../../utils/date_utils.dart';

class RecordCard extends StatelessWidget {
  final DailyRecordDTO record;
  final void Function(String dateIso)? onEdit;
  final Future<void> Function(String dateIso)? onDelete;

  const RecordCard({
    super.key,
    required this.record,
    this.onEdit,
    this.onDelete,
  });

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  static (IconData, Color) _heatpumpMeta(String mode) {
    switch (mode.toLowerCase()) {
      case 'riscaldamento':
        return (Icons.local_fire_department, Colors.deepOrange);
      case 'raffrescamento':
        return (Icons.ac_unit, Colors.lightBlue);
      default:
        return (Icons.power_off, Colors.grey);
    }
  }

  static Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPv = AppStorage.getHasPv();
    final hasGridMeter = AppStorage.getHasGridMeter();

    final date = parseItalianDateSafe(record.dateIso) ?? DateTime.now();
    final hasAcs = record.consumptionACS != null;
    final hasMode =
        record.heatpumpMode != null && record.heatpumpMode!.isNotEmpty;
    final showGrid = hasGridMeter && record.energyFromGrid != null;
    final showPv = hasPv && record.pvProduction != null;

    Widget card = Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit != null ? () => onEdit!(record.dateIso) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Data badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
              const SizedBox(width: 14),
              // Dati
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Temperatura esterna — riga principale
                    Row(
                      children: [
                        const Icon(Icons.thermostat,
                            size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          'Esterna: ${record.externalTemp}\u00b0C',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    _infoRow(
                      icon: Icons.flash_on,
                      iconColor: Colors.amber,
                      text: 'Consumo: ${record.consumption} kWh',
                      cs: cs,
                    ),
                    if (hasAcs)
                      _infoRow(
                        icon: Icons.water_drop,
                        iconColor: Colors.blueAccent,
                        text: 'ACS: ${record.consumptionACS} kWh',
                        cs: cs,
                      ),
                    if (showGrid)
                      _infoRow(
                        icon: Icons.electrical_services_outlined,
                        iconColor: const Color(0xFFFFB74D),
                        text:
                            'Rete: ${record.energyFromGrid!.toStringAsFixed(1)} kWh',
                        cs: cs,
                      ),
                    if (showPv)
                      _infoRow(
                        icon: Icons.wb_sunny_outlined,
                        iconColor: const Color(0xFF66BB6A),
                        text:
                            'FV: ${record.pvProduction!.toStringAsFixed(1)} kWh',
                        cs: cs,
                      ),
                    if (hasMode)
                      _infoRow(
                        icon: _heatpumpMeta(record.heatpumpMode!).$1,
                        iconColor: _heatpumpMeta(record.heatpumpMode!).$2,
                        text: 'PDC: ${record.heatpumpMode}',
                        cs: cs,
                      ),
                  ],
                ),
              ),
              // Azioni destra
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (record.note.isNotEmpty)
                    Icon(Icons.sticky_note_2_outlined,
                        color: cs.onSurfaceVariant, size: 18),
                  if (onEdit != null)
                    IconButton(
                      onPressed: () => onEdit!(record.dateIso),
                      icon: Icon(Icons.edit, size: 20, color: cs.primary),
                      tooltip: 'Modifica',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // Swipe-to-delete: solo se il callback è disponibile
    if (onDelete != null) {
      card = _SwipableDeleteWrapper(
        record: record,
        onDelete: onDelete!,
        child: card,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card,
    );
  }
}

// ---------------------------------------------------------------------------
// Wrapper Dismissible con SnackBar undo
// ---------------------------------------------------------------------------

class _SwipableDeleteWrapper extends StatefulWidget {
  final DailyRecordDTO record;
  final Future<void> Function(String dateIso) onDelete;
  final Widget child;

  const _SwipableDeleteWrapper({
    required this.record,
    required this.onDelete,
    required this.child,
  });

  @override
  State<_SwipableDeleteWrapper> createState() => _SwipableDeleteWrapperState();
}

class _SwipableDeleteWrapperState extends State<_SwipableDeleteWrapper> {
  bool _deleted = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(widget.record.dateIso),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(Icons.delete_sweep_rounded,
            color: cs.onErrorContainer, size: 28),
      ),
      confirmDismiss: (_) async {
        // Anticipa con SnackBar + undo. Il dismiss vero avviene
        // solo se l'utente NON preme Annulla entro 3s.
        bool undone = false;

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Registrazione del ${widget.record.dateIso} eliminata',
            ),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'ANNULLA',
              onPressed: () {
                undone = true;
              },
            ),
          ),
        );

        // Aspettiamo la durata dello SnackBar
        await Future.delayed(const Duration(seconds: 3));
        return !undone;
      },
      onDismissed: (_) async {
        if (_deleted) return;
        _deleted = true;
        await widget.onDelete(widget.record.dateIso);
      },
      child: widget.child,
    );
  }
}
