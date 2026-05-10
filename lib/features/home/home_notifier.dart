import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/constants/room_constants.dart';
import '../../models/curve_settings.dart';
import '../../models/daily_record_dto.dart';
import '../../repositories/curve_settings_repository.dart';
import '../../services/hive_storage.dart';
import '../../services/notification_service.dart';
import '../../utils/app_toast.dart';
import '../../utils/date_utils.dart';

import 'logic/curve_logic.dart';
import 'logic/record_form_validator.dart';
import 'utils/export_utils.dart';
import 'widgets/rooms_manager_sheet.dart';

class HomeNotifier extends ChangeNotifier {
  final CurveSettingsRepository _settingsRepo = CurveSettingsRepository();

  late PageController pageController;

  final TextEditingController externalTempController = TextEditingController();
  final TextEditingController consumptionController = TextEditingController();
  final TextEditingController consumptionAcsController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController energyFromGridController = TextEditingController();
  final TextEditingController pvProductionController = TextEditingController();
  final ValueNotifier<String> heatpumpModeNotifier =
      ValueNotifier<String>('spenta');
  final ValueNotifier<String> boilerModeNotifier =
      ValueNotifier<String>('spenta');
  final Map<String, TextEditingController> internalTempControllers = {};
  final Map<String, String> comfortRatings = {};

  List<DailyRecordDTO> allRecords = [];
  CurveSettings _settings = CurveSettings.defaults();

  // F4 — storico AI in memoria (ricaricato da Hive al load)
  List<AiApplySnapshot> aiHistory = [];

  List<String> rooms = [];

  List<DailyRecordDTO> get records {
    return allRecords
        .where((r) => r.mode == currentMode.toModeString())
        .toList();
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
    pageController.dispose();
    externalTempController.dispose();
    consumptionController.dispose();
    consumptionAcsController.dispose();
    noteController.dispose();
    energyFromGridController.dispose();
    pvProductionController.dispose();
    heatpumpModeNotifier.dispose();
    boilerModeNotifier.dispose();
    for (final c in internalTempControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> loadFromHive() async {
    final storedRecords = await AppStorage.loadRecords();
    final loadedSettings = _settingsRepo.load();
    final loadedRooms = AppStorage.getRooms();

    allRecords = storedRecords;
    _settings = loadedSettings;
    aiHistory = AppStorage.getAiHistory(); // F4

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

  void updateSystemOverlay() {
    final themeMode = AppStorage.getThemeMode();
    final bool isDark;
    switch (themeMode) {
      case ThemeMode.dark:
        isDark = true;
        break;
      case ThemeMode.light:
        isDark = false;
        break;
      case ThemeMode.system:
        isDark = ui.PlatformDispatcher.instance.platformBrightness ==
            ui.Brightness.dark;
        break;
    }
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
    consumptionAcsController.clear();
    noteController.clear();
    energyFromGridController.clear();
    pvProductionController.clear();
    heatpumpModeNotifier.value = 'spenta';
    boilerModeNotifier.value = 'spenta';
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
    consumptionAcsController.text = r.consumptionACS?.toString() ?? '';
    noteController.text = r.note;
    energyFromGridController.text = r.energyFromGrid?.toString() ?? '';
    pvProductionController.text = r.pvProduction?.toString() ?? '';
    heatpumpModeNotifier.value = r.heatpumpMode ?? 'spenta';
    boilerModeNotifier.value = r.boilerMode ?? 'spenta';

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

  String? _buildContextualNotificationBody(CurveSuggestion suggestion) {
    final slopeDelta = suggestion.suggestedSlope - slope;
    final offsetDelta = suggestion.suggestedOffset - offset;
    final hasChange = slopeDelta.abs() >= 0.05 || offsetDelta.abs() >= 0.05;

    if (!hasChange) return null;

    if (suggestion.smartTip.isNotEmpty &&
        !suggestion.smartTip.toLowerCase().contains('apprendimento')) {
      return suggestion.smartTip;
    }

    final modeLabel =
        currentMode == SystemMode.heating ? 'riscaldamento' : 'raffrescamento';
    if (slopeDelta > 0) {
      return 'La curva di $modeLabel potrebbe essere incrementata. Valuta di applicare il suggerimento AI.';
    } else if (slopeDelta < 0) {
      return 'La curva di $modeLabel potrebbe essere ridotta. Valuta di applicare il suggerimento AI.';
    } else if (offsetDelta > 0) {
      return 'Offset $modeLabel in aumento suggerito. Controlla il grafico AI.';
    } else {
      return 'Offset $modeLabel in diminuzione suggerito. Controlla il grafico AI.';
    }
  }

  Future<void> addRecord(BuildContext context) async {
    final result = RecordFormValidator.validate(
      externalTempController: externalTempController,
      consumptionController: consumptionController,
      internalTempControllers: internalTempControllers,
    );

    if (result is RecordValidationError) {
      AppToast.show(
        result.message,
        context: context,
        level: ToastLevel.error,
      );
      return;
    }

    final ok = result as RecordValidationOk;
    final now = DateTime.now();
    final dateIso = formatItalianDate(now);
    final modeStr = currentMode.toModeString();
    final consumptionAcs =
        double.tryParse(consumptionAcsController.text.replaceAll(',', '.'));
    final energyFromGrid =
        double.tryParse(energyFromGridController.text.replaceAll(',', '.'));
    final pvProduction =
        double.tryParse(pvProductionController.text.replaceAll(',', '.'));

    if (editingIndex != null) {
      final originalDate = allRecords[editingIndex!].dateIso;
      final isToday = originalDate == dateIso;
      allRecords[editingIndex!] = DailyRecordDTO(
        dateIso: originalDate,
        externalTemp: ok.externalTemp,
        internalTemps: ok.internalTemps,
        consumption: ok.consumption,
        comfortRatings: Map.from(comfortRatings),
        note: noteController.text,
        mode: modeStr,
        heatpumpMode: heatpumpModeNotifier.value,
        consumptionACS: consumptionAcs,
        boilerMode: boilerModeNotifier.value,
        energyFromGrid: energyFromGrid,
        pvProduction: pvProduction,
      );
      editingIndex = null;
      notifyListeners();
      final label = isToday ? 'oggi' : originalDate;
      if (context.mounted) {
        AppToast.show(
          'Registrazione del $label aggiornata!',
          context: context,
          level: ToastLevel.success,
        );
      }
    } else {
      final exists =
          allRecords.any((r) => r.dateIso == dateIso && r.mode == modeStr);
      if (exists) {
        if (context.mounted) {
          AppToast.show(
            'Esiste già una registrazione per oggi. Modifica quella esistente.',
            context: context,
            level: ToastLevel.warning,
          );
        }
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
        heatpumpMode: heatpumpModeNotifier.value,
        consumptionACS: consumptionAcs,
        boilerMode: boilerModeNotifier.value,
        energyFromGrid: energyFromGrid,
        pvProduction: pvProduction,
      ));
      notifyListeners();
      if (context.mounted) {
        AppToast.show(
          'Registrazione salvata!',
          context: context,
          level: ToastLevel.success,
        );
      }
    }

    await saveToHive();
    clearFields();
    if (context.mounted) FocusScope.of(context).unfocus();

    try {
      final windowRecords = recordsSinceLastApply(currentMode);
      if (windowRecords.length >= 5) {
        final suggestion = computeOptimalCurveSuggestion(
            windowRecords, slope, offset, currentMode);
        final body = _buildContextualNotificationBody(suggestion);
        if (body != null) {
          await NotificationService.showContextualNotification(
            title: '🧠 ClimaSense AI',
            body: body,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> deleteRecordByDateIso(String dateIso) async {
    final modeStr = currentMode.toModeString();
    final index =
        allRecords.indexWhere((r) => r.dateIso == dateIso && r.mode == modeStr);
    if (index == -1) return;
    if (editingIndex == index) editingIndex = null;
    allRecords.removeAt(index);
    notifyListeners();
    await saveToHive();
  }

  Future<void> deleteToday(BuildContext context) async {
    final today = formatItalianDate(DateTime.now());
    final modeStr = currentMode.toModeString();
    final index =
        allRecords.indexWhere((r) => r.dateIso == today && r.mode == modeStr);
    if (index == -1) {
      AppToast.show(
        'Nessuna registrazione trovata per oggi',
        context: context,
        level: ToastLevel.warning,
      );
      return;
    }
    allRecords.removeAt(index);
    clearFields();
    await saveToHive();
    currentPage = 0;
    pageController.jumpToPage(0);
  }

  void duplicateFromYesterday(BuildContext context) {
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
    heatpumpModeNotifier.value = last.heatpumpMode ?? 'spenta';
    boilerModeNotifier.value = last.boilerMode ?? 'spenta';
    consumptionAcsController.text = last.consumptionACS?.toString() ?? '';
    energyFromGridController.text = last.energyFromGrid?.toString() ?? '';
    pvProductionController.text = last.pvProduction?.toString() ?? '';
    notifyListeners();

    AppToast.show(
      "Dati copiati dall'ultima registrazione",
      context: context,
      level: ToastLevel.info,
    );
  }

  /// F4 — Applica la curva AI salvando uno snapshot PRIMA di modificare.
  void onApplyAiCurve(BuildContext context) {
    final windowRecords = recordsSinceLastApply(currentMode);

    if (windowRecords.length < 5) {
      AppToast.show(
        'Serve almeno 5 rilevamenti nuovi (${windowRecords.length}/5)',
        context: context,
        level: ToastLevel.warning,
      );
      return;
    }

    final suggestion =
        computeOptimalCurveSuggestion(windowRecords, slope, offset, currentMode);

    if ((suggestion.suggestedSlope - slope).abs() < 0.05 &&
        (suggestion.suggestedOffset - offset).abs() < 0.05) {
      AppToast.show(
        'I valori suggeriti sono uguali a quelli attuali. Nessuna modifica necessaria.',
        context: context,
        level: ToastLevel.warning,
      );
      return;
    }

    // Salva snapshot dei valori ATTUALI (prima dell'apply) per poter fare undo
    final snapshot = AiApplySnapshot(
      slope: slope,
      offset: offset,
      mode: currentMode.toModeString(),
      appliedAt: DateTime.now().toIso8601String(),
      smartTip: suggestion.smartTip,
    );
    AppStorage.addAiSnapshot(snapshot);
    aiHistory = AppStorage.getAiHistory();

    final nowApply = DateTime.now();
    _settings = currentMode == SystemMode.heating
        ? _settings.copyWith(
            heatingSlope: suggestion.suggestedSlope,
            heatingOffset: suggestion.suggestedOffset,
            lastAiApplyHeating: nowApply,
          )
        : _settings.copyWith(
            coolingSlope: suggestion.suggestedSlope,
            coolingOffset: suggestion.suggestedOffset,
            lastAiApplyCooling: nowApply,
          );

    notifyListeners();
    Future.microtask(_saveSettings);

    AppToast.show(
      'Nuova curva AI applicata!',
      context: context,
      level: ToastLevel.success,
    );
  }

  /// F4 — Ripristina i parametri dell'ultimo snapshot AI (undo).
  Future<void> undoLastAiApply(BuildContext context) async {
    final snapshot = await AppStorage.popLastAiSnapshot();
    if (snapshot == null) {
      AppToast.show(
        'Nessun apply AI da annullare.',
        context: context,
        level: ToastLevel.warning,
      );
      return;
    }

    final isHeating = snapshot.mode == 'heating';
    _settings = isHeating
        ? _settings.copyWith(
            heatingSlope: snapshot.slope,
            heatingOffset: snapshot.offset,
          )
        : _settings.copyWith(
            coolingSlope: snapshot.slope,
            coolingOffset: snapshot.offset,
          );

    aiHistory = AppStorage.getAiHistory();
    notifyListeners();
    await _saveSettings();

    final modeLabel = isHeating ? 'riscaldamento' : 'raffrescamento';
    if (context.mounted) {
      AppToast.show(
        'Ripristinata curva $modeLabel: S ${snapshot.slope.toStringAsFixed(2)} / O ${snapshot.offset.toStringAsFixed(1)}',
        context: context,
        level: ToastLevel.info,
      );
    }
  }

  Future<void> exportCsv(BuildContext context) async {
    if (records.isEmpty) {
      AppToast.show(
        'Nessun dato da esportare!',
        context: context,
        level: ToastLevel.warning,
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
      if (context.mounted) {
        AppToast.show(
          'Errore export CSV: $e',
          context: context,
          level: ToastLevel.error,
        );
      }
    }
  }

  Future<void> exportPdf(BuildContext context) async {
    if (records.isEmpty) {
      AppToast.show(
        'Nessun dato da esportare!',
        context: context,
        level: ToastLevel.warning,
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
      if (context.mounted) {
        AppToast.show(
          'Errore export PDF: $e',
          context: context,
          level: ToastLevel.error,
        );
      }
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

  Future<void> doBackup(BuildContext context) async {
    try {
      final backupJson = await ExportUtils.generateBackupJson(
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
      if (context.mounted) {
        AppToast.show(
          'Errore backup: $e',
          context: context,
          level: ToastLevel.error,
        );
      }
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
      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Il file non è un oggetto JSON valido.');
      }
      final backupData = decoded;

      if (backupData['metadata'] == null) {
        throw const FormatException('Campo "metadata" mancante nel backup.');
      }
      if (backupData['settings'] is! Map) {
        throw const FormatException('Campo "settings" mancante o non valido nel backup.');
      }
      if (backupData['records'] is! List) {
        throw const FormatException('Campo "records" mancante o non è una lista nel backup.');
      }

      if (!context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conferma Ripristino'),
          content: const Text('Sovrascriverà tutti i dati attuali. Continuare?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('CONFERMA', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      final settings = backupData['settings'] as Map<String, dynamic>;
      final newRecords = (backupData['records'] as List)
          .map((j) => DailyRecordDTO.fromJson(j as Map<String, dynamic>))
          .toList();

      final modeStr = settings['mode'] as String? ?? 'heating';
      final restoredMode = modeStr == 'cooling'
          ? SystemMode.cooling
          : SystemMode.heating;

      await AppStorage.saveRecords(newRecords);
      await _settingsRepo.save(CurveSettings(
        heatingSlope: (settings['heatingSlope'] as num?)?.toDouble() ?? 1.0,
        heatingOffset: (settings['heatingOffset'] as num?)?.toDouble() ?? 0.0,
        coolingSlope: (settings['coolingSlope'] as num?)?.toDouble() ?? 0.5,
        coolingOffset: (settings['coolingOffset'] as num?)?.toDouble() ?? 0.0,
        mode: restoredMode,
      ));

      await loadFromHive();

      if (context.mounted) {
        AppToast.show(
          'Ripristino completato!',
          context: context,
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(
          'Errore ripristino: $e',
          context: context,
          level: ToastLevel.error,
        );
      }
    }
  }

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
      AppToast.show(
        'Notifica impostata alle ${picked.format(context)}',
        context: context,
        level: ToastLevel.info,
      );
    }
  }

  void onPageChanged(int index) {
    currentPage = index;
    notifyListeners();
  }

  void onNavDestinationSelected(int index) {
    pageController.jumpToPage(index);
  }

  Future<void> resetCalibration() async {
    await _settingsRepo.reset();
    await loadFromHive();
  }
}
