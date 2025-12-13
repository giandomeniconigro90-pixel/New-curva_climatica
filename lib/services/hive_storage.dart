// lib/services/hive_storage.dart

import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart'; // Per TimeOfDay
import '../models/daily_record_dto.dart';

class AppStorage {
  static const String _boxName = 'clima_sense_box';
  static const String _recordsBoxName = 'daily_records_box';

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(DailyRecordDTOAdapter());
    }
    await Hive.openBox(_boxName);
    await Hive.openBox<DailyRecordDTO>(_recordsBoxName);
  }

  // --- APP STATE ---
  static bool isAppInitialized() {
    var box = Hive.box(_boxName);
    return box.get('isInitialized', defaultValue: false);
  }

  static Future<void> setAppInitialized() async {
    var box = Hive.box(_boxName);
    await box.put('isInitialized', true);
  }

  // --- CONFIGURAZIONE CURVE ---
  static Future<void> saveSlope(double value) async {
    await Hive.box(_boxName).put('heatingSlope', value);
  }

  static double getSlope() {
    return Hive.box(_boxName).get('heatingSlope', defaultValue: 1.2);
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
    // Valori di default curva riscaldamento
    await saveSlope(1.2);
    await saveOffset(0.0);

    // Valori di default curva raffrescamento
    await saveCoolingSlope(0.5);
    await saveCoolingOffset(0.0);

    // Reset date applicazione AI
    await saveLastAiApplyHeatingIso(null);
    await saveLastAiApplyCoolingIso(null);

    // NON toccare i records qui: niente saveRecords([])
  }

  // --- COSTI ---
  static double getCostPerKwh() {
    return Hive.box(_boxName).get('costPerKwh', defaultValue: 0.25);
  }

  static Future<void> saveCostPerKwh(double value) async {
    await Hive.box(_boxName).put('costPerKwh', value);
  }

  // --- NOTIFICHE (TimeOfDay salvato come int hour, int minute o stringa 'HH:mm') ---
  // Per compatibilità con NotificationService che usa split, salviamo come String
  static Future<void> saveNotificationTime(TimeOfDay time) async {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    await Hive.box(_boxName).put('notificationTimeStr', '$h:$m');
  }

  static String? getNotificationTime() {
    // Ritorna "HH:mm" o null
    return Hive.box(_boxName).get('notificationTimeStr', defaultValue: "20:00");
  }

  // --- RECORDS (Gestione Dati Giornalieri) ---
  static Future<void> saveRecord(DailyRecordDTO record) async {
    var box = Hive.box<DailyRecordDTO>(_recordsBoxName);
    await box.put(record.dateIso, record);
  }

  // Alias per compatibilità
  // Alias per compatibilità
  static Future<void> saveRecords(List<DailyRecordDTO> records) async {
    var box = Hive.box<DailyRecordDTO>(_recordsBoxName);

    // 1) cancella tutti i record salvati prima
    await box.clear();

    // 2) risalva solo quelli passati
    for (var r in records) {
      await box.put(r.dateIso, r);
    }
  }

  static List<DailyRecordDTO> getRecords() {
    var box = Hive.box<DailyRecordDTO>(_recordsBoxName);
    return box.values.toList();
  }

  // Alias asincrono se richiesto
  static Future<List<DailyRecordDTO>> loadRecords() async {
    return getRecords();
  }

  static Future<void> deleteRecord(String dateIso) async {
    await Hive.box<DailyRecordDTO>(_recordsBoxName).delete(dateIso);
  }
}
