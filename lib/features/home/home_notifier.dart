// lib/features/home/home_notifier.dart
//
// Refactor #8 — HomeNotifier riscritto come orchestratore:
//   • Delega export      → ExportService
//   • Delega AI curve    → AiCurveService
//   • Mantiene: stato UI, CRUD records, controllers, rooms
//   • Firma pubblica invariata: nessun consumer cambia
//   + vmcModeNotifier aggiunto per tile VMC
// + cancelEdit(): esce dalla modifica senza salvare
// fix: clearFields() prima di notifyListeners() nel ramo editing di addRecord

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/room_constants.dart';
import '../../models/curve_settings.dart';
import '../../models/daily_record_dto.dart';
import '../../repositories/curve_settings_repository.dart';
import '../../services/hive_storage.dart';
import '../../services/notification_service.dart';
import '../../utils/app_toast.dart';
import '../../utils/date_utils.dart';

import 'logic/ai_curve_service.dart';
import 'logic/curve_logic.dart';
import 'logic/export_service.dart';
import 'logic/record_form_validator.dart';
import 'widgets/rooms_manager_sheet.dart';

class HomeNotifier extends ChangeNotifier {
  final CurveSettingsRepository _settingsRepo = CurveSettingsRepository();
  late final ExportService _exportService;
  final AiCurveService _aiService = const AiCurveService();

  late PageController pageController;

  final TextEditingController externalTempController = TextEditingController();
  final TextEditingController consumptionController = TextEditingController();
  final TextEditingController consumptionAcsController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController energyFromGridController = TextEditingController();
  final TextEditingController pvProductionController = TextEditingController();
  final ValueNotifier<String> heatpumpModeNotifier = ValueNotifier<String>('spenta');
  final ValueNotifier<String> boilerModeNotifier = ValueNotifier<String>('spenta');
  final ValueNotifier<String> vmcModeNotifier = ValueNotifier<String>('spenta');
  final Map<String, TextEditingController> internalTempControllers = {};
  final Map<String, String> comfortRatings = {};

  List<DailyRecordDTO> allRecords = [];
  CurveSettings _settings = CurveSettings.defaults();

  List<AiApplySnapshot> aiHistory = [];
  List<String> rooms = [];

  // -------------------------------------------------------------------------
  // Getters
  // -------------------------------------------------------------------------

  List<DailyRecordDTO> get records => allRecords
      .where((r) => r.mode == currentMode.toModeString())
      .toList();

  double get slope => _settings.activeSlope;
  double get offset => _settings.activeOffset;
  SystemMode get currentMode => _settings.mode;
  DateTime? get lastAiApplyHeating => _settings.lastAiApplyHeating;
  DateTime? get lastAiApplyCooling => _settings.lastAiApplyCooling;

  int currentPage = 0;
  int? editingIndex;

  final GlobalKey chartKey = GlobalKey();

  // -------------------------------------------------------------------------
  // Costruttore
  // -------------------------------------------------------------------------

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
    _exportService = ExportService(
      settingsRepo: _settingsRepo,
      chartKey: chartKey,
    );

    for (final room in RoomConstants.defaultRooms) {
      internalTempControllers[room] = TextEditingController();
      comfortRatings[room] = 'ok';
    }

    loadFromHive();
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

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
    vmcModeNotifier.dispose();
    for (final c in internalTempControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Hive load / save
  // -------------------------------------------------------------------------

  Future<void> loadFromHive() async {
    final storedRecords = await AppStorage.loadRecords();
    final loadedSettings = _settingsRepo.load();
    final loadedRooms = AppStorage.getRooms();

    allRecords = storedRecords;
    _settings = loadedSettings;
    aiHistory = AppStorage.getAiHistory();

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

  // -------------------------------------------------------------------------
  // UI helpers
  // -------------------------------------------------------------------------

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
      case ThemeMode.light:
        isDark = false;
      case ThemeMode.system:
        isDark =
            ui.PlatformDispatcher.instance.platformBrightness == ui.Brightness.dark;
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
    _settings = _settings.mode == SystemMode.heating
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
    notifyListeners();
    updateSystemOverlay();
    Future.microtask(_saveSettings);
  }

  void onPageChanged(int index) {
    currentPage = index;
    notifyListeners();
  }

  void onNavDestinationSelected(int index) {
    pageController.jumpToPage(index);
  }

  // -------------------------------------------------------------------------
  // Record helpers
  // -------------------------------------------------------------------------

  List<DailyRecordDTO> recordsSinceLastApply(SystemMode mode) {
    final last = mode == SystemMode.heating
        ? _settings.lastAiApplyHeating
        : _settings.lastAiApplyCooling;
    return AiCurveService.recordsSinceLastApply(
      records: records,
      lastApply: last,
    );
  }

  /// Esce dalla modalità modifica senza salvare nulla.
  void cancelEdit() {
    if (editingIndex == null) return;
    clearFields();
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
    vmcModeNotifier.value = 'spenta';
    internalTempControllers.forEach((_, c) => c.clear());

    if (preFillFromLast && records.isNotEmpty) {
      comfortRatings
        ..clear()
        ..addAll(records.last.comfortRatings);
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
    vmcModeNotifier.value = r.vmcMode ?? 'spenta';
    r.internalTemps.forEach((room, value) {
      if (internalTempControllers.containsKey(room)) {
        internalTempControllers[room]!.text = value.toStringAsFixed(1);
      }
    });
    comfortRatings
      ..clear()
      ..addAll(r.comfortRatings);
    notifyListeners();
    currentPage = 0;
    pageController.jumpToPage(0);
  }

  // -------------------------------------------------------------------------
  // CRUD records
  // -------------------------------------------------------------------------

  Future<void> addRecord(BuildContext context) async {
    final result = RecordFormValidator.validate(
      externalTempController: externalTempController,
      consumptionController: consumptionController,
      internalTempControllers: internalTempControllers,
    );

    if (result is RecordValidationError) {
      AppToast.show(result.message, context: context, level: ToastLevel.error);
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
        vmcMode: vmcModeNotifier.value,
      );
      // IMPORTANTE: clearFields() PRIMA di notifyListeners() così quando
      // didUpdateWidget scatta (isEditing: true→false) i controller sono
      // già vuoti e il re-fetch meteo trova la tile Esterna a '--'.
      clearFields();
      final label = isToday ? 'oggi' : originalDate;
      if (context.mounted) {
        AppToast.show('Registrazione del $label aggiornata!',
            context: context, level: ToastLevel.success);
      }
    } else {
      final exists = allRecords
          .any((r) => r.dateIso == dateIso && r.mode == modeStr);
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
        vmcMode: vmcModeNotifier.value,
      ));
      notifyListeners();
      if (context.mounted) {
        AppToast.show('Registrazione salvata!',
            context: context, level: ToastLevel.success);
      }
    }

    await saveToHive();
    if (context.mounted) FocusScope.of(context).unfocus();

    await _aiService.maybeShowNotification(
      windowRecords: recordsSinceLastApply(currentMode),
      slope: slope,
      offset: offset,
      mode: currentMode,
    );
  }

  Future<void> deleteRecordByDateIso(String dateIso) async {
    final modeStr = currentMode.toModeString();
    final index = allRecords
        .indexWhere((r) => r.dateIso == dateIso && r.mode == modeStr);
    if (index == -1) return;
    if (editingIndex == index) editingIndex = null;
    allRecords.removeAt(index);
    notifyListeners();
    await saveToHive();
  }

  Future<void> deleteToday(BuildContext context) async {
    final today = formatItalianDate(DateTime.now());
    final modeStr = currentMode.toModeString();
    final index = allRecords
        .indexWhere((r) => r.dateIso == today && r.mode == modeStr);
    if (index == -1) {
      AppToast.show('Nessuna registrazione trovata per oggi',
          context: context, level: ToastLevel.warning);
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
    consumptionController.text = last.consumption.toString();
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
    vmcModeNotifier.value = last.vmcMode ?? 'spenta';
    consumptionAcsController.text = last.consumptionACS?.toString() ?? '';
    energyFromGridController.text = last.energyFromGrid?.toString() ?? '';
    pvProductionController.text = last.pvProduction?.toString() ?? '';
    notifyListeners();
    AppToast.show("Dati copiati dall'ultima registrazione",
        context: context, level: ToastLevel.info);
  }

  // -------------------------------------------------------------------------
  // AI curve — delega ad AiCurveService
  // -------------------------------------------------------------------------

  Future<void> onApplyAiCurve(BuildContext context) async {
    final result = await _aiService.applyAiCurve(
      context,
      windowRecords: recordsSinceLastApply(currentMode),
      currentSlope: slope,
      currentOffset: offset,
      currentSettings: _settings,
      mode: currentMode,
    );
    if (result is AiApplySuccess) {
      AppStorage.addAiSnapshot(result.snapshot);
      _settings = result.newSettings;
      aiHistory = AppStorage.getAiHistory();
      notifyListeners();
      Future.microtask(_saveSettings);
    }
  }

  Future<void> undoLastAiApply(BuildContext context) async {
    final result = await _aiService.undoLastApply(
      context,
      currentSettings: _settings,
    );
    if (result is AiUndoSuccess) {
      _settings = result.newSettings;
      aiHistory = AppStorage.getAiHistory();
      notifyListeners();
      await _saveSettings();
    }
  }

  // -------------------------------------------------------------------------
  // Export — delega ad ExportService
  // -------------------------------------------------------------------------

  Future<Uint8List?> captureChart() => _exportService.captureChart();

  Future<void> exportCsv(BuildContext context) => _exportService.exportCsv(
        context,
        records: records,
        slope: slope,
        offset: offset,
        mode: currentMode,
      );

  Future<void> exportPdf(BuildContext context) => _exportService.exportPdf(
        context,
        records: records,
        windowRecords: recordsSinceLastApply(currentMode),
        slope: slope,
        offset: offset,
        mode: currentMode,
        currentPage: currentPage,
        onSwitchToChartPage: () async {
          currentPage = 2;
          notifyListeners();
          pageController.jumpToPage(2);
          await Future.delayed(const Duration(milliseconds: 800));
        },
        onRestorePage: () async {},
      );

  Future<void> doBackup(BuildContext context) => _exportService.doBackup(
        context,
        allRecords: allRecords,
        mode: currentMode,
        heatingSlope: _settings.heatingSlope,
        heatingOffset: _settings.heatingOffset,
        coolingSlope: _settings.coolingSlope,
        coolingOffset: _settings.coolingOffset,
      );

  Future<void> doRestore(BuildContext context) async {
    final data = await _exportService.doRestore(context);
    if (data == null) return;
    await AppStorage.saveRecords(data.records);
    await _settingsRepo.save(data.settings);
    await loadFromHive();
    if (context.mounted) {
      AppToast.show('Ripristino completato!',
          context: context, level: ToastLevel.success);
    }
  }

  // -------------------------------------------------------------------------
  // Notifiche e impostazioni
  // -------------------------------------------------------------------------

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
      AppToast.show('Notifica impostata alle ${picked.format(context)}',
          context: context, level: ToastLevel.info);
    }
  }

  Future<void> resetCalibration() async {
    await _settingsRepo.reset();
    await loadFromHive();
  }
}
