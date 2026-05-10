// lib/services/hive_migration_runner.dart
//
// Refactor #7 — Migration helper per Hive:
//   • Ogni migrazione ha un numero di versione progressivo
//   • Al boot viene eseguito solo il delta (versioni > quella salvata)
//   • Idempotente: rieseguire non produce effetti collaterali
//   • Safe: ogni migrazione è in try/catch, un errore non blocca le successive
//   • Extensible: aggiungere v3, v4… basta aggiungere un case nel _runner

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants/room_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Schema version enum
// ─────────────────────────────────────────────────────────────────────────────

/// Versione corrente dello schema Hive.
/// Incrementa questo valore + aggiungi un case in [HiveMigrationRunner._migrate]
/// ogni volta che introduci una modifica incompatibile ai dati salvati.
const int kCurrentSchemaVersion = 2;

// ─────────────────────────────────────────────────────────────────────────────
// HiveMigrationRunner
// ─────────────────────────────────────────────────────────────────────────────

class HiveMigrationRunner {
  static const String _boxName = 'clima_sense_box';
  static const String _keySchemaVersion = 'schemaVersion';

  /// Prezzo kWh default (necessario per la v1).
  static const double _defaultCostPerKwh = 0.14891;

  // -------------------------------------------------------------------------
  // Entry point
  // -------------------------------------------------------------------------

  /// Esegue tutte le migrazioni dalla versione salvata fino a [kCurrentSchemaVersion].
  ///
  /// È sicuro chiamarlo ad ogni avvio: le migrazioni già applicate vengono
  /// saltate perché il numero di versione salvato è >= al loro numero.
  ///
  /// Prerequisito: il box [_boxName] deve essere già aperto.
  static Future<void> run() async {
    try {
      final box = Hive.box(_boxName);
      final int savedVersion =
          (box.get(_keySchemaVersion) as int?) ?? 0;

      if (savedVersion >= kCurrentSchemaVersion) {
        _log('Schema v$savedVersion — nessuna migrazione necessaria.');
        return;
      }

      _log('Schema v$savedVersion → v$kCurrentSchemaVersion: '
          'avvio ${kCurrentSchemaVersion - savedVersion} migrazione/i.');

      for (int v = savedVersion + 1; v <= kCurrentSchemaVersion; v++) {
        await _migrate(v, box);
      }

      await box.put(_keySchemaVersion, kCurrentSchemaVersion);
      _log('Migrazione completata — schema ora a v$kCurrentSchemaVersion.');
    } catch (e) {
      _log('Errore imprevisto in run(): $e');
    }
  }

  // -------------------------------------------------------------------------
  // Dispatcher migrazioni
  // -------------------------------------------------------------------------

  static Future<void> _migrate(int targetVersion, Box<dynamic> box) async {
    _log('Applico migrazione v$targetVersion...');
    switch (targetVersion) {
      case 1:
        await _migrateV1CostPerKwh(box);
      case 2:
        await _migrateV2Rooms(box);
      // ─────────────────────────────────────────────────────────────────
      // Per aggiungere v3:
      //   1. Incrementa kCurrentSchemaVersion a 3
      //   2. Aggiungi: case 3: await _migrateV3MyChange(box);
      //   3. Implementa _migrateV3MyChange()
      // ─────────────────────────────────────────────────────────────────
      default:
        _log('Nessuna implementazione per v$targetVersion — saltata.');
    }
  }

  // -------------------------------------------------------------------------
  // v1 — Normalizza costPerKwh
  //
  // Versioni precedenti usavano 0.25 o 0.28 come default.
  // Se il valore è assente o uguale a uno di questi legacy values,
  // sostituisce con il prezzo A2A corretto.
  // -------------------------------------------------------------------------

  static Future<void> _migrateV1CostPerKwh(Box<dynamic> box) async {
    try {
      final stored = box.get('costPerKwh');
      final isLegacy = stored == null ||
          (stored is double && (stored == 0.25 || stored == 0.28));
      if (isLegacy) {
        await box.put('costPerKwh', _defaultCostPerKwh);
        _log('v1: costPerKwh impostato a $_defaultCostPerKwh');
      } else {
        _log('v1: costPerKwh già valido (${stored}), nessuna modifica.');
      }
    } catch (e) {
      _log('v1 error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // v2 — Aggiunge le stanze di default alla lista custom
  //
  // Versioni precedenti potevano avere una lista custom senza le stanze
  // predefinite (Soggiorno, Notte). La migrazione le antepone se mancanti.
  // -------------------------------------------------------------------------

  static Future<void> _migrateV2Rooms(Box<dynamic> box) async {
    try {
      final stored = box.get('customRooms');
      if (stored == null) {
        _log('v2: nessuna lista stanze salvata, migrazione non necessaria.');
        return;
      }

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
        _log('v2: stanze di default aggiunte: $current');
      } else {
        _log('v2: stanze già presenti, nessuna modifica.');
      }
    } catch (e) {
      _log('v2 error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Logging
  // -------------------------------------------------------------------------

  static void _log(String msg) {
    if (kDebugMode) debugPrint('[HiveMigrationRunner] $msg');
  }
}
