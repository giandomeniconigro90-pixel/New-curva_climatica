// lib/features/home/logic/ai_curve_service.dart
//
// Refactor #8 — Responsabilità estratta da HomeNotifier:
//   • onApplyAiCurve  — applica la curva suggerita e salva lo snapshot
//   • undoLastAiApply — ripristina il precedente snapshot
//   • _buildContextualNotificationBody — testo della notifica AI
//
// AiCurveService non ha stato proprio: riceve i valori correnti
// e restituisce il nuovo CurveSettings + lo snapshot via AiApplyResult.
// Il notifier aggiorna il proprio stato con il risultato e chiama
// _saveSettings() / AppStorage.

import 'package:flutter/material.dart';

import '../../../models/curve_settings.dart';
import '../../../services/hive_storage.dart';
import '../../../services/notification_service.dart';
import '../../../utils/app_toast.dart';
import '../../../utils/date_utils.dart';
import '../logic/curve_logic.dart';
import '../../../models/daily_record_dto.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class AiApplyResult {}

/// L'apply è andato a buon fine: il notifier deve aggiornare _settings.
final class AiApplySuccess extends AiApplyResult {
  final CurveSettings newSettings;
  final AiApplySnapshot snapshot;
  const AiApplySuccess(
      {required this.newSettings, required this.snapshot});
}

/// Nessun apply eseguito (warning già mostrato).
final class AiApplyAborted extends AiApplyResult {
  const AiApplyAborted();
}

sealed class AiUndoResult {}

final class AiUndoSuccess extends AiUndoResult {
  final CurveSettings newSettings;
  const AiUndoSuccess({required this.newSettings});
}

final class AiUndoAborted extends AiUndoResult {
  const AiUndoAborted();
}

// ---------------------------------------------------------------------------
// AiCurveService
// ---------------------------------------------------------------------------

class AiCurveService {
  const AiCurveService();

  // -------------------------------------------------------------------------
  // Apply
  // -------------------------------------------------------------------------

  /// Calcola la curva ottimale e, se diversa dall'attuale, la applica.
  /// Mostra toast e notifica. Restituisce [AiApplySuccess] o [AiApplyAborted].
  Future<AiApplyResult> applyAiCurve(
    BuildContext context, {
    required List<DailyRecordDTO> windowRecords,
    required double currentSlope,
    required double currentOffset,
    required CurveSettings currentSettings,
    required SystemMode mode,
  }) async {
    if (windowRecords.length < 5) {
      AppToast.show(
        'Serve almeno 5 rilevamenti nuovi (${windowRecords.length}/5)',
        context: context,
        level: ToastLevel.warning,
      );
      return const AiApplyAborted();
    }

    final suggestion = computeOptimalCurveSuggestion(
        windowRecords, currentSlope, currentOffset, mode);

    if ((suggestion.suggestedSlope - currentSlope).abs() < 0.05 &&
        (suggestion.suggestedOffset - currentOffset).abs() < 0.05) {
      AppToast.show(
        'I valori suggeriti sono uguali a quelli attuali. Nessuna modifica necessaria.',
        context: context,
        level: ToastLevel.warning,
      );
      return const AiApplyAborted();
    }

    final snapshot = AiApplySnapshot(
      slope: currentSlope,
      offset: currentOffset,
      mode: mode.toModeString(),
      appliedAt: DateTime.now().toIso8601String(),
      smartTip: suggestion.smartTip,
    );

    final nowApply = DateTime.now();
    final newSettings = mode == SystemMode.heating
        ? currentSettings.copyWith(
            heatingSlope: suggestion.suggestedSlope,
            heatingOffset: suggestion.suggestedOffset,
            lastAiApplyHeating: nowApply,
          )
        : currentSettings.copyWith(
            coolingSlope: suggestion.suggestedSlope,
            coolingOffset: suggestion.suggestedOffset,
            lastAiApplyCooling: nowApply,
          );

    if (context.mounted) {
      AppToast.show(
        'Nuova curva AI applicata!',
        context: context,
        level: ToastLevel.success,
      );
    }

    return AiApplySuccess(newSettings: newSettings, snapshot: snapshot);
  }

  // -------------------------------------------------------------------------
  // Undo
  // -------------------------------------------------------------------------

  Future<AiUndoResult> undoLastApply(
    BuildContext context, {
    required CurveSettings currentSettings,
  }) async {
    final snapshot = await AppStorage.popLastAiSnapshot();
    if (snapshot == null) {
      AppToast.show(
        'Nessun apply AI da annullare.',
        context: context,
        level: ToastLevel.warning,
      );
      return const AiUndoAborted();
    }

    final isHeating = snapshot.mode == 'heating';
    final newSettings = isHeating
        ? currentSettings.copyWith(
            heatingSlope: snapshot.slope,
            heatingOffset: snapshot.offset,
          )
        : currentSettings.copyWith(
            coolingSlope: snapshot.slope,
            coolingOffset: snapshot.offset,
          );

    final modeLabel =
        isHeating ? 'riscaldamento' : 'raffrescamento';
    if (context.mounted) {
      AppToast.show(
        'Ripristinata curva $modeLabel: '
        'S ${snapshot.slope.toStringAsFixed(2)} / '
        'O ${snapshot.offset.toStringAsFixed(1)}',
        context: context,
        level: ToastLevel.info,
      );
    }

    return AiUndoSuccess(newSettings: newSettings);
  }

  // -------------------------------------------------------------------------
  // Notifica contestuale post-salvataggio
  // -------------------------------------------------------------------------

  Future<void> maybeShowNotification({
    required List<DailyRecordDTO> windowRecords,
    required double slope,
    required double offset,
    required SystemMode mode,
  }) async {
    if (windowRecords.length < 5) return;
    try {
      final suggestion = computeOptimalCurveSuggestion(
          windowRecords, slope, offset, mode);
      final body = _buildBody(suggestion, slope, offset, mode);
      if (body != null) {
        await NotificationService.showContextualNotification(
          title: '\uD83E\uDDE0 ClimaSense AI',
          body: body,
        );
      }
    } catch (_) {}
  }

  String? _buildBody(
    CurveSuggestion suggestion,
    double slope,
    double offset,
    SystemMode mode,
  ) {
    final slopeDelta = suggestion.suggestedSlope - slope;
    final offsetDelta = suggestion.suggestedOffset - offset;
    if (slopeDelta.abs() < 0.05 && offsetDelta.abs() < 0.05) return null;

    if (suggestion.smartTip.isNotEmpty &&
        !suggestion.smartTip.toLowerCase().contains('apprendimento')) {
      return suggestion.smartTip;
    }

    final modeLabel = mode == SystemMode.heating
        ? 'riscaldamento'
        : 'raffrescamento';
    if (slopeDelta > 0) {
      return 'La curva di $modeLabel potrebbe essere incrementata. '
          'Valuta di applicare il suggerimento AI.';
    } else if (slopeDelta < 0) {
      return 'La curva di $modeLabel potrebbe essere ridotta. '
          'Valuta di applicare il suggerimento AI.';
    } else if (offsetDelta > 0) {
      return 'Offset $modeLabel in aumento suggerito. '
          'Controlla il grafico AI.';
    } else {
      return 'Offset $modeLabel in diminuzione suggerito. '
          'Controlla il grafico AI.';
    }
  }

  // -------------------------------------------------------------------------
  // Helper — filtro records da ultimo apply
  // -------------------------------------------------------------------------

  static List<DailyRecordDTO> recordsSinceLastApply({
    required List<DailyRecordDTO> records,
    required DateTime? lastApply,
  }) {
    if (lastApply == null) return List<DailyRecordDTO>.from(records);
    final lastDay =
        DateTime(lastApply.year, lastApply.month, lastApply.day);
    return records.where((r) {
      final d = parseItalianDateSafe(r.dateIso);
      return d != null && d.isAfter(lastDay);
    }).toList();
  }
}
