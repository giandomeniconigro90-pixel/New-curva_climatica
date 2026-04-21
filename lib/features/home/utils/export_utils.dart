import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:csv/csv.dart';

import '../../../models/daily_record_dto.dart';
import '../../../utils/date_utils.dart';
import '../logic/curve_logic.dart';

class ExportUtils {

  // ================= CSV =================
  static String generateCsv(
      List<DailyRecordDTO> records, {
        required double slope,
        required double offset,
        required SystemMode mode,
      }) {
    List<List<dynamic>> rows = [];
    rows.add(["--- Parametri Attuali ---"]);
    rows.add(["Modo", mode == SystemMode.heating ? "Riscaldamento" : "Raffrescamento"]);
    rows.add(["Curva (Slope)", slope.toString().replaceAll('.', ',')]);
    rows.add(["Parallela (Offset)", offset.toString().replaceAll('.', ',')]);
    rows.add([]);
    _appendDataRows(rows, records);
    return const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
  }

  static void _appendDataRows(List<List<dynamic>> rows, List<DailyRecordDTO> records) {
    if (records.isEmpty) return;
    final sortedRecords = List<DailyRecordDTO>.from(records);
    sortedRecords.sort((a, b) {
      final dA = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
      final dB = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
      return dB.compareTo(dA);
    });
    final Set<String> allRooms = {};
    for (var r in sortedRecords) {
      allRooms.addAll(r.internalTemps.keys);
    }
    final sortedRooms = allRooms.toList()..sort();

    // Header
    List<String> header = [
      "Data",
      "T. Esterna (°C)",
      "Consumo (kWh)",
      "ACS (kWh)",
      "Energia Rete (kWh)",
      "Fotovoltaico (kWh)",
      "Pompa di Calore",
      "Caldaia",
      "Note",
    ];
    for (var room in sortedRooms) {
      header.add("$room T. (°C)");
      header.add("$room Comfort");
    }
    rows.add(header);

    // Righe dati
    for (var r in sortedRecords) {
      final DateTime date = parseItalianDateSafe(r.dateIso) ?? DateTime.now();
      List<dynamic> row = [
        DateFormat('dd/MM/yyyy').format(date),
        r.externalTemp.toString().replaceAll('.', ','),
        r.consumption.toString().replaceAll('.', ','),
        r.consumptionACS != null
            ? r.consumptionACS!.toString().replaceAll('.', ',')
            : "",
        r.energyFromGrid != null
            ? r.energyFromGrid!.toString().replaceAll('.', ',')
            : "",
        r.pvProduction != null
            ? r.pvProduction!.toString().replaceAll('.', ',')
            : "",
        r.heatpumpMode ?? "",
        r.boilerMode ?? "",
        r.note.replaceAll('\n', ' '),
      ];
      for (var room in sortedRooms) {
        row.add(r.internalTemps[room]?.toString().replaceAll('.', ',') ?? "");
        row.add(r.comfortRatings[room] ?? "");
      }
      rows.add(row);
    }
  }

  static Future<void> shareCsv(String csvData, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(path)], text: 'Export Dati ClimaSense (CSV)');
    _deleteFileSilently(file);
  }

  // ================= PDF =================
  static Future<void> generateAndSavePdf({
    required List<DailyRecordDTO> records,
    required double slope,
    required double offset,
    required CurveSuggestion suggestion,
    required CurveStats stats,
    required Uint8List? chartImage,
    required SystemMode currentMode,
  }) async {
    await _createPdf(
      records,
      slope: slope,
      offset: offset,
      suggestion: suggestion,
      stats: stats,
      chartImage: chartImage,
      currentMode: currentMode,
    );
  }

  static Future<void> _createPdf(
      List<DailyRecordDTO> records, {
        double? slope,
        double? offset,
        CurveSuggestion? suggestion,
        CurveStats? stats,
        Uint8List? chartImage,
        SystemMode? currentMode,
      }) async {
    final pdf = pw.Document();
    final sortedRecords = List<DailyRecordDTO>.from(records);
    sortedRecords.sort((a, b) {
      final dA = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
      final dB = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
      return dB.compareTo(dA);
    });

    // Calcola statistiche energetiche aggregate
    final recordsWithGrid = sortedRecords.where((r) => r.energyFromGrid != null);
    final recordsWithPv = sortedRecords.where((r) => r.pvProduction != null);
    final recordsWithAcs = sortedRecords.where((r) => r.consumptionACS != null);

    final totalConsumption = sortedRecords.fold(0.0, (s, r) => s + r.consumption);
    final totalAcs = recordsWithAcs.fold(0.0, (s, r) => s + r.consumptionACS!);
    final totalGrid = recordsWithGrid.fold(0.0, (s, r) => s + r.energyFromGrid!);
    final totalPv = recordsWithPv.fold(0.0, (s, r) => s + r.pvProduction!);

    final modeLabel = currentMode == SystemMode.heating ? 'Riscaldamento' : 'Raffrescamento';
    final exportDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // ── Intestazione ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'ClimaSense Report',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  exportDate,
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
            pw.Divider(thickness: 1.5),
            pw.SizedBox(height: 8),

            // ── Parametri curva ──
            pw.Text('Parametri Curva', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Table.fromTextArray(
              headers: ['Modalità', 'Pendenza (Slope)', 'Parallela (Offset)', 'Suggerimento AI'],
              data: [
                [
                  modeLabel,
                  slope?.toStringAsFixed(2) ?? '-',
                  offset?.toStringAsFixed(2) ?? '-',
                  suggestion != null
                      ? 'Slope ${suggestion.newSlope.toStringAsFixed(2)} / Offset ${suggestion.newOffset.toStringAsFixed(2)}'
                      : '-',
                ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.centerLeft,
              },
            ),
            pw.SizedBox(height: 12),

            // ── Statistiche aggregate ──
            pw.Text('Riepilogo Energetico (${sortedRecords.length} giorni)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Table.fromTextArray(
              headers: ['Voce', 'Totale', 'Media/giorno', 'Giorni rilevati'],
              data: [
                [
                  'Consumo Pompa di Calore',
                  '${totalConsumption.toStringAsFixed(1)} kWh',
                  sortedRecords.isNotEmpty ? '${(totalConsumption / sortedRecords.length).toStringAsFixed(1)} kWh' : '-',
                  '${sortedRecords.length}',
                ],
                if (recordsWithAcs.isNotEmpty)
                  [
                    'ACS (Atlantic Calypso)',
                    '${totalAcs.toStringAsFixed(1)} kWh',
                    '${(totalAcs / recordsWithAcs.length).toStringAsFixed(1)} kWh',
                    '${recordsWithAcs.length}',
                  ],
                if (recordsWithGrid.isNotEmpty)
                  [
                    'Energia da Rete',
                    '${totalGrid.toStringAsFixed(1)} kWh',
                    '${(totalGrid / recordsWithGrid.length).toStringAsFixed(1)} kWh',
                    '${recordsWithGrid.length}',
                  ],
                if (recordsWithPv.isNotEmpty)
                  [
                    'Produzione Fotovoltaico',
                    '${totalPv.toStringAsFixed(1)} kWh',
                    '${(totalPv / recordsWithPv.length).toStringAsFixed(1)} kWh',
                    '${recordsWithPv.length}',
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),
            pw.SizedBox(height: 12),

            // ── Grafico curva (se disponibile) ──
            if (chartImage != null) ...[
              pw.Text('Grafico Curva Climatica', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Container(
                height: 200,
                width: double.infinity,
                child: pw.Image(pw.MemoryImage(chartImage)),
              ),
              pw.SizedBox(height: 12),
            ],

            // ── Tabella giornaliera ──
            pw.Text('Registrazioni Giornaliere', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Table.fromTextArray(
              context: context,
              headers: <String>[
                'Data',
                'Ext\n°C',
                'HP\nkWh',
                'ACS\nkWh',
                'Rete\nkWh',
                'PV\nkWh',
                'Pompa\ndi Calore',
                'Caldaia',
                'Note',
              ],
              data: sortedRecords.map((r) {
                final date = parseItalianDateSafe(r.dateIso) ?? DateTime.now();
                return [
                  DateFormat('dd/MM/yy').format(date),
                  '${r.externalTemp}',
                  '${r.consumption}',
                  r.consumptionACS != null ? '${r.consumptionACS}' : '-',
                  r.energyFromGrid != null ? '${r.energyFromGrid}' : '-',
                  r.pvProduction != null ? '${r.pvProduction}' : '-',
                  r.heatpumpMode ?? '-',
                  r.boilerMode ?? '-',
                  r.note.length > 40 ? '${r.note.substring(0, 40)}…' : r.note,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(52),
                1: const pw.FixedColumnWidth(28),
                2: const pw.FixedColumnWidth(28),
                3: const pw.FixedColumnWidth(28),
                4: const pw.FixedColumnWidth(28),
                5: const pw.FixedColumnWidth(28),
                6: const pw.FixedColumnWidth(52),
                7: const pw.FixedColumnWidth(40),
                8: const pw.FlexColumnWidth(),
              },
            ),
          ];
        },
        footer: (pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('ClimaSense — Export automatico', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
            pw.Text('Pag. ${context.pageNumber} / ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/ClimaSense_Report.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(path)], text: 'Export PDF ClimaSense');
    _deleteFileSilently(file);
  }

  // ================= BACKUP JSON =================

  static Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }

  static Future<String> generateBackupJson({
    required List<DailyRecordDTO> records,
    required SystemMode mode,
    required double heatingSlope,
    required double heatingOffset,
    required double coolingSlope,
    required double coolingOffset,
  }) async {
    final appVersion = await _getAppVersion();
    final Map<String, dynamic> backupMap = {
      'metadata': {
        'exportDate': DateTime.now().toIso8601String(),
        'appVersion': appVersion,
      },
      'settings': {
        'heatingSlope': heatingSlope,
        'heatingOffset': heatingOffset,
        'coolingSlope': coolingSlope,
        'coolingOffset': coolingOffset,
      },
      'records': records.map((e) => e.toJson()).toList(),
    };
    return jsonEncode(backupMap);
  }

  static Future<void> shareBackupJsonString(String jsonString, [String? fileName]) async {
    final directory = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'ClimaSense_Backup.json';
    final path = '${directory.path}/$name';
    final file = File(path);
    await file.writeAsString(jsonString);
    await Share.shareXFiles([XFile(path)], text: 'Backup JSON');
    _deleteFileSilently(file);
  }

  static void _deleteFileSilently(File file) {
    file.delete().catchError((e) {
      debugPrint('ExportUtils: impossibile eliminare file temp: $e');
      return file;
    });
  }
}
