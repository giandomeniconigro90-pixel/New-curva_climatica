import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../core/constants/room_constants.dart';
import '../../models/daily_record_dto.dart';
import '../../services/hive_storage.dart';
import '../../services/notification_service.dart';
import '../../utils/date_utils.dart';
import '../initial_settings/initial_settings_home.dart';

import 'logic/curve_logic.dart';
import 'utils/export_utils.dart';

class HomeNotifier extends ChangeNotifier {
  late PageController pageController;

  final TextEditingController externalTempController = TextEditingController();
  final TextEditingController consumptionController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final Map<String, TextEditingController> internalTempControllers = {};

  final Map<String, String> comfortRatings = {};

  List<DailyRecordDTO> allRecords = [];

  List<DailyRecordDTO> get records {
    final modeStr = currentMode == SystemMode.cooling ? 'cooling' : 'heating';
    return allRecords.where((r) => r.mode == modeStr).toList();
  }

  late double slope;
  late double offset;

  SystemMode currentMode = SystemMode.heating;

  double cachedHeatingSlope = 1.2;
  double cachedHeatingOffset = 0.0;
  double cachedCoolingSlope = 0.5;
  double cachedCoolingOffset = 0.0;

  DateTime? lastAiApplyHeating;
  DateTime? lastAiApplyCooling;

  int currentPage = 0;
  int? editingIndex;

  final GlobalKey chartKey = GlobalKey();

  BuildContext? _context;

  HomeNotifier({
    required double initialSlope,
    required double initialOffset,
    int initialPage = 0,
  }) {
    currentPage = initialPage;
    pageController = PageController(initialPage: currentPage);
    slope = initialSlope;
    offset = initialOffset;

    for (final room in RoomConstants.defaultRooms) {
      internalTempControllers[room] = TextEditingController();
      comfortRatings[room] = 'ok';
    }

    loadFromHive();
  }

  void attachContext(BuildContext context) {
    _context = context;
  }

  @override
  void dispose() {
    pageController.dispose();
    externalTempController.dispose();
    consumptionController.dispose();
    noteController.dispose();
    for (final c in internalTempControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> loadFromHive() async {
    final results = await Future.wait([
      AppStorage.loadRecords(),
      Future.value(AppStorage.getSystemMode()),
      Future.value(AppStorage.getSlope()),
      Future.value(AppStorage.getOffset()),
      Future.value(AppStorage.getCoolingSlope()),
      Future.value(AppStorage.getCoolingOffset()),
      Future.value(AppStorage.getLastAiApplyHeatingIso()),
      Future.value(AppStorage.getLastAiApplyCoolingIso()),
    ]);

    final storedRecords = results[0] as List<DailyRecordDTO>;
    final modeStr = results[1] as String? ?? 'heating';

    cachedHeatingSlope = results[2] as double;
    cachedHeatingOffset = results[3] as double;
    cachedCoolingSlope = results[4] as double;
    cachedCoolingOffset = results[5] as double;

    final heatIso = results[6] as String?;
    final coolIso = results[7] as String?;

    lastAiApplyHeating = heatIso != null ? DateTime.tryParse(heatIso) : null;
    lastAiApplyCooling = coolIso != null ? DateTime.tryParse(coolIso) : null;

    final loadedMode =
        modeStr == 'cooling' ? SystemMode.cooling : SystemMode.heating;

    allRecords = storedRecords;
    currentMode = loadedMode;

    if (currentMode == SystemMode.heating) {
      slope = cachedHeatingSlope;
      offset = cachedHeatingOffset;
    } else {
      slope = cachedCoolingSlope;
      offset = cachedCoolingOffset;
    }

    notifyListeners();
    updateSystemOverlay();
  }

  Future<void> saveToHive() async {
    await AppStorage.saveRecords(allRecords);
  }

  void updateSystemOverlay() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
  }

  void toggleMode(bool value) {
    final newMode = value ? SystemMode.cooling : SystemMode.heating;

    if (currentMode == SystemMode.heating) {
      cachedHeatingSlope = slope;
      cachedHeatingOffset = offset;
    } else {
      cachedCoolingSlope = slope;
      cachedCoolingOffset = offset;
    }

    currentMode = newMode;
    if (newMode == SystemMode.heating) {
      slope = cachedHeatingSlope;
      offset = cachedHeatingOffset;
    } else {
      slope = cachedCoolingSlope;
      offset = cachedCoolingOffset;
    }

    notifyListeners();
    updateSystemOverlay();

    Future.microtask(() async {
      await AppStorage.saveSystemMode(
        newMode == SystemMode.cooling ? 'cooling' : 'heating',
      );
      if (newMode == SystemMode.heating) {
        await AppStorage.saveCoolingSlope(cachedCoolingSlope);
        await AppStorage.saveCoolingOffset(cachedCoolingOffset);
      } else {
        await AppStorage.saveSlope(cachedHeatingSlope);
        await AppStorage.saveOffset(cachedHeatingOffset);
      }
    });
  }

  List<DailyRecordDTO> recordsSinceLastApply(SystemMode mode) {
    final last =
        mode == SystemMode.heating ? lastAiApplyHeating : lastAiApplyCooling;
    if (last == null) return List<DailyRecordDTO>.from(records);
    final lastDay = DateTime(last.year, last.month, last.day);
    return records.where((r) {
      final d = parseItalianDateSafe(r.dateIso);
      return d != null && d.isAfter(lastDay);
    }).toList();
  }

  void clearFields({bool preFillFromLast = false}) {
    editingIndex = null;
    externalTempController.clear();
    consumptionController.clear();
    noteController.clear();
    internalTempControllers.forEach((_, c) => c.clear());

    if (preFillFromLast && records.isNotEmpty) {
      final last = records.last;
      comfortRatings.clear();
      comfortRatings.addAll(last.comfortRatings);
    } else {
      comfortRatings.updateAll((k, v) => 'ok');
    }
    notifyListeners();
  }

  void startEditRecordByDateIso(String dateIso) {
    final modeStr = currentMode == SystemMode.cooling ? 'cooling' : 'heating';
    final index = allRecords.indexWhere(
        (r) => r.dateIso == dateIso && r.mode == modeStr);
    if (index == -1) return;
    startEditRecordByAllIndex(index);
  }

  void startEditRecord(int sortedIndex) {
    final filtered = records;
    if (sortedIndex < 0 || sortedIndex >= filtered.length) return;
    final targetDateIso = filtered[sortedIndex].dateIso;
    startEditRecordByDateIso(targetDateIso);
  }

  void startEditRecordByAllIndex(int allIndex) {
    if (allIndex < 0 || allIndex >= allRecords.length) return;
    final r = allRecords[allIndex];

    editingIndex = allIndex;
    externalTempController.text = r.externalTemp.toString();
    consumptionController.text = r.consumption.toString();
    noteController.text = r.note ?? '';

    r.internalTemps.forEach((room, value) {
      if (internalTempControllers.containsKey(room)) {
        internalTempControllers[room]!.text = value.toStringAsFixed(1);
      }
    });

    comfortRatings.clear();
    comfortRatings.addAll(r.comfortRatings);

    notifyListeners();
    currentPage = 0;
    pageController.jumpToPage(0);
  }

  Future<void> addRecord() async {
    final ctx = _context;
    if (externalTempController.text.isEmpty ||
        consumptionController.text.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Errore: Temperatura Esterna e Consumo sono obbligatori!',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    for (var entry in internalTempControllers.entries) {
      if (entry.value.text.trim().isEmpty) {
        Fluttertoast.showToast(
          msg: 'Errore: Manca la temperatura per ${entry.key}!',
          backgroundColor: Colors.red.shade600,
          textColor: Colors.white,
          fontSize: 14,
        );
        return;
      }
    }

    final double? extTemp =
        double.tryParse(externalTempController.text.replaceAll(',', '.'));
    final double? cons =
        double.tryParse(consumptionController.text.replaceAll(',', '.'));

    if (extTemp == null || cons == null) {
      Fluttertoast.showToast(
        msg: 'Valori numerici non validi',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    final Map<String, double> internalTemps = {};
    bool conversionError = false;

    internalTempControllers.forEach((room, controller) {
      final val = double.tryParse(controller.text.replaceAll(',', '.'));
      if (val != null) {
        internalTemps[room] = val;
      } else {
        conversionError = true;
      }
    });

    if (conversionError) {
      Fluttertoast.showToast(
        msg: 'Errore: Una delle temperature interne non è un numero valido.',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    final now = DateTime.now();
    final dateIso = formatItalianDate(now);
    final modeStr = currentMode == SystemMode.cooling ? 'cooling' : 'heating';

    if (editingIndex != null) {
      final originalDate = allRecords[editingIndex!].dateIso;
      final updatedRecord = DailyRecordDTO(
        dateIso: originalDate,
        externalTemp: extTemp,
        internalTemps: internalTemps,
        consumption: cons,
        comfortRatings: Map.from(comfortRatings),
        note: noteController.text,
        mode: modeStr,
      );

      allRecords[editingIndex!] = updatedRecord;
      editingIndex = null;
      notifyListeners();

      Fluttertoast.showToast(
        msg: 'Registrazione aggiornata!',
        backgroundColor: Colors.green.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    } else {
      final exists = allRecords.any(
          (r) => r.dateIso == dateIso && r.mode == modeStr);
      if (exists) {
        Fluttertoast.showToast(
          msg: 'Esiste già una registrazione per oggi. Modifica quella esistente.',
          backgroundColor: Colors.orange.shade600,
          textColor: Colors.white,
          fontSize: 14,
        );
        return;
      }

      final newRecord = DailyRecordDTO(
        dateIso: dateIso,
        externalTemp: extTemp,
        internalTemps: internalTemps,
        consumption: cons,
        comfortRatings: Map.from(comfortRatings),
        note: noteController.text,
        mode: modeStr,
      );

      allRecords.add(newRecord);
      notifyListeners();

      Fluttertoast.showToast(
        msg: 'Registrazione salvata!',
        backgroundColor: Colors.green.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    }

    await saveToHive();
    clearFields();
    if (ctx != null && ctx.mounted) {
      FocusScope.of(ctx).unfocus();
    }
  }

  Future<void> deleteRecord(int sortedIndex) async {
    final filtered = records;
    final sortedRecords = List<DailyRecordDTO>.from(filtered);
    sortedRecords.sort((a, b) {
      final da = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
      final db = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
      return db.compareTo(da);
    });

    if (sortedIndex >= 0 && sortedIndex < sortedRecords.length) {
      final targetDateIso = sortedRecords[sortedIndex].dateIso;
      final modeStr = currentMode == SystemMode.cooling ? 'cooling' : 'heating';
      final originalIndex = allRecords.indexWhere(
          (r) => r.dateIso == targetDateIso && r.mode == modeStr);

      if (originalIndex != -1) {
        allRecords.removeAt(originalIndex);
        if (editingIndex == originalIndex) editingIndex = null;
        notifyListeners();

        await saveToHive();

        Fluttertoast.showToast(
          msg: 'Registrazione eliminata',
          backgroundColor: Colors.red.shade600,
          textColor: Colors.white,
          fontSize: 14,
        );
      }
    }
  }

  Future<void> deleteToday() async {
    final today = formatItalianDate(DateTime.now());
    final modeStr = currentMode == SystemMode.cooling ? 'cooling' : 'heating';
    final index = allRecords.indexWhere(
        (r) => r.dateIso == today && r.mode == modeStr);

    if (index != -1) {
      allRecords.removeAt(index);
      if (editingIndex == index) editingIndex = null;
      notifyListeners();
      await saveToHive();
      Fluttertoast.showToast(
        msg: 'Registrazione eliminata',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    } else {
      Fluttertoast.showToast(
        msg: 'Nessuna registrazione trovata per oggi',
        backgroundColor: Colors.orange.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    }
  }

  void duplicateFromYesterday() {
    if (records.isEmpty) return;

    final sorted = List<DailyRecordDTO>.from(records);
    sorted.sort((a, b) {
      final dA = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
      final dB = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
      return dB.compareTo(dA);
    });

    if (sorted.isEmpty) return;

    final last = sorted.first;

    last.internalTemps.forEach((room, val) {
      if (internalTempControllers.containsKey(room)) {
        internalTempControllers[room]!.text = val.toStringAsFixed(1);
      }
    });

    comfortRatings.clear();
    comfortRatings.addAll(last.comfortRatings);
    notifyListeners();

    Fluttertoast.showToast(
      msg: "Dati copiati dall'ultima registrazione",
      backgroundColor: Colors.blue.shade600,
      textColor: Colors.white,
      fontSize: 14,
    );
  }

  void onApplyAiCurve() {
    final windowRecords = recordsSinceLastApply(currentMode);

    if (windowRecords.length < 5) {
      Fluttertoast.showToast(
        msg: 'Serve almeno 5 rilevamenti nuovi (${windowRecords.length}/5)',
        backgroundColor: Colors.orange.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    final suggestion =
        computeOptimalCurveSuggestion(windowRecords, slope, offset, currentMode);

    if ((suggestion.suggestedSlope - slope).abs() < 0.05 &&
        (suggestion.suggestedOffset - offset).abs() < 0.05) {
      Fluttertoast.showToast(
        msg: 'I valori suggeriti sono uguali a quelli attuali. Nessuna modifica necessaria.',
        backgroundColor: Colors.orange.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    final now = DateTime.now();
    final nowIso = now.toIso8601String();

    slope = suggestion.suggestedSlope;
    offset = suggestion.suggestedOffset;

    if (currentMode == SystemMode.heating) {
      lastAiApplyHeating = now;
      cachedHeatingSlope = slope;
      cachedHeatingOffset = offset;
    } else {
      lastAiApplyCooling = now;
      cachedCoolingSlope = slope;
      cachedCoolingOffset = offset;
    }
    notifyListeners();

    Future.microtask(() async {
      if (currentMode == SystemMode.heating) {
        await AppStorage.saveSlope(slope);
        await AppStorage.saveOffset(offset);
        await AppStorage.saveLastAiApplyHeatingIso(nowIso);
      } else {
        await AppStorage.saveCoolingSlope(slope);
        await AppStorage.saveCoolingOffset(offset);
        await AppStorage.saveLastAiApplyCoolingIso(nowIso);
      }
    });

    Fluttertoast.showToast(
      msg: 'Nuova curva AI applicata!',
      backgroundColor: Colors.indigo,
      textColor: Colors.white,
      fontSize: 14,
    );
  }

  Future<void> exportCsv() async {
    if (records.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Nessun dato da esportare!',
        backgroundColor: Colors.orange.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    try {
      final csv = ExportUtils.generateCsv(
        records,
        slope: slope,
        offset: offset,
        mode: currentMode,
      );

      final dateStr = DateTime.now().toIso8601String().split('T').first;
      await ExportUtils.shareCsv(
        csv,
        'ClimaSense_$dateStr.csv',
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Errore export CSV: $e',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    }
  }

  Future<void> exportPdf() async {
    if (records.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Nessun dato da esportare!',
        backgroundColor: Colors.orange.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    final int originalPage = currentPage;

    if (currentPage != 2) {
      currentPage = 2;
      notifyListeners();
      pageController.jumpToPage(2);
      await Future.delayed(const Duration(milliseconds: 800));
    }

    try {
      final chartImage = await captureChart();
      final finalImage = chartImage ?? await captureChart();

      final windowRecords = recordsSinceLastApply(currentMode);
      final suggestion =
          computeOptimalCurveSuggestion(windowRecords, slope, offset, currentMode);
      final stats = computeCurveStats(windowRecords);

      await ExportUtils.generateAndSavePdf(
        records: records,
        slope: slope,
        offset: offset,
        suggestion: suggestion,
        stats: stats,
        chartImage: finalImage,
        currentMode: currentMode,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Errore export PDF: $e',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    } finally {
      if (originalPage != 2) {
        currentPage = originalPage;
        notifyListeners();
        pageController.jumpToPage(originalPage);
      }
    }
  }

  Future<Uint8List?> captureChart() async {
    try {
      final RenderRepaintBoundary? boundary =
          chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> doBackup() async {
    try {
      final backupJson = ExportUtils.generateBackupJson(
        records: allRecords,
        mode: currentMode,
        heatingSlope: cachedHeatingSlope,
        heatingOffset: cachedHeatingOffset,
        coolingSlope: cachedCoolingSlope,
        coolingOffset: cachedCoolingOffset,
      );

      final date = DateTime.now().toIso8601String().split('T').first;
      await ExportUtils.shareBackupJsonString(
        backupJson,
        'ClimaSenseBackup_$date.json',
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Errore backup: $e',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    }
  }

  Future<void> doRestore(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();

      final backupData = jsonDecode(jsonString);

      if (backupData['metadata'] == null ||
          backupData['settings'] == null ||
          backupData['records'] == null) {
        throw Exception('File di backup non valido.');
      }

      if (!context.mounted) return;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conferma Ripristino'),
          content: const Text(
            'Sovrascriverà tutti i dati attuali. Continuare?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'CONFERMA',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      final settings = backupData['settings'] as Map<String, dynamic>;
      final recordsData = backupData['records'] as List;

      final newRecords =
          recordsData.map((j) => DailyRecordDTO.fromJson(j)).toList();

      await AppStorage.saveRecords(newRecords);

      final double heatingSlope =
          (settings['heatingSlope'] as num?)?.toDouble() ?? 1.2;
      final double heatingOffset =
          (settings['heatingOffset'] as num?)?.toDouble() ?? 0.0;
      final double coolingSlope =
          (settings['coolingSlope'] as num?)?.toDouble() ?? 0.5;
      final double coolingOffset =
          (settings['coolingOffset'] as num?)?.toDouble() ?? 0.0;

      await AppStorage.saveSlope(heatingSlope);
      await AppStorage.saveOffset(heatingOffset);
      await AppStorage.saveCoolingSlope(coolingSlope);
      await AppStorage.saveCoolingOffset(coolingOffset);

      await AppStorage.saveSystemMode('heating');

      await loadFromHive();

      Fluttertoast.showToast(
        msg: 'Ripristino completato!',
        backgroundColor: Colors.green.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Errore ripristino: $e',
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    }
  }

  Future<void> setNotificationTime(BuildContext context) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (!context.mounted) return;

    if (picked != null) {
      await AppStorage.saveNotificationTime(picked);
      await NotificationService.cancelAll();
      await NotificationService.scheduleDailyReminder();

      if (context.mounted) {
        Fluttertoast.showToast(
          msg: 'Notifica impostata alle ${picked.format(context)}',
          backgroundColor: Colors.blue.shade600,
          textColor: Colors.white,
          fontSize: 14,
        );
      }
    }
  }

  void onPageChanged(int index) {
    currentPage = index;
    notifyListeners();
  }

  void onNavDestinationSelected(int index) {
    pageController.jumpToPage(index);
  }
}
