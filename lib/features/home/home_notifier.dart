import 'dart:async';
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
import '../../models/curve_settings.dart';
import '../../models/daily_record_dto.dart';
import '../../repositories/curve_settings_repository.dart';
import '../../services/hive_storage.dart';
import '../../services/notification_service.dart';
import '../../utils/date_utils.dart';
import '../initial_settings/initial_settings_home.dart';

import 'logic/curve_logic.dart';
import 'logic/record_form_validator.dart';
import 'utils/export_utils.dart';
import 'widgets/rooms_manager_sheet.dart';

class HomeNotifier extends ChangeNotifier {
  final CurveSettingsRepository _settingsRepo = CurveSettingsRepository();

  late PageController pageController;

  final TextEditingController externalTempController = TextEditingController();
  final TextEditingController consumptionController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final Map<String, TextEditingController> internalTempControllers = {};
  final Map<String, String> comfortRatings = {};

  List<DailyRecordDTO> allRecords = [];
  CurveSettings _settings = CurveSettings.defaults();

  List<String> rooms = [];

  // --- Undo delete ---
  DailyRecordDTO? _pendingDeleteRecord;
  int? _pendingDeleteIndex;
  Timer? _deleteTimer;

  List<DailyRecordDTO> get records {
    return allRecords.where((r) => r.mode == currentMode.toModeString()).toList();
  }

  double get slope => _settings.activeSlope;
  double get offset => _settings.activeOffset;
  SystemMode get currentMode => _settings.mode;
  DateTime? get lastAiApplyHeating => _settings.lastAiApplyHeating;
  DateTime? get lastAiApplyCooling => _settings.lastAiApplyCooling;

  int currentPage = 0;
  int? editingIndex;

  final GlobalKey chartKey = GlobalKey();

  HomeNotifier({
    required double initialSlope,
    required double initialOffset,
    int initialPage = 0,
  }) {
    currentPage = initialPage;
    pageController = PageController(initialPage: currentPage);
    _settings = CurveSettings.defaults().copyWith(
      heatingSlope: initialSlope,
      heatingOffset: initialOffset,
    );

    for (final room in RoomConstants.defaultRooms) {
      internalTempControllers[room] = TextEditingController();
      comfortRatings[room] = 'ok';
    }

    loadFromHive();
  }

  @override
  void dispose() {
    _deleteTimer?.cancel();
    pageController.dispose();
    externalTempController.dispose();
    consumptionController.dispose();
    noteController.dispose();
    for (final c in internalTempControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PERSISTENZA
  // ---------------------------------------------------------------------------

  Future<void> loadFromHive() async {
    final storedRecords = await AppStorage.loadRecords();
    final loadedSettings = _settingsRepo.load();
    final loadedRooms = AppStorage.getRooms();

    allRecords = storedRecords;
    _settings = loadedSettings;

    _syncRoomControllers(loadedRooms);

    notifyListeners();
    updateSystemOverlay();
  }

  void _syncRoomControllers(List<String> newRooms) {
    rooms = newRooms;

    for (final room in newRooms) {
      internalTempControllers.putIfAbsent(room, () => TextEditingController());
      comfortRatings.putIfAbsent(room, () => 'ok');
    }

    final toRemove = internalTempControllers.keys
        .where((k) => !newRooms.contains(k))
        .toList();
    for (final k in toRemove) {
      internalTempControllers[k]?.dispose();
      internalTempControllers.remove(k);
      comfortRatings.remove(k);
    }
  }

  Future<void> saveToHive() async {
    await AppStorage.saveRecords(allRecords);
  }

  Future<void> _saveSettings() => _settingsRepo.save(_settings);

  // ---------------------------------------------------------------------------
  // GESTIONE STANZE
  // ---------------------------------------------------------------------------

  Future<void> manageRooms(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RoomsManagerSheet(initialRooms: List.from(rooms)),
    );
    final updated = AppStorage.getRooms();
    _syncRoomControllers(updated);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SISTEMA
  // ---------------------------------------------------------------------------

  void updateSystemOverlay() {
    final themeMode = AppStorage.getThemeMode();
    final bool isDark = themeMode == ThemeMode.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  void toggleMode(bool value) {
    final newMode = value ? SystemMode.cooling : SystemMode.heating;

    final updated = _settings.mode == SystemMode.heating
        ? _settings.copyWith(
            heatingSlope: slope,
            heatingOffset: offset,
            mode: newMode,
          )
        : _settings.copyWith(
            coolingSlope: slope,
            coolingOffset: offset,
            mode: newMode,
          );

    _settings = updated;
    notifyListeners();
    updateSystemOverlay();
    Future.microtask(_saveSettings);
  }

  // ---------------------------------------------------------------------------
  // RECORDS
  // ---------------------------------------------------------------------------

  List<DailyRecordDTO> recordsSinceLastApply(SystemMode mode) {
    final last = mode == SystemMode.heating
        ? _settings.lastAiApplyHeating
        : _settings.lastAiApplyCooling;
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
    final index = allRecords.indexWhere(
        (r) => r.dateIso == dateIso && r.mode == currentMode.toModeString());
    if (index == -1) return;
    startEditRecordByAllIndex(index);
  }

  void startEditRecord(int sortedIndex) {
    final filtered = records;
    if (sortedIndex < 0 || sortedIndex >= filtered.length) return;
    startEditRecordByDateIso(filtered[sortedIndex].dateIso);
  }

  void startEditRecordByAllIndex(int allIndex) {
    if (allIndex < 0 || allIndex >= allRecords.length) return;
    final r = allRecords[allIndex];

    editingIndex = allIndex;
    externalTempController.text = r.externalTemp.toString();
    consumptionController.text = r.consumption.toString();
    noteController.text = r.note;

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

  Future<void> addRecord(BuildContext context) async {
    final result = RecordFormValidator.validate(
      externalTempController: externalTempController,
      consumptionController: consumptionController,
      internalTempControllers: internalTempControllers,
    );

    if (result is RecordValidationError) {
      Fluttertoast.showToast(
        msg: result.message,
        backgroundColor: Colors.red.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return;
    }

    final ok = result as RecordValidationOk;
    final now = DateTime.now();
    final dateIso = formatItalianDate(now);
    final modeStr = currentMode.toModeString();

    if (editingIndex != null) {
      final originalDate = allRecords[editingIndex!].dateIso;
      allRecords[editingIndex!] = DailyRecordDTO(
        dateIso: originalDate,
        externalTemp: ok.externalTemp,
        internalTemps: ok.internalTemps,
        consumption: ok.consumption,
        comfortRatings: Map.from(comfortRatings),
        note: noteController.text,
        mode: modeStr,
      );
      editingIndex = null;
      notifyListeners();
      Fluttertoast.showToast(
        msg: 'Registrazione aggiornata!',
        backgroundColor: Colors.green.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
    } else {
      final exists =
          allRecords.any((r) => r.dateIso == dateIso && r.mode == modeStr);
      if (exists) {
        Fluttertoast.showToast(
          msg: 'Esiste gi\u00e0 una registrazione per oggi. Modifica quella esistente.',
          backgroundColor: Colors.orange.shade600,
          textColor: Colors.white,
          fontSize: 14,
        );
        return;
      }

      allRecords.add(DailyRecordDTO(
        dateIso: dateIso,
        externalTemp: ok.externalTemp,
        internalTemps: ok.internalTemps,
        consumption: ok.consumption,
        comfortRatings: Map.from(comfortRatings),
        note: noteController.text,
        mode: modeStr,
      ));
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
    if (context.mounted) FocusScope.of(context).unfocus();
  }

  // ---------------------------------------------------------------------------
  // DELETE CON UNDO
  // ---------------------------------------------------------------------------

  /// Rimuove subito dalla UI, aspetta 5s prima di salvare su Hive.
  /// Restituisce il record eliminato (usato dalla view per la SnackBar).
  DailyRecordDTO? softDeleteRecord(int sortedIndex) {
    // Annulla eventuale delete pendente precedente (conferma immediata)
    _commitPendingDelete();

    final sortedRecords = List<DailyRecordDTO>.from(records)
      ..sort((a, b) {
        final da = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
        final db = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
        return db.compareTo(da);
      });

    if (sortedIndex < 0 || sortedIndex >= sortedRecords.length) return null;

    final targetDateIso = sortedRecords[sortedIndex].dateIso;
    final modeStr = currentMode.toModeString();
    final originalIndex = allRecords
        .indexWhere((r) => r.dateIso == targetDateIso && r.mode == modeStr);

    if (originalIndex == -1) return null;

    _pendingDeleteRecord = allRecords[originalIndex];
    _pendingDeleteIndex = originalIndex;

    allRecords.removeAt(originalIndex);
    if (editingIndex == originalIndex) editingIndex = null;
    notifyListeners();

    _deleteTimer = Timer(const Duration(seconds: 5), () {
      _pendingDeleteRecord = null;
      _pendingDeleteIndex = null;
      saveToHive();
    });

    return _pendingDeleteRecord;
  }

  /// Rimuove oggi (soft delete con undo).
  DailyRecordDTO? softDeleteToday() {
    _commitPendingDelete();

    final today = formatItalianDate(DateTime.now());
    final modeStr = currentMode.toModeString();
    final index =
        allRecords.indexWhere((r) => r.dateIso == today && r.mode == modeStr);

    if (index == -1) {
      Fluttertoast.showToast(
        msg: 'Nessuna registrazione trovata per oggi',
        backgroundColor: Colors.orange.shade600,
        textColor: Colors.white,
        fontSize: 14,
      );
      return null;
    }

    _pendingDeleteRecord = allRecords[index];
    _pendingDeleteIndex = index;

    allRecords.removeAt(index);
    if (editingIndex == index) editingIndex = null;
    notifyListeners();

    _deleteTimer = Timer(const Duration(seconds: 5), () {
      _pendingDeleteRecord = null;
      _pendingDeleteIndex = null;
      saveToHive();
    });

    return _pendingDeleteRecord;
  }

  /// Annulla l'ultima eliminazione pendente.
  void undoDelete() {
    if (_pendingDeleteRecord == null || _pendingDeleteIndex == null) return;
    _deleteTimer?.cancel();
    _deleteTimer = null;

    final idx = _pendingDeleteIndex!.clamp(0, allRecords.length);
    allRecords.insert(idx, _pendingDeleteRecord!);
    _pendingDeleteRecord = null;
    _pendingDeleteIndex = null;
    notifyListeners();
  }

  /// Conferma immediatamente l'eliminazione pendente (salva su Hive subito).
  void _commitPendingDelete() {
    if (_pendingDeleteRecord == null) return;
    _deleteTimer?.cancel();
    _deleteTimer = null;
    _pendingDeleteRecord = null;
    _pendingDeleteIndex = null;
    saveToHive();
  }

  // Mantenuti per retrocompatibilità con eventuali altri chiamanti
  Future<void> deleteRecord(int sortedIndex) async {
    softDeleteRecord(sortedIndex);
  }

  Future<void> deleteToday() async {
    softDeleteToday();
  }

  void duplicateFromYesterday() {
    if (records.isEmpty) return;

    final last = (List<DailyRecordDTO>.from(records)
          ..sort((a, b) {
            final dA = parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
            final dB = parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
            return dB.compareTo(dA);
          }))
        .first;

    last.internalTemps.forEach((room, val) {
      if (internalTempControllers.containsKey(room)) {
        internalTempControllers[room]!.text = val.toStringAsFixed(1);
      }
    });

    comfortRatings
      ..clear()
      ..addAll(last.comfortRatings);
    notifyListeners();

    Fluttertoast.showToast(
      msg: "Dati copiati dall'ultima registrazione",
      backgroundColor: Colors.blue.shade600,
      textColor: Colors.white,
      fontSize: 14,
    );
  }

  // ---------------------------------------------------------------------------
  // AI CURVE
  // ---------------------------------------------------------------------------

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

    _settings = currentMode == SystemMode.heating
        ? _settings.copyWith(
            heatingSlope: suggestion.suggestedSlope,
            heatingOffset: suggestion.suggestedOffset,
            lastAiApplyHeating: now,
          )
        : _settings.copyWith(
            coolingSlope: suggestion.suggestedSlope,
            coolingOffset: suggestion.suggestedOffset,
            lastAiApplyCooling: now,
          );

    notifyListeners();
    Future.microtask(_saveSettings);

    Fluttertoast.showToast(
      msg: 'Nuova curva AI applicata!',
      backgroundColor: Colors.indigo,
      textColor: Colors.white,
      fontSize: 14,
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT
  // ---------------------------------------------------------------------------

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
      await ExportUtils.shareCsv(csv, 'ClimaSense_$dateStr.csv');
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
      final chartImage = await captureChart() ?? await captureChart();
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
        chartImage: chartImage,
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
      final boundary = chartKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // BACKUP / RESTORE
  // ---------------------------------------------------------------------------

  Future<void> doBackup() async {
    try {
      final backupJson = ExportUtils.generateBackupJson(
        records: allRecords,
        mode: currentMode,
        heatingSlope: _settings.heatingSlope,
        heatingOffset: _settings.heatingOffset,
        coolingSlope: _settings.coolingSlope,
        coolingOffset: _settings.coolingOffset,
      );
      final date = DateTime.now().toIso8601String().split('T').first;
      await ExportUtils.shareBackupJsonString(
          backupJson, 'ClimaSenseBackup_$date.json');
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

      final jsonString = await File(result.files.single.path!).readAsString();
      final backupData = jsonDecode(jsonString);

      if (backupData['metadata'] == null ||
          backupData['settings'] == null ||
          backupData['records'] == null) {
        throw Exception('File di backup non valido.');
      }

      if (!context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conferma Ripristino'),
          content: const Text('Sovrascriver\u00e0 tutti i dati attuali. Continuare?'),
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

      if (confirmed != true || !context.mounted) return;

      final settings = backupData['settings'] as Map<String, dynamic>;
      final newRecords = (backupData['records'] as List)
          .map((j) => DailyRecordDTO.fromJson(j))
          .toList();

      await AppStorage.saveRecords(newRecords);
      await _settingsRepo.save(CurveSettings(
        heatingSlope: (settings['heatingSlope'] as num?)?.toDouble() ?? 1.2,
        heatingOffset: (settings['heatingOffset'] as num?)?.toDouble() ?? 0.0,
        coolingSlope: (settings['coolingSlope'] as num?)?.toDouble() ?? 0.5,
        coolingOffset: (settings['coolingOffset'] as num?)?.toDouble() ?? 0.0,
        mode: SystemMode.heating,
      ));

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

  // ---------------------------------------------------------------------------
  // NOTIFICHE
  // ---------------------------------------------------------------------------

  Future<void> setNotificationTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (!context.mounted || picked == null) return;

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

  // ---------------------------------------------------------------------------
  // NAVIGAZIONE
  // ---------------------------------------------------------------------------

  void onPageChanged(int index) {
    currentPage = index;
    notifyListeners();
  }

  void onNavDestinationSelected(int index) {
    pageController.jumpToPage(index);
  }

  // ---------------------------------------------------------------------------
  // RESET CALIBRAZIONE
  // ---------------------------------------------------------------------------

  Future<void> resetCalibration() async {
    await _settingsRepo.reset();
    await loadFromHive();
  }
}
