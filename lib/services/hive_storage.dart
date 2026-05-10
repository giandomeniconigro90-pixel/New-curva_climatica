// lib/services/hive_storage.dart

import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../core/constants/room_constants.dart';
import '../models/daily_record_dto.dart';

/// Snapshot di un singolo apply AI, usato per lo storico e l'undo.
class AiApplySnapshot {
  final double slope;
  final double offset;
  final String mode; // 'heating' | 'cooling'
  final String appliedAt; // ISO-8601
  final String smartTip;

  const AiApplySnapshot({
    required this.slope,
    required this.offset,
    required this.mode,
    required this.appliedAt,
    required this.smartTip,
  });

  Map<String, dynamic> toJson() => {
        'slope': slope,
        'offset': offset,
        'mode': mode,
        'appliedAt': appliedAt,
        'smartTip': smartTip,
      };

  factory AiApplySnapshot.fromJson(Map<String, dynamic> j) => AiApplySnapshot(
        slope: (j['slope'] as num).toDouble(),
        offset: (j['offset'] as num).toDouble(),
        mode: j['mode'] as String,
        appliedAt: j['appliedAt'] as String,
        smartTip: j['smartTip'] as String? ?? '',
      );
}

class AppStorage {
  static const String _boxName = 'clima_sense_box';
  static const String _recordsBoxName = 'daily_records_box';

  static const String _stagingPrefix = '__new__';
  static const String _aiHistoryKey = 'aiApplyHistory';

  /// Prezzo reale A2A Click Luce Monoraria (IVA 10% inclusa).
  static const double _defaultCostPerKwh = 0.14891;

  static String _recordKey(DailyRecordDTO r) => '${r.dateIso}_${r.mode}';
  static String _stagingKey(DailyRecordDTO r) => '$_stagingPrefix${_recordKey(r)}';

  static DailyRecordDTO _cloneRecord(DailyRecordDTO r) => DailyRecordDTO(
        dateIso: r.dateIso,
        externalTemp: r.externalTemp,
        internalTemps: Map<String, double>.from(r.internalTemps),
        consumption: r.consumption,
        comfortRatings: Map<String, String>.from(r.comfortRatings),
        note: r.note,
        mode: r.mode,
        heatpumpMode: r.heatpumpMode,
        consumptionACS: r.consumptionACS,
        boilerMode: r.boilerMode,
        energyFromGrid: r.energyFromGrid,
        pvProduction: r.pvProduction,
      );

  // ─────────────────────────────────────────────────────────────────────────
  // INIT — con gestione errori robusta (#2)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(DailyRecordDTOAdapter());
      }
      await Hive.openBox(_boxName);
      await Hive.openBox<DailyRecordDTO>(_recordsBoxName);
      await _recoverStagingIfNeeded();
      await _migrateCostPerKwh();
      await _migrateRooms();
    } on HiveError catch (e) {
      // Box corrotto: tentiamo una reinizializzazione pulita.
      // I dati vengono persi ma l'app non crasha.
      debugPrint('[AppStorage] HiveError durante init: $e — tento recupero.');
      await _tryRecoverCorruptedBoxes();
    } catch (e) {
      debugPrint('[AppStorage] Errore imprevisto durante init: $e');
      // Proseguiamo comunque: l'app parte con dati vuoti.
    }
  }

  /// Tenta di eliminare e riaprire i box corrotti.
  static Future<void> _tryRecoverCorruptedBoxes() async {
    try {
      // Chiudi tutto ciò che è aperto
      await Hive.close();
      // Reinizializza da zero (i file vengono sovrascritti al prossimo put)
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(DailyRecordDTOAdapter());
      }
      // Elimina i box corrotti e riaprili vuoti
      await Hive.deleteBoxFromDisk(_boxName);
      await Hive.deleteBoxFromDisk(_recordsBoxName);
      await Hive.openBox(_boxName);
      await Hive.openBox<DailyRecordDTO>(_recordsBoxName);
      debugPrint('[AppStorage] Recupero completato: box reinizializzati vuoti.');
    } catch (e) {
      debugPrint('[AppStorage] Recupero fallito: $e');
    }
  }

  static Future<void> _migrateCostPerKwh() async {
    try {
      final box = Hive.box(_boxName);
      final stored = box.get('costPerKwh');
      final isLegacy = stored == null ||
          (stored is double && (stored == 0.25 || stored == 0.28));
      if (isLegacy) {
        await box.put('costPerKwh', _defaultCostPerKwh);
      }
    } catch (e) {
      debugPrint('[AppStorage] _migrateCostPerKwh error: $e');
    }
  }

  static Future<void> _migrateRooms() async {
    try {
      final box = Hive.box(_boxName);
      final stored = box.get('customRooms');
      if (stored == null) return;

      final current = List<String>.from(stored as List);
      bool changed = false;

      for (final zone in RoomConstants.defaultRooms.reversed) {
        if (!current.contains(zone)) {
          current.insert(0, zone);
          changed = true;
        }
      }

      if (changed) {
        await box.put('customRooms', current);
      }
    } catch (e) {
      debugPrint('[AppStorage] _migrateRooms error: $e');
    }
  }

  static Future<void> _recoverStagingIfNeeded() async {
    try {
      final box = Hive.box<DailyRecordDTO>(_recordsBoxName);

      final stagingKeys = box.keys
          .whereType<String>()
          .where((k) => k.startsWith(_stagingPrefix))
          .toList();

      if (stagingKeys.isEmpty) return;

      final definitiveKeys = box.keys
          .whereType<String>()
          .where((k) => !k.startsWith(_stagingPrefix))
          .toSet();

      for (final sk in stagingKeys) {
        final definitiveKey = sk.substring(_stagingPrefix.length);
        if (!definitiveKeys.contains(definitiveKey)) {
          final record = box.get(sk);
          if (record != null) {
            await box.put(definitiveKey, _cloneRecord(record));
          }
        }
      }

      await box.deleteAll(stagingKeys);
    } catch (e) {
      debugPrint('[AppStorage] _recoverStagingIfNeeded error: $e');
    }
  }

  // --- APP STATE ---
  static bool isAppInitialized() {
    try {
      return Hive.box(_boxName).get('isInitialized', defaultValue: false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAppInitialized() async {
    try {
      await Hive.box(_boxName).put('isInitialized', true);
    } catch (e) {
      debugPrint('[AppStorage] setAppInitialized error: $e');
    }
  }

  // --- CONFIGURAZIONE CURVE ---
  static Future<void> saveSlope(double value) async {
    try { await Hive.box(_boxName).put('heatingSlope', value); }
    catch (e) { debugPrint('[AppStorage] saveSlope error: $e'); }
  }

  static double getSlope() {
    try { return Hive.box(_boxName).get('heatingSlope', defaultValue: 1.0); }
    catch (_) { return 1.0; }
  }

  static Future<void> saveOffset(double value) async {
    try { await Hive.box(_boxName).put('heatingOffset', value); }
    catch (e) { debugPrint('[AppStorage] saveOffset error: $e'); }
  }

  static double getOffset() {
    try { return Hive.box(_boxName).get('heatingOffset', defaultValue: 0.0); }
    catch (_) { return 0.0; }
  }

  static Future<void> saveCoolingSlope(double value) async {
    try { await Hive.box(_boxName).put('coolingSlope', value); }
    catch (e) { debugPrint('[AppStorage] saveCoolingSlope error: $e'); }
  }

  static double getCoolingSlope() {
    try { return Hive.box(_boxName).get('coolingSlope', defaultValue: 0.5); }
    catch (_) { return 0.5; }
  }

  static Future<void> saveCoolingOffset(double value) async {
    try { await Hive.box(_boxName).put('coolingOffset', value); }
    catch (e) { debugPrint('[AppStorage] saveCoolingOffset error: $e'); }
  }

  static double getCoolingOffset() {
    try { return Hive.box(_boxName).get('coolingOffset', defaultValue: 0.0); }
    catch (_) { return 0.0; }
  }

  static Future<void> saveSystemMode(String mode) async {
    try { await Hive.box(_boxName).put('systemMode', mode); }
    catch (e) { debugPrint('[AppStorage] saveSystemMode error: $e'); }
  }

  static String getSystemMode() {
    try { return Hive.box(_boxName).get('systemMode', defaultValue: 'heating'); }
    catch (_) { return 'heating'; }
  }

  // --- TEMA ---
  static ThemeMode getThemeMode() {
    try {
      final stored =
          Hive.box(_boxName).get('themeMode', defaultValue: 'system') as String;
      switch (stored) {
        case 'light': return ThemeMode.light;
        case 'dark':  return ThemeMode.dark;
        default:      return ThemeMode.system;
      }
    } catch (_) {
      return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    try {
      final String value;
      switch (mode) {
        case ThemeMode.light: value = 'light'; break;
        case ThemeMode.dark:  value = 'dark';  break;
        default:              value = 'system';
      }
      await Hive.box(_boxName).put('themeMode', value);
    } catch (e) {
      debugPrint('[AppStorage] saveThemeMode error: $e');
    }
  }

  // --- AI FLAGS ---
  static Future<void> saveLastAiApplyHeatingIso(String? iso) async {
    try {
      final box = Hive.box(_boxName);
      if (iso == null) {
        await box.delete('lastAiApplyHeating');
      } else {
        await box.put('lastAiApplyHeating', iso);
      }
    } catch (e) {
      debugPrint('[AppStorage] saveLastAiApplyHeatingIso error: $e');
    }
  }

  static String? getLastAiApplyHeatingIso() {
    try { return Hive.box(_boxName).get('lastAiApplyHeating'); }
    catch (_) { return null; }
  }

  static Future<void> saveLastAiApplyCoolingIso(String? iso) async {
    try {
      final box = Hive.box(_boxName);
      if (iso == null) {
        await box.delete('lastAiApplyCooling');
      } else {
        await box.put('lastAiApplyCooling', iso);
      }
    } catch (e) {
      debugPrint('[AppStorage] saveLastAiApplyCoolingIso error: $e');
    }
  }

  static String? getLastAiApplyCoolingIso() {
    try { return Hive.box(_boxName).get('lastAiApplyCooling'); }
    catch (_) { return null; }
  }

  static Future<void> resetCalibration() async {
    await saveSlope(1.0);
    await saveOffset(0.0);
    await saveCoolingSlope(0.5);
    await saveCoolingOffset(0.0);
    await saveLastAiApplyHeatingIso(null);
    await saveLastAiApplyCoolingIso(null);
    await clearAiHistory();
  }

  // --- AI HISTORY (F4) ---
  static List<AiApplySnapshot> getAiHistory() {
    try {
      final box = Hive.box(_boxName);
      final raw = box.get(_aiHistoryKey);
      if (raw == null) return [];
      final list = raw is String
          ? jsonDecode(raw) as List
          : raw as List;
      return list
          .map((e) => AiApplySnapshot.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[AppStorage] getAiHistory error: $e');
      return [];
    }
  }

  static Future<void> addAiSnapshot(AiApplySnapshot snapshot) async {
    try {
      final history = getAiHistory();
      history.insert(0, snapshot);
      if (history.length > 20) history.removeLast();
      await Hive.box(_boxName)
          .put(_aiHistoryKey, jsonEncode(history.map((s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('[AppStorage] addAiSnapshot error: $e');
    }
  }

  static Future<AiApplySnapshot?> popLastAiSnapshot() async {
    try {
      final history = getAiHistory();
      if (history.isEmpty) return null;
      final last = history.removeAt(0);
      await Hive.box(_boxName)
          .put(_aiHistoryKey, jsonEncode(history.map((s) => s.toJson()).toList()));
      return last;
    } catch (e) {
      debugPrint('[AppStorage] popLastAiSnapshot error: $e');
      return null;
    }
  }

  static Future<void> clearAiHistory() async {
    try { await Hive.box(_boxName).delete(_aiHistoryKey); }
    catch (e) { debugPrint('[AppStorage] clearAiHistory error: $e'); }
  }

  // --- COSTI ---
  static double getCostPerKwh() {
    try { return Hive.box(_boxName).get('costPerKwh', defaultValue: _defaultCostPerKwh); }
    catch (_) { return _defaultCostPerKwh; }
  }

  static Future<void> saveCostPerKwh(double value) async {
    try { await Hive.box(_boxName).put('costPerKwh', value); }
    catch (e) { debugPrint('[AppStorage] saveCostPerKwh error: $e'); }
  }

  // --- NOTIFICHE ---
  static Future<void> saveNotificationTime(TimeOfDay time) async {
    try {
      final h = time.hour.toString().padLeft(2, '0');
      final m = time.minute.toString().padLeft(2, '0');
      await Hive.box(_boxName).put('notificationTimeStr', '$h:$m');
    } catch (e) {
      debugPrint('[AppStorage] saveNotificationTime error: $e');
    }
  }

  static String? getNotificationTime() {
    try { return Hive.box(_boxName).get('notificationTimeStr', defaultValue: '20:00'); }
    catch (_) { return '20:00'; }
  }

  // --- CITTÀ METEO ---
  static String? getCityOverride() {
    try {
      final v = Hive.box(_boxName).get('cityOverride') as String?;
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCityOverride(String? city) async {
    try {
      final box = Hive.box(_boxName);
      if (city == null || city.trim().isEmpty) {
        await box.delete('cityOverride');
      } else {
        await box.put('cityOverride', city.trim());
      }
      await box.delete('weatherCacheTemp');
      await box.delete('weatherCacheCity');
      await box.delete('weatherCacheTimestamp');
    } catch (e) {
      debugPrint('[AppStorage] saveCityOverride error: $e');
    }
  }

  // --- STANZE ---
  static Future<void> saveRooms(List<String> rooms) async {
    try {
      final toSave = List<String>.from(rooms);
      for (final zone in RoomConstants.defaultRooms.reversed) {
        if (!toSave.contains(zone)) toSave.insert(0, zone);
      }
      await Hive.box(_boxName).put('customRooms', toSave);
    } catch (e) {
      debugPrint('[AppStorage] saveRooms error: $e');
    }
  }

  static List<String> getRooms() {
    try {
      final stored = Hive.box(_boxName).get('customRooms');
      if (stored == null) return List<String>.from(RoomConstants.defaultRooms);
      final rooms = List<String>.from(stored as List);
      for (final zone in RoomConstants.defaultRooms.reversed) {
        if (!rooms.contains(zone)) rooms.insert(0, zone);
      }
      return rooms;
    } catch (_) {
      return List<String>.from(RoomConstants.defaultRooms);
    }
  }

  // --- WIZARD IMPIANTO ---
  static String getPlantType() {
    try { return Hive.box(_boxName).get('plantType', defaultValue: 'heatpump') as String; }
    catch (_) { return 'heatpump'; }
  }

  static Future<void> savePlantType(String type) async {
    try { await Hive.box(_boxName).put('plantType', type); }
    catch (e) { debugPrint('[AppStorage] savePlantType error: $e'); }
  }

  static bool getHasPv() {
    try { return Hive.box(_boxName).get('hasPv', defaultValue: false) as bool; }
    catch (_) { return false; }
  }

  static Future<void> saveHasPv(bool value) async {
    try { await Hive.box(_boxName).put('hasPv', value); }
    catch (e) { debugPrint('[AppStorage] saveHasPv error: $e'); }
  }

  static bool getHasGridMeter() {
    try { return Hive.box(_boxName).get('hasGridMeter', defaultValue: false) as bool; }
    catch (_) { return false; }
  }

  static Future<void> saveHasGridMeter(bool value) async {
    try { await Hive.box(_boxName).put('hasGridMeter', value); }
    catch (e) { debugPrint('[AppStorage] saveHasGridMeter error: $e'); }
  }

  // --- RECORDS ---
  static Future<void> saveRecord(DailyRecordDTO record) async {
    try {
      final box = Hive.box<DailyRecordDTO>(_recordsBoxName);
      await box.put(_recordKey(record), record);
    } catch (e) {
      debugPrint('[AppStorage] saveRecord error: $e');
    }
  }

  /// Salva tutti i record con pattern staging → promote → cleanup.
  /// In caso di errore logga e rilancia per permettere al notifier
  /// di mostrare un toast all'utente.
  static Future<void> saveRecords(List<DailyRecordDTO> records) async {
    try {
      final box = Hive.box<DailyRecordDTO>(_recordsBoxName);

      final Map<String, DailyRecordDTO> staging = {
        for (final r in records) _stagingKey(r): _cloneRecord(r),
      };
      await box.putAll(staging);

      final definitiveKeys = box.keys
          .whereType<String>()
          .where((k) => !k.startsWith(_stagingPrefix))
          .toList();
      await box.deleteAll(definitiveKeys);

      final Map<String, DailyRecordDTO> promoted = {
        for (final r in records) _recordKey(r): _cloneRecord(r),
      };
      await box.putAll(promoted);

      await box.deleteAll(staging.keys.toList());
    } on HiveError catch (e) {
      debugPrint('[AppStorage] saveRecords HiveError: $e');
      rethrow; // Il chiamante (HomeNotifier) mostrerà un toast
    } catch (e) {
      debugPrint('[AppStorage] saveRecords error: $e');
      rethrow;
    }
  }

  static List<DailyRecordDTO> getRecords() {
    try {
      return Hive.box<DailyRecordDTO>(_recordsBoxName)
          .toMap()
          .entries
          .where((e) => !(e.key as String).startsWith(_stagingPrefix))
          .map((e) => e.value)
          .toList();
    } catch (e) {
      debugPrint('[AppStorage] getRecords error: $e');
      return [];
    }
  }

  static Future<List<DailyRecordDTO>> loadRecords() async {
    try {
      return getRecords();
    } catch (e) {
      debugPrint('[AppStorage] loadRecords error: $e');
      return []; // Fallback sicuro: lista vuota invece di crash
    }
  }

  static Future<void> deleteRecord(String dateIso, String mode) async {
    try {
      await Hive.box<DailyRecordDTO>(_recordsBoxName).delete('${dateIso}_$mode');
    } catch (e) {
      debugPrint('[AppStorage] deleteRecord error: $e');
    }
  }
}
