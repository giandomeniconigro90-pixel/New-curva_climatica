import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

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

  // ─────────────────────────────────────────────────────────────
  // F6 — Dialogo selezione range date prima dell'export
  // ─────────────────────────────────────────────────────────────

  /// Mostra il bottom-sheet di selezione range e restituisce
  /// la lista filtrata, oppure null se l'utente annulla.
  Future<List<DailyRecordDTO>?> _showExportRangeSheet(
      BuildContext context) async {
    if (records.isEmpty) return null;

    // Calcola min/max dei record disponibili
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

    final result = await showModalBottomSheet<List<DailyRecordDTO>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExportRangeSheet(
        records: records,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
    return result;
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

    // F6 — selezione range
    final filtered = await _showExportRangeSheet(context);
    if (filtered == null || !context.mounted) return;

    try {
      final csv = ExportUtils.generateCsv(
        filtered,
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

    // F6 — selezione range
    final filtered = await _showExportRangeSheet(context);
    if (filtered == null || !context.mounted) return;

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
        records: filtered,
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

// ─────────────────────────────────────────────────────────────────────────────
// F6 — Widget bottom-sheet selezione range per export
// ─────────────────────────────────────────────────────────────────────────────

class _ExportRangeSheet extends StatefulWidget {
  final List<DailyRecordDTO> records;
  final DateTime firstDate;
  final DateTime lastDate;

  const _ExportRangeSheet({
    required this.records,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_ExportRangeSheet> createState() => _ExportRangeSheetState();
}

class _ExportRangeSheetState extends State<_ExportRangeSheet> {
  // 0 = tutti, 1 = ultimo mese, 2 = ultimi 3 mesi, 3 = personalizzato
  int _selected = 0;
  DateTimeRange? _customRange;

  final _fmt = DateFormat('dd/MM/yyyy');

  List<DailyRecordDTO> _filtered() {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;

    switch (_selected) {
      case 1:
        from = DateTime(now.year, now.month - 1, now.day);
        break;
      case 2:
        from = DateTime(now.year, now.month - 3, now.day);
        break;
      case 3:
        from = _customRange?.start;
        to = _customRange?.end;
        break;
      default:
        break;
    }

    return widget.records.where((r) {
      final d = parseItalianDateSafe(r.dateIso);
      if (d == null) return false;
      if (from != null && d.isBefore(from)) return false;
      if (to != null && d.isAfter(to.add(const Duration(days: 1)))) return false;
      return true;
    }).toList();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: widget.lastDate.subtract(const Duration(days: 30)),
            end: widget.lastDate,
          ),
      locale: const Locale('it', 'IT'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _selected = 3;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _filtered().length;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.date_range_outlined,
                    color: cs.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Seleziona periodo di export',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Opzioni rapide
          _QuickOption(
            icon: Icons.all_inclusive_rounded,
            label: 'Tutti i dati',
            subtitle: '${widget.records.length} registrazioni',
            selected: _selected == 0,
            onTap: () => setState(() => _selected = 0),
          ),
          const SizedBox(height: 8),
          _QuickOption(
            icon: Icons.calendar_month_outlined,
            label: 'Ultimo mese',
            subtitle: _subtitleForPreset(1),
            selected: _selected == 1,
            onTap: () => setState(() => _selected = 1),
          ),
          const SizedBox(height: 8),
          _QuickOption(
            icon: Icons.calendar_today_outlined,
            label: 'Ultimi 3 mesi',
            subtitle: _subtitleForPreset(2),
            selected: _selected == 2,
            onTap: () => setState(() => _selected = 2),
          ),
          const SizedBox(height: 8),

          // Opzione range personalizzato
          _QuickOption(
            icon: Icons.tune_rounded,
            label: 'Range personalizzato',
            subtitle: _customRange != null
                ? '${_fmt.format(_customRange!.start)} → ${_fmt.format(_customRange!.end)}'
                : 'Tocca per scegliere',
            selected: _selected == 3,
            onTap: _pickCustomRange,
            trailing: Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ),
          const SizedBox(height: 24),

          // Counter registrazioni selezionate
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  count == 0
                      ? 'Nessuna registrazione nel periodo selezionato'
                      : '$count registrazioni verranno esportate',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Bottoni azione
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Annulla'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: count == 0
                      ? null
                      : () => Navigator.of(context).pop(_filtered()),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Esporta ($count)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitleForPreset(int preset) {
    final now = DateTime.now();
    final months = preset == 1 ? 1 : 3;
    final from = DateTime(now.year, now.month - months, now.day);
    final count = widget.records.where((r) {
      final d = parseItalianDateSafe(r.dateIso);
      return d != null && !d.isBefore(from);
    }).length;
    return '$count registrazioni';
  }
}

class _QuickOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _QuickOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: selected
                            ? cs.onPrimaryContainer
                            : cs.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (selected && trailing == null)
                Icon(Icons.check_circle_rounded,
                    color: cs.onPrimaryContainer, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
