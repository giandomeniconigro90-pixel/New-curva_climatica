import 'package:hive_flutter/hive_flutter.dart';
import '../models/daily_record_dto.dart';

class AppStorage {
  static const String _boxName = 'appBox';
  static const String _recordsKey = 'records';

  static const String _slopeKey = 'slope';
  static const String _offsetKey = 'offset';
  static const String _coolingSlopeKey = 'coolingSlope';
  static const String _coolingOffsetKey = 'coolingOffset';
  static const String _modeKey = 'systemMode';
  static const String _costKey = 'costPerKwh';
  static const String _notificationTimeKey = 'notificationTime';
  static const String _initKey = 'isInitialized';

  // AI Cooldown Keys
  static const String _lastAiApplyHeatingKey = 'lastAiApplyHeatingIso';
  static const String _lastAiApplyCoolingKey = 'lastAiApplyCoolingIso';

  static Future init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  static Future<List<DailyRecordDTO>> loadRecords() async {
    final box = await Hive.openBox(_boxName);
    final List stored = box.get(_recordsKey, defaultValue: []) as List;
    return stored.map((e) => DailyRecordDTO.fromMap(Map.from(e as Map))).toList();
  }

  static Future saveRecords(List<DailyRecordDTO> records) async {
    final box = await Hive.openBox(_boxName);
    final List<Map<String, dynamic>> data =
    records.map((r) => Map<String, dynamic>.from(r.toMap())).toList();
    await box.put(_recordsKey, data);
  }

  static Future<double> getSlope({double defaultValue = 1.2}) async {
    final box = await Hive.openBox(_boxName);
    final val = box.get(_slopeKey);
    return (val is num) ? val.toDouble() : defaultValue;
  }

  static Future<double> getOffset({double defaultValue = 0.0}) async {
    final box = await Hive.openBox(_boxName);
    final val = box.get(_offsetKey);
    return (val is num) ? val.toDouble() : defaultValue;
  }

  static Future saveSlope(double slope) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_slopeKey, slope);
  }

  static Future saveOffset(double offset) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_offsetKey, offset);
  }

  static Future<double> getCoolingSlope({double defaultValue = 0.5}) async {
    final box = await Hive.openBox(_boxName);
    final val = box.get(_coolingSlopeKey);
    return (val is num) ? val.toDouble() : defaultValue;
  }

  static Future<double> getCoolingOffset({double defaultValue = 0.0}) async {
    final box = await Hive.openBox(_boxName);
    final val = box.get(_coolingOffsetKey);
    return (val is num) ? val.toDouble() : defaultValue;
  }

  static Future saveCoolingSlope(double slope) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_coolingSlopeKey, slope);
  }

  static Future saveCoolingOffset(double offset) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_coolingOffsetKey, offset);
  }

  static Future<String> getSystemMode() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_modeKey, defaultValue: 'heating') as String;
  }

  static Future saveSystemMode(String mode) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_modeKey, mode);
  }

  // Metodi mancanti aggiunti
  static Future<String?> getLastAiApplyHeatingIso() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_lastAiApplyHeatingKey) as String?;
  }

  static Future<String?> getLastAiApplyCoolingIso() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_lastAiApplyCoolingKey) as String?;
  }

  static Future<void> saveLastAiApplyHeatingIso(String iso) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_lastAiApplyHeatingKey, iso);
  }

  static Future<void> saveLastAiApplyCoolingIso(String iso) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_lastAiApplyCoolingKey, iso);
  }

  static Future<double> getCostPerKwh({double defaultValue = 0.25}) async {
    final box = await Hive.openBox(_boxName);
    final val = box.get(_costKey);
    return (val is num) ? val.toDouble() : defaultValue;
  }

  static Future saveCostPerKwh(double cost) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_costKey, cost);
  }

  static Future<String?> getNotificationTime() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_notificationTimeKey) as String?;
  }

  static Future saveNotificationTime(String time) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_notificationTimeKey, time);
  }

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
    await box.delete(_lastAiApplyHeatingKey);
    await box.delete(_lastAiApplyCoolingKey);
    await box.delete(_initKey);
  }
}
