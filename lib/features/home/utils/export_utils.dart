import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:csv/csv.dart';

import '../../../models/daily_record_dto.dart';
import '../logic/curve_logic.dart';

class ExportUtils {

  /// Parsa date in formato dd/MM/yyyy o ISO yyyy-MM-dd
  static DateTime _parseDateSafe(String dateIso) {
    final slashParts = dateIso.split('/');
    if (slashParts.length == 3) {
      final d = int.tryParse(slashParts[0]);
      final m = int.tryParse(slashParts[1]);
      final y = int.tryParse(slashParts[2]);
      if (d != null && m != null && y != null) return DateTime(y, m, d);
    }
    return DateTime.tryParse(dateIso) ?? DateTime.now();
  }

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

  static Future<void> exportSimpleCsv(List<DailyRecordDTO> records) async {
    List<List<dynamic>> rows = [];
    _appendDataRows(rows, records);
    String csvData = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
    await shareCsv(csvData, "ClimaSense_Export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv");
  }

  static void _appendDataRows(List<List<dynamic>> rows, List<DailyRecordDTO> records) {
    if (records.isEmpty) return;
    final sortedRecords = List<DailyRecordDTO>.from(records);
    sortedRecords.sort((a, b) => b.dateIso.compareTo(a.dateIso));
    final Set<String> allRooms = {};
    for (var r in sortedRecords) {
      allRooms.addAll(r.internalTemps.keys);
    }
    final sortedRooms = allRooms.toList()..sort();
    List<String> header = ["Data", "T. Esterna", "Consumo", "Note"];
    for (var room in sortedRooms) {
      header.add("$room T.");
      header.add("$room Comfort");
    }
    rows.add(header);
    for (var r in sortedRecords) {
      final DateTime date = _parseDateSafe(r.dateIso);
      List<dynamic> row = [
        DateFormat('dd/MM/yyyy').format(date),
        r.externalTemp.toString().replaceAll('.', ','),
        r.consumption.toString().replaceAll('.', ','),
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
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = "${directory.path}/$fileName";
      final file = File(path);
      await file.writeAsString(csvData);
      await Share.shareXFiles([XFile(path)], text: 'Export Dati ClimaSense (CSV)');
    } catch (e) {
      print("Errore share CSV: $e");
    }
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
    await _createPdf(records, slope: slope, offset: offset, suggestion: suggestion, stats: stats, chartImage: chartImage, currentMode: currentMode);
  }

  static Future<void> exportSimplePdf(List<DailyRecordDTO> records) async {
    await _createPdf(records);
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
    sortedRecords.sort((a, b) => b.dateIso.compareTo(a.dateIso));
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                "ClimaSense Report",
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 10),
            if (chartImage != null)
              pw.Container(
                height: 200,
                width: 400,
                child: pw.Image(pw.MemoryImage(chartImage)),
              ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              context: context,
              headers: <String>['Data', 'Ext °C', 'Consumo', 'Note'],
              data: sortedRecords.map((r) {
                final date = _parseDateSafe(r.dateIso);
                return [
                  DateFormat('dd/MM/yyyy').format(date),
                  '${r.externalTemp}',
                  '${r.consumption}',
                  r.note,
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );
    final directory = await getApplicationDocumentsDirectory();
    final path = "${directory.path}/ClimaSense_Report.pdf";
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(path)], text: 'Export PDF');
  }

  // ================= BACKUP JSON =================
  static String generateBackupJson({
    required List<DailyRecordDTO> records,
    required SystemMode mode,
    required double heatingSlope,
    required double heatingOffset,
    required double coolingSlope,
    required double coolingOffset,
  }) {
    final Map<String, dynamic> backupMap = {
      "metadata": {"exportDate": DateTime.now().toIso8601String(), "appVersion": "1.0.0"},
      "settings": {
        "heatingSlope": heatingSlope, "heatingOffset": heatingOffset,
        "coolingSlope": coolingSlope, "coolingOffset": coolingOffset,
      },
      "records": records.map((e) => e.toJson()).toList(),
    };
    return jsonEncode(backupMap);
  }

  static Future<void> generateSimpleBackup(List<DailyRecordDTO> records) async {
    final jsonString = jsonEncode(records.map((e) => e.toJson()).toList());
    await shareBackupJsonString(jsonString);
  }

  static Future<void> shareBackupJsonString(String jsonString, [String? fileName]) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final name = fileName ?? "ClimaSense_Backup.json";
      final path = "${directory.path}/$name";
      final file = File(path);
      await file.writeAsString(jsonString);
      await Share.shareXFiles([XFile(path)], text: 'Backup JSON');
    } catch (e) {
      print("Errore Backup: $e");
    }
  }
}
