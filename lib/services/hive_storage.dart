// lib/services/hive_storage.dart

import 'package:hive_flutter/hive_flutter.dart';
import '../models/daily_record_dto.dart';

class AppStorage {
  static const String _boxName = 'appBox';
  static const String _recordsKey = 'records';

  // Chiavi Riscaldamento (Default)
  static const String _slopeKey = 'slope';
  static const String _offsetKey = 'offset';

  // Chiavi Raffrescamento (Nuove)
  static const String _coolingSlopeKey = 'coolingSlope';
  static const String _coolingOffsetKey = 'coolingOffset';

  // Chiave Modalità Sistema
  static const String _modeKey = 'systemMode'; // 'heating' o 'cooling'
  static const String _costKey = 'costPerKwh';

  // Chiave orario notifica giornaliera
  static const String _notificationTimeKey = 'notificationTime';

  // Chiave inizializzazione app
  static const String _initKey = 'isInitialized';

  static Future init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  // === RECORDS ===

  static Future<List<DailyRecordDTO>> loadRecords() async {
    final box = await Hive.openBox(_boxName);
    final List stored = box.get(_recordsKey, defaultValue: []) as List;
    return stored
        .map((e) => DailyRecordDTO.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future saveRecords(List<DailyRecordDTO> records) async {
    final box = await Hive.openBox(_boxName);
    final List<Map<String, dynamic>> data =
    records.map((r) => Map<String, dynamic>.from(r.toMap())).toList();
    await box.put(_recordsKey, data);
  }

  // === RISCALDAMENTO ===

  static Future<double> getSlope({double defaultValue = 1.2}) async {
    final box = await Hive.openBox(_boxName);
    final value = box.get(_slopeKey);
    if (value == null) return defaultValue;
    return (value as num).toDouble();
  }

  static Future<double> getOffset({double defaultValue = 0.0}) async {
    final box = await Hive.openBox(_boxName);
    final value = box.get(_offsetKey);
    if (value == null) return defaultValue;
    return (value as num).toDouble();
  }

  static Future saveSlope(double slope) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_slopeKey, slope);
  }

  static Future saveOffset(double offset) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_offsetKey, offset);
  }

  // === RAFFRESCAMENTO ===

  static Future<double> getCoolingSlope({double defaultValue = 0.5}) async {
    final box = await Hive.openBox(_boxName);
    final value = box.get(_coolingSlopeKey);
    if (value == null) return defaultValue;
    return (value as num).toDouble();
  }

  static Future<double> getCoolingOffset({double defaultValue = 18.0}) async {
    final box = await Hive.openBox(_boxName);
    final value = box.get(_coolingOffsetKey);
    if (value == null) return defaultValue;
    return (value as num).toDouble();
  }

  static Future saveCoolingSlope(double slope) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_coolingSlopeKey, slope);
  }

  static Future saveCoolingOffset(double offset) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_coolingOffsetKey, offset);
  }

  // === MODALITÀ SISTEMA ===

  static Future<String> getSystemMode() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_modeKey, defaultValue: 'heating') as String;
  }

  static Future saveSystemMode(String mode) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_modeKey, mode);
  }

  // === COSTO ENERGIA ===

  static Future<double> getCostPerKwh({double defaultValue = 0.25}) async {
    final box = await Hive.openBox(_boxName);
    final value = box.get(_costKey);
    if (value == null) return defaultValue;
    return (value as num).toDouble();
  }

  static Future saveCostPerKwh(double cost) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_costKey, cost);
  }

  // === NOTIFICHE ===

  static Future<String?> getNotificationTime() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_notificationTimeKey) as String?;
  }

  static Future saveNotificationTime(String time) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_notificationTimeKey, time);
  }

  // === INIZIALIZZAZIONE APP ===

  static Future setAppInitialized() async {
    final box = await Hive.openBox(_boxName);
    await box.put(_initKey, true);
  }

  static Future<bool> isAppInitialized() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_initKey, defaultValue: false) as bool;
  }

  static Future resetCalibration() async {
    final box = await Hive.openBox(_boxName);
    await box.delete(_slopeKey);
    await box.delete(_offsetKey);
    await box.delete(_coolingSlopeKey);
    await box.delete(_coolingOffsetKey);
    await box.delete(_initKey);
  }
}