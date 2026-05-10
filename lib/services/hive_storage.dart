// lib/services/hive_storage.dart

import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import '../core/constants/room_constants.dart';
import '../models/daily_record_dto.dart';

class AppStorage {
  static const String _boxName = 'clima_sense_box';
  static const String _recordsBoxName = 'daily_records_box';

  static const String _stagingPrefix = '__new__';

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

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(DailyRecordDTOAdapter());
    }
    await Hive.openBox(_boxName);
    await Hive.openBox<DailyRecordDTO>(_recordsBoxName);
    await _recoverStagingIfNeeded();
    await _migrateCostPerKwh();
    await _migrateRooms();
  }

  static Future<void> _migrateCostPerKwh() async {
    final box = Hive.box(_boxName);
    final stored = box.get('costPerKwh');
    final isLegacy = stored == null ||
        (stored is double && (stored == 0.25 || stored == 0.28));
    if (isLegacy) {
      await box.put('costPerKwh', _defaultCostPerKwh);
    }
  }

  /// Migrazione stanze: garantisce che le zone fisiche obbligatorie
  /// (Piano Terra, Primo Piano) siano sempre presenti in cima alla lista.
  static Future<void> _migrateRooms() async {
    final box = Hive.box(_boxName);
    final stored = box.get('customRooms');
    if (stored == null) return; // nessuna lista salvata: usa i default

    final current = List<String>.from(stored as List);
    bool changed = false;

    // Inserisce le zone fisse in cima se mancanti, nell'ordine corretto
    for (final zone in RoomConstants.defaultRooms.reversed) {
      if (!current.contains(zone)) {
        current.insert(0, zone);
        changed = true;
      }
    }

    if (changed) {
      await box.put('customRooms', current);
    }
  }

  static Future<void> _recoverStagingIfNeeded() async {
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

    if (definitiveKeys.isEmpty) {
      for (final sk in stagingKeys) {
        final record = box.get(sk);
        if (record != null) {
          final definitiveKey = sk.substring(_stagingPrefix.length);
          await box.put(definitiveKey, _cloneRecord(record));
        }
      }
    }

    await box.deleteAll(stagingKeys);
  }

  // --- APP STATE ---
  static bool isAppInitialized() {
    return Hive.box(_boxName).get('isInitialized', defaultValue: false);
  }

  static Future<void> setAppInitialized() async {
    await Hive.box(_boxName).put('isInitialized', true);
  }

  // --- CONFIGURAZIONE CURVE ---
  static Future<void> saveSlope(double value) async {
    await Hive.box(_boxName).put('heatingSlope', value);
  }

  static double getSlope() {
    return Hive.box(_boxName).get('heatingSlope', defaultValue: 1.0);
  }

  static Future<void> saveOffset(double value) async {
    await Hive.box(_boxName).put('heatingOffset', value);
  }

  static double getOffset() {
    return Hive.box(_boxName).get('heatingOffset', defaultValue: 0.0);
  }

  static Future<void> saveCoolingSlope(double value) async {
    await Hive.box(_boxName).put('coolingSlope', value);
  }

  static double getCoolingSlope() {
    return Hive.box(_boxName).get('coolingSlope', defaultValue: 0.5);
  }

  static Future<void> saveCoolingOffset(double value) async {
    await Hive.box(_boxName).put('coolingOffset', value);
  }

  static double getCoolingOffset() {
    return Hive.box(_boxName).get('coolingOffset', defaultValue: 0.0);
  }

  static Future<void> saveSystemMode(String mode) async {
    await Hive.box(_boxName).put('systemMode', mode);
  }

  static String getSystemMode() {
    return Hive.box(_boxName).get('systemMode', defaultValue: 'heating');
  }

  // --- TEMA ---
  static ThemeMode getThemeMode() {
    final stored =
        Hive.box(_boxName).get('themeMode', defaultValue: 'system') as String;
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      default:
        value = 'system';
    }
    await Hive.box(_boxName).put('themeMode', value);
  }

  // --- AI FLAGS ---
  static Future<void> saveLastAiApplyHeatingIso(String? iso) async {
    final box = Hive.box(_boxName);
    if (iso == null) {
      await box.delete('lastAiApplyHeating');
    } else {
      await box.put('lastAiApplyHeating', iso);
    }
  }

  static String? getLastAiApplyHeatingIso() {
    return Hive.box(_boxName).get('lastAiApplyHeating');
  }

  static Future<void> saveLastAiApplyCoolingIso(String? iso) async {
    final box = Hive.box(_boxName);
    if (iso == null) {
      await box.delete('lastAiApplyCooling');
    } else {
      await box.put('lastAiApplyCooling', iso);
    }
  }

  static String? getLastAiApplyCoolingIso() {
    return Hive.box(_boxName).get('lastAiApplyCooling');
  }

  static Future<void> resetCalibration() async {
    await saveSlope(1.0);
    await saveOffset(0.0);
    await saveCoolingSlope(0.5);
    await saveCoolingOffset(0.0);
    await saveLastAiApplyHeatingIso(null);
    await saveLastAiApplyCoolingIso(null);
  }

  // --- COSTI ---
  static double getCostPerKwh() {
    return Hive.box(_boxName).get('costPerKwh', defaultValue: _defaultCostPerKwh);
  }

  static Future<void> saveCostPerKwh(double value) async {
    await Hive.box(_boxName).put('costPerKwh', value);
  }

  // --- NOTIFICHE ---
  static Future<void> saveNotificationTime(TimeOfDay time) async {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    await Hive.box(_boxName).put('notificationTimeStr', '$h:$m');
  }

  static String? getNotificationTime() {
    return Hive.box(_boxName).get('notificationTimeStr', defaultValue: '20:00');
  }

  // --- CITTÀ METEO (override manuale GPS) ---
  static String? getCityOverride() {
    final v = Hive.box(_boxName).get('cityOverride') as String?;
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  static Future<void> saveCityOverride(String? city) async {
    final box = Hive.box(_boxName);
    if (city == null || city.trim().isEmpty) {
      await box.delete('cityOverride');
    } else {
      await box.put('cityOverride', city.trim());
    }
    // Invalida cache meteo
    await box.delete('weatherCacheTemp');
    await box.delete('weatherCacheCity');
    await box.delete('weatherCacheTimestamp');
  }

  // --- STANZE ---
  static Future<void> saveRooms(List<String> rooms) async {
    // Garanzia: le zone fisse sono sempre presenti prima di salvare
    final toSave = List<String>.from(rooms);
    for (final zone in RoomConstants.defaultRooms.reversed) {
      if (!toSave.contains(zone)) toSave.insert(0, zone);
    }
    await Hive.box(_boxName).put('customRooms', toSave);
  }

  static List<String> getRooms() {
    final stored = Hive.box(_boxName).get('customRooms');
    if (stored == null) return List<String>.from(RoomConstants.defaultRooms);
    final rooms = List<String>.from(stored as List);
    // Garanzia runtime: zone fisse sempre presenti
    for (final zone in RoomConstants.defaultRooms.reversed) {
      if (!rooms.contains(zone)) rooms.insert(0, zone);
    }
    return rooms;
  }

  // --- WIZARD IMPIANTO ---
  static String getPlantType() {
    return Hive.box(_boxName).get('plantType', defaultValue: 'heatpump') as String;
  }

  static Future<void> savePlantType(String type) async {
    await Hive.box(_boxName).put('plantType', type);
  }

  static bool getHasPv() {
    return Hive.box(_boxName).get('hasPv', defaultValue: false) as bool;
  }

  static Future<void> saveHasPv(bool value) async {
    await Hive.box(_boxName).put('hasPv', value);
  }

  static bool getHasGridMeter() {
    return Hive.box(_boxName).get('hasGridMeter', defaultValue: false) as bool;
  }

  static Future<void> saveHasGridMeter(bool value) async {
    await Hive.box(_boxName).put('hasGridMeter', value);
  }

  // --- RECORDS ---
  static Future<void> saveRecord(DailyRecordDTO record) async {
    final box = Hive.box<DailyRecordDTO>(_recordsBoxName);
    await box.put(_recordKey(record), record);
  }

  static Future<void> saveRecords(List<DailyRecordDTO> records) async {
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
  }

  static List<DailyRecordDTO> getRecords() {
    return Hive.box<DailyRecordDTO>(_recordsBoxName)
        .toMap()
        .entries
        .where((e) => !(e.key as String).startsWith(_stagingPrefix))
        .map((e) => e.value)
        .toList();
  }

  static Future<List<DailyRecordDTO>> loadRecords() async {
    return getRecords();
  }

  static Future<void> deleteRecord(String dateIso, String mode) async {
    await Hive.box<DailyRecordDTO>(_recordsBoxName).delete('${dateIso}_$mode');
  }
}
