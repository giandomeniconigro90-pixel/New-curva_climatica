// lib/features/home/logic/export_service.dart
//
// Refactor #8 — Responsabilità estratta da HomeNotifier:
//   • CSV / PDF export
//   • Backup JSON (doBackup / doRestore)
//   • Chart capture tramite GlobalKey
//
// Non ha stato proprio: è istanziato da HomeNotifier e riceve
// i dati che gli servono tramite parametri. Non usa BuildContext
// internamente tranne dove indispensabile (dialog di conferma,
// range sheet, toast) — i callback UI restano nel notifier.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../models/curve_settings.dart';
import '../../../models/daily_record_dto.dart';
import '../../../repositories/curve_settings_repository.dart';
import '../../../services/hive_storage.dart';
import '../../../utils/app_toast.dart';
import '../../../utils/date_utils.dart';
import '../logic/curve_logic.dart';
import '../utils/backup_version.dart';
import '../utils/export_utils.dart';
import '../widgets/export_range_sheet.dart';

class ExportService {
  final CurveSettingsRepository settingsRepo;
  final GlobalKey chartKey;

  const ExportService({
    required this.settingsRepo,
    required this.chartKey,
  });

  // ---------------------------------------------------------------------------
  // Chart capture
  // ---------------------------------------------------------------------------

  Future<Uint8List?> captureChart() async {
    try {
      final boundary = chartKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Range sheet helper
  // ---------------------------------------------------------------------------

  Future<List<DailyRecordDTO>?> showExportRangeSheet(
    BuildContext context,
    List<DailyRecordDTO> records,
  ) async {
    if (records.isEmpty) return null;
    final sorted = List<DailyRecordDTO>.from(records)
      ..sort((a, b) {
        final dA = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
        final dB = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
        return dA.compareTo(dB);
      });
    final firstDate =
        parseItalianDateSafe(sorted.first.dateIso) ?? DateTime(2000);
    final lastDate =
        parseItalianDateSafe(sorted.last.dateIso) ?? DateTime.now();

    return showModalBottomSheet<List<DailyRecordDTO>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ExportRangeSheet(
        records: records,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------------------

  Future<void> exportCsv(
    BuildContext context, {
    required List<DailyRecordDTO> records,
    required double slope,
    required double offset,
    required SystemMode mode,
  }) async {
    if (records.isEmpty) {
      AppToast.show('Nessun dato da esportare!',
          context: context, level: ToastLevel.warning);
      return;
    }
    final filtered = await showExportRangeSheet(context, records);
    if (filtered == null || !context.mounted) return;
    try {
      final csv = ExportUtils.generateCsv(filtered,
          slope: slope, offset: offset, mode: mode);
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      await ExportUtils.shareCsv(csv, 'ClimaSense_$dateStr.csv');
    } catch (e) {
      if (context.mounted) {
        AppToast.show('Errore export CSV: $e',
            context: context, level: ToastLevel.error);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  /// [onSwitchToChartPage] e [onRestorePage] consentono al notifier
  /// di navigare alla pagina del grafico prima della cattura e ripristinarla.
  Future<void> exportPdf(
    BuildContext context, {
    required List<DailyRecordDTO> records,
    required List<DailyRecordDTO> windowRecords,
    required double slope,
    required double offset,
    required SystemMode mode,
    required int currentPage,
    required Future<void> Function() onSwitchToChartPage,
    required Future<void> Function() onRestorePage,
  }) async {
    if (records.isEmpty) {
      AppToast.show('Nessun dato da esportare!',
          context: context, level: ToastLevel.warning);
      return;
    }
    final filtered = await showExportRangeSheet(context, records);
    if (filtered == null || !context.mounted) return;

    final needSwitch = currentPage != 2;
    if (needSwitch) await onSwitchToChartPage();
    try {
      final chartImage = await captureChart();
      final suggestion = computeOptimalCurveSuggestion(
          windowRecords, slope, offset, mode);
      final stats = computeCurveStats(windowRecords);
      await ExportUtils.generateAndSavePdf(
        records: filtered,
        slope: slope,
        offset: offset,
        suggestion: suggestion,
        stats: stats,
        chartImage: chartImage,
        currentMode: mode,
      );
    } catch (e) {
      if (context.mounted) {
        AppToast.show('Errore export PDF: $e',
            context: context, level: ToastLevel.error);
      }
    } finally {
      if (needSwitch) await onRestorePage();
    }
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  Future<void> doBackup(
    BuildContext context, {
    required List<DailyRecordDTO> allRecords,
    required SystemMode mode,
    required double heatingSlope,
    required double heatingOffset,
    required double coolingSlope,
    required double coolingOffset,
  }) async {
    try {
      final backupJson = await ExportUtils.generateBackupJson(
        records: allRecords,
        mode: mode,
        heatingSlope: heatingSlope,
        heatingOffset: heatingOffset,
        coolingSlope: coolingSlope,
        coolingOffset: coolingOffset,
      );
      final date = DateTime.now().toIso8601String().split('T').first;
      await ExportUtils.shareBackupJsonString(
          backupJson, 'ClimaSenseBackup_$date.json');
    } catch (e) {
      if (context.mounted) {
        AppToast.show('Errore backup: $e',
            context: context, level: ToastLevel.error);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Restituisce i dati ripristinati se l'utente conferma,
  /// `null` se annulla o in caso di errore.
  Future<RestoredBackupData?> doRestore(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return null;

      final jsonString =
          await File(result.files.single.path!).readAsString();
      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
            'Il file non è un oggetto JSON valido.');
      }
      final backupData = decoded;

      if (backupData['metadata'] is! Map) {
        throw const FormatException(
            'Campo "metadata" mancante o non valido nel backup.');
      }
      if (backupData['settings'] is! Map) {
        throw const FormatException(
            'Campo "settings" mancante o non valido nel backup.');
      }
      if (backupData['records'] is! List) {
        throw const FormatException(
            'Campo "records" mancante o non è una lista nel backup.');
      }

      final metadata =
          backupData['metadata'] as Map<String, dynamic>;
      ExportUtils.validateBackupMetadata(metadata);

      if (!context.mounted) return null;

      final backupVersion =
          metadata['backupVersion'] as int? ?? 1;
      final backupDate =
          metadata['exportDate'] as String? ?? 'data sconosciuta';
      final appVersion = metadata['appVersion'] as String? ?? '?';
      final recordCount =
          (backupData['records'] as List).length;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conferma Ripristino'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Sovrascriverà tutti i dati attuali. Continuare?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Versione backup: v$backupVersion',
                        style: const TextStyle(fontSize: 12)),
                    Text('App version: $appVersion',
                        style: const TextStyle(fontSize: 12)),
                    Text('Registrazioni: $recordCount',
                        style: const TextStyle(fontSize: 12)),
                    Text(
                        'Data export: ${backupDate.split('T').first}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('CONFERMA',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return null;

      final settings =
          backupData['settings'] as Map<String, dynamic>;
      final newRecords = (backupData['records'] as List)
          .map((j) =>
              DailyRecordDTO.fromJson(j as Map<String, dynamic>))
          .toList();

      final modeStr = settings['mode'] as String? ?? 'heating';
      return RestoredBackupData(
        records: newRecords,
        settings: CurveSettings(
          heatingSlope:
              (settings['heatingSlope'] as num?)?.toDouble() ?? 1.0,
          heatingOffset:
              (settings['heatingOffset'] as num?)?.toDouble() ?? 0.0,
          coolingSlope:
              (settings['coolingSlope'] as num?)?.toDouble() ?? 0.5,
          coolingOffset:
              (settings['coolingOffset'] as num?)?.toDouble() ?? 0.0,
          mode: modeStr == 'cooling'
              ? SystemMode.cooling
              : SystemMode.heating,
        ),
      );
    } on BackupVersionException catch (e) {
      if (context.mounted) {
        AppToast.show(e.message,
            context: context, level: ToastLevel.error);
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        AppToast.show('Errore ripristino: $e',
            context: context, level: ToastLevel.error);
      }
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Value object restituito da doRestore()
// ---------------------------------------------------------------------------

class RestoredBackupData {
  final List<DailyRecordDTO> records;
  final CurveSettings settings;
  const RestoredBackupData(
      {required this.records, required this.settings});
}
