// lib/features/home/widgets/results_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../../../utils/app_toast.dart';
import '../../../utils/date_utils.dart';
import '../logic/curve_logic.dart';
import 'record_card.dart';

class ResultsPage extends StatefulWidget {
  final List<DailyRecordDTO> records;
  final double? slope;
  final double? offset;
  final CurveSuggestion? suggestion;
  final CurveStats? stats;
  final VoidCallback? onApplyAiCurve;
  final void Function(String dateIso)? onEditRecordByDateIso;
  final Future<void> Function(String dateIso)? onDeleteRecordByDateIso;
  // F4
  final List<AiApplySnapshot> aiHistory;
  final Future<void> Function(BuildContext)? onUndoAiApply;

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
    this.aiHistory = const [],
    this.onUndoAiApply,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  // -------------------------------------------------------------------------
  // AnimatedList key — ricreata quando la lista cambia lunghezza
  // -------------------------------------------------------------------------
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<DailyRecordDTO> _sortedRecords;

  @override
  void initState() {
    super.initState();
    _sortedRecords = _sorted(widget.records);
  }

  @override
  void didUpdateWidget(ResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      final newSorted = _sorted(widget.records);
      // Inserimento: nuovo record in testa
      if (newSorted.length > _sortedRecords.length) {
        _sortedRecords = newSorted;
        _listKey.currentState?.insertItem(0,
            duration: const Duration(milliseconds: 350));
      } else {
        // Aggiornamento generico (edit o delete): ricostruiamo la lista
        _sortedRecords = newSorted;
      }
    }
  }

  static List<DailyRecordDTO> _sorted(List<DailyRecordDTO> src) =>
      List<DailyRecordDTO>.from(src)
        ..sort((a, b) {
          final da = parseItalianDateSafe(a.dateIso) ?? DateTime.now();
          final db = parseItalianDateSafe(b.dateIso) ?? DateTime.now();
          return db.compareTo(da);
        });

  // -------------------------------------------------------------------------
  // Build principale
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) {
      return const Center(
        child: Text('Nessun dato registrato',
            style: TextStyle(color: Colors.grey)),
      );
    }

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
              // F4 — Storico apply AI
              if (widget.aiHistory.isNotEmpty) ...[
                _buildAiHistoryCard(context),
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
              // AnimatedList per animazione inserimento
              AnimatedList(
                key: _listKey,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                initialItemCount: _sortedRecords.length,
                itemBuilder: (context, index, animation) {
                  if (index >= _sortedRecords.length) {
                    return const SizedBox.shrink();
                  }
                  final r = _sortedRecords[index];
                  return _buildAnimatedItem(context, r, animation);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedItem(
    BuildContext context,
    DailyRecordDTO r,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0.3, 1.0),
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.15),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: RecordCard(
            record: r,
            onEdit: widget.onEditRecordByDateIso,
            onDelete: widget.onDeleteRecordByDateIso,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // AI Card
  // -------------------------------------------------------------------------

  Widget _buildAiCard(BuildContext context, CurveSuggestion suggestion) {
    final cs = Theme.of(context).colorScheme;

    final int windowCount = suggestion.learningProgress;
    final bool hasEnoughData = windowCount >= 5;

    final bool valuesAreEqual = widget.slope != null &&
        widget.offset != null &&
        (suggestion.suggestedSlope - widget.slope!).abs() < 0.05 &&
        (suggestion.suggestedOffset - widget.offset!).abs() < 0.05;

    final List<RoomComfortStat> roomStats =
        hasEnoughData ? analyzeRoomComfort(widget.records) : [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: hasEnoughData
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
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
                  'Rilevamenti: $windowCount / 5',
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
          if (roomStats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.meeting_room_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Stanze con disagio',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...roomStats.map((s) => _buildRoomStatRow(context, s)),
          ],
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
                          : 'Serve 5+ rilevamenti ($windowCount/5)',
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

  // -------------------------------------------------------------------------
  // AI History Card
  // -------------------------------------------------------------------------

  Widget _buildAiHistoryCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.history,
                    color: cs.onTertiaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Storico Apply AI',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                    fontSize: 16,
                  ),
                ),
              ),
              if (widget.onUndoAiApply != null)
                TextButton.icon(
                  onPressed: () => widget.onUndoAiApply!(context),
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Annulla ultimo',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...widget.aiHistory.take(5).toIndexedMap((i, s) {
            final isFirst = i == 0;
            final dt = DateTime.tryParse(s.appliedAt);
            final dateLabel =
                dt != null ? fmt.format(dt.toLocal()) : s.appliedAt;
            final modeLabel =
                s.mode == 'heating' ? '\uD83D\uDD25 Risc.' : '\u2744\uFE0F Raff.';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isFirst
                    ? cs.primaryContainer.withValues(alpha: 0.5)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: isFirst
                    ? Border.all(color: cs.primary.withValues(alpha: 0.3))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '$modeLabel  S: ${s.slope.toStringAsFixed(2)}  O: ${s.offset.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            if (isFirst) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'ULTIMO',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (s.smartTip.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            s.smartTip,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          if (widget.aiHistory.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ altri ${widget.aiHistory.length - 5} apply precedenti',
                style:
                    TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Room stat row
  // -------------------------------------------------------------------------

  Widget _buildRoomStatRow(BuildContext context, RoomComfortStat s) {
    final cs = Theme.of(context).colorScheme;
    final bool isCold = s.dominantIssue == RoomComfortIssue.tooCold;
    final Color issueColor =
        isCold ? Colors.blue.shade300 : Colors.orange.shade400;
    final IconData issueIcon =
        isCold ? Icons.ac_unit : Icons.local_fire_department_outlined;
    final String issueLabel =
        isCold ? '${s.coldDays} g. freddo' : '${s.hotDays} g. caldo';
    final double barFill = s.issueRate.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(issueIcon, size: 14, color: issueColor),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            child: Text(
              s.room,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: barFill,
                backgroundColor: cs.surfaceContainerHighest,
                color: issueColor,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            issueLabel,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper extension
// ---------------------------------------------------------------------------

extension _IndexedMap<T> on Iterable<T> {
  Iterable<R> toIndexedMap<R>(R Function(int index, T item) f) sync* {
    int i = 0;
    for (final item in this) {
      yield f(i++, item);
    }
  }
}
