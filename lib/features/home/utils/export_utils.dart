// lib/features/home/utils/export_utils.dart

import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/daily_record_dto.dart';
import '../logic/curve_logic.dart';

class ExportUtils {
  // === GENERAZIONE CSV ===
  static String generateCsv(List<DailyRecordDTO> records, {
    double slope = 0.0,
    double offset = 20.0,
    SystemMode mode = SystemMode.heating,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Data;Temp Esterna;T Mandata Calcolata;Consumo;Note');

    for (final r in records) {
      final mandataCalcolata = computeMandata(r.externalTemp, slope, offset, mode);
      String row = '${r.dateIso};'
          '${r.externalTemp.toString().replaceAll('.', ',')};'
          '${mandataCalcolata.toStringAsFixed(1).replaceAll('.', ',')};'
          '${r.consumption.toString().replaceAll('.', ',')};'
          '${r.note}';
      buffer.writeln(row);
    }

    return buffer.toString();
  }

  // === CONDIVISIONE CSV (Salva dove vuoi) ===
  static Future<void> shareCsv(String csvData, String fileName) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvData);

    // Apre il pannello: su iOS "Salva su File", su Android condivisione generica
    await Share.shareXFiles(
        [XFile(file.path)],
        text: 'File CSV esportato da ClimaSense'
    );
  }

  // === GENERAZIONE PDF CON GRAFICO ===
  static Future<void> generateAndSavePdf({
    required double slope,
    required double offset,
    required List<DailyRecordDTO> records,
    required Uint8List? chartImage,
    required SystemMode currentMode,
    CurveSuggestion? suggestion,
    CurveStats? stats,
  }) async {
    final pdf = pw.Document();
    final bool isHeating = currentMode == SystemMode.heating;
    final String modeLabel = isHeating ? 'RISCALDAMENTO' : 'RAFFRESCAMENTO';
    final PdfColor primaryColor = isHeating ? PdfColor.fromInt(0xFFD84315) : PdfColor.fromInt(0xFF0277BD);
    final PdfColor accentColor = isHeating ? PdfColor.fromInt(0xFFFF7043) : PdfColor.fromInt(0xFF29B6F6);

    pw.MemoryImage? logo;
    try {
      final byteData = await rootBundle.load('assets/images/logo.png');
      logo = pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (_) {}

    final activeStats = stats ?? computeCurveStats(records);
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final filteredRecords = filterRecordsByMode(records, currentMode);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // HEADER
          pw.Container(
            decoration: pw.BoxDecoration(
              color: primaryColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            padding: const pw.EdgeInsets.all(24),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (logo != null)
                      pw.Container(
                        width: 40, height: 40,
                        margin: const pw.EdgeInsets.only(right: 12),
                        decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
                        child: pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.ClipOval(child: pw.Image(logo))),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('ClimaSense', style: pw.TextStyle(color: PdfColors.white, fontSize: 24, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Report Analisi Energetica', style: pw.TextStyle(color: PdfColors.white, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(modeLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text(dateStr, style: pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 30),
          _buildSectionTitle('PARAMETRI ATTUALI', primaryColor),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildStatCard('Pendenza', slope.toStringAsFixed(2), accentColor),
              _buildStatCard('Parallela', offset.toStringAsFixed(1), accentColor),
              _buildStatCard('Record', '${filteredRecords.length}', accentColor),
            ],
          ),
          pw.SizedBox(height: 20),
          _buildSectionTitle('STATISTICHE', primaryColor),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildStatCard('Consumo Medio', '${activeStats.avgConsumption.toStringAsFixed(1)} kWh', accentColor),
              _buildStatCard('Temp Min', '${activeStats.minExternalTemp.toStringAsFixed(1)}°', accentColor),
              _buildStatCard('Temp Max', '${activeStats.maxExternalTemp.toStringAsFixed(1)}°', accentColor),
            ],
          ),
          pw.SizedBox(height: 30),
          if (chartImage != null) ...[
            _buildSectionTitle('ANALISI VISIVA', primaryColor),
            pw.SizedBox(height: 15),
            pw.Center(
              child: pw.Container(
                height: 300,
                child: pw.Image(pw.MemoryImage(chartImage), fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 30),
          ],
        ],
      ),
    );

    if (filteredRecords.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            _buildSectionTitle('TABELLA DI RIFERIMENTO', primaryColor),
            pw.SizedBox(height: 8),
            _buildCurveReferenceTableCompact(slope, offset, currentMode, accentColor, primaryColor),
            pw.SizedBox(height: 20),
            _buildSectionTitle('STORICO RILEVAZIONI', primaryColor),
            pw.SizedBox(height: 8),
            _buildRecordsTableCompact(filteredRecords.take(20).toList(), slope, offset, currentMode, accentColor, primaryColor),
            pw.SizedBox(height: 40),
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text('Generato da ClimaSense App', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic)),
            ),
          ],
        ),
      );
    }

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'ClimaSense_Report.pdf');
  }

  static pw.Widget _buildSectionTitle(String title, PdfColor color) {
    return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 5),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: color, width: 1))),
        child: pw.Text(title, style: pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold, fontSize: 11))
    );
  }

  static pw.Widget _buildStatCard(String label, String value, PdfColor color) {
    return pw.Container(
      width: 100,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: color),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: pw.TextStyle(color: PdfColors.grey700, fontSize: 8)),
          pw.Text(value, style: pw.TextStyle(color: color, fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _buildCurveReferenceTableCompact(double slope, double offset, SystemMode mode, PdfColor accentColor, PdfColor primaryColor) {
    final List<int> temps = mode == SystemMode.heating ? [-5, 0, 5, 10, 15] : [25, 28, 30, 35, 40];
    final rows = [['T Est. (°C)', 'T Mandata (°C)'], ...temps.map((t) {
      final mandata = computeMandata(t.toDouble(), slope, offset, mode);
      return ['$t', '${mandata.toStringAsFixed(1)}'];
    })];
    return pw.Table(
      border: pw.TableBorder.all(color: accentColor, width: 0.5),
      columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1)},
      children: rows.asMap().entries.map((entry) {
        final isHeader = entry.key == 0;
        return pw.TableRow(
          decoration: pw.BoxDecoration(color: isHeader ? primaryColor : (entry.key % 2 == 0 ? PdfColors.grey50 : PdfColors.white)),
          children: entry.value.map((cell) => pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(cell, style: pw.TextStyle(fontSize: 9, fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal, color: isHeader ? PdfColors.white : PdfColors.black), textAlign: pw.TextAlign.center),
          )).toList(),
        );
      }).toList(),
    );
  }

  static pw.Widget _buildRecordsTableCompact(List<DailyRecordDTO> records, double slope, double offset, SystemMode mode, PdfColor accentColor, PdfColor primaryColor) {
    final headerRow = ['Data', 'T Est.', 'T Mandata', 'kWh'];
    final dataRows = records.map((r) {
      final mandata = computeMandata(r.externalTemp, slope, offset, mode);
      return [r.dateIso, '${r.externalTemp.toInt()}°', '${mandata.toStringAsFixed(1)}°', '${r.consumption}'];
    }).toList();
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: primaryColor),
          children: headerRow.map((h) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center))).toList(),
        ),
        ...dataRows.map((row) => pw.TableRow(
          children: row.map((cell) => pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(cell, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center))).toList(),
        )).toList(),
      ],
    );
  }

  // === BACKUP CON SELEZIONE DESTINAZIONE ===

  static String generateBackupJson({
    required List<DailyRecordDTO> records,
    required SystemMode mode,
    required double heatingSlope,
    required double heatingOffset,
    required double coolingSlope,
    required double coolingOffset,
  }) {
    final backupData = {
      'metadata': {
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'appName': 'ClimaSense',
      },
      'settings': {
        'systemMode': mode == SystemMode.heating ? 'heating' : 'cooling',
        'heatingSlope': heatingSlope,
        'heatingOffset': heatingOffset,
        'coolingSlope': coolingSlope,
        'coolingOffset': coolingOffset,
      },
      'records': records.map((r) => r.toJson()).toList(),
    };
    return jsonEncode(backupData);
  }

  /// Salva il JSON e chiede all'utente dove metterlo (Drive, Files, Share...)
  static Future<void> shareBackupJson(String json, String fileName) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName.json');
    await file.writeAsString(json);

    // Apriamo il dialog nativo
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Backup ClimaSense del ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
      subject: 'Backup ClimaSense',
    );
  }
}
