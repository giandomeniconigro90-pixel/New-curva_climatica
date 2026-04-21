// lib/models/daily_record_dto.dart

import 'package:hive/hive.dart';

@HiveType(typeId: 0)
class DailyRecordDTO extends HiveObject {
  @HiveField(0)
  final String dateIso;

  @HiveField(1)
  final double externalTemp;

  @HiveField(2)
  final Map<String, double> internalTemps;

  @HiveField(3)
  final double consumption;

  @HiveField(4)
  final Map<String, String> comfortRatings;

  @HiveField(5)
  final String note;

  @HiveField(6)
  final String mode; // 'heating' o 'cooling'

  /// Modalità operativa della pompa di calore (Sherpa Monobloc S2 E6).
  /// Valori ammessi: 'riscaldamento', 'raffrescamento', 'spenta'.
  /// Leggibile dall'app Comfort Home (Olimpia Splendid).
  /// Null per i record creati prima di questo campo.
  @HiveField(7)
  final String? heatpumpMode;

  /// Consumo giornaliero acqua calda sanitaria in kWh (Atlantic Calypso VM 150).
  /// Leggibile dall'app Cozytouch (Atlantic).
  /// Null se non inserito dall'utente.
  @HiveField(8)
  final double? consumptionACS;

  /// Modalità operativa della caldaia.
  /// Valori ammessi: 'accesa', 'standby', 'spenta'.
  /// Leggibile dall'app Cozytouch (Atlantic).
  /// Null per i record creati prima di questo campo.
  @HiveField(9)
  final String? boilerMode;

  /// Energia prelevata dalla rete elettrica in kWh.
  /// Leggibile dall'app ShinePhone (Growatt).
  /// Null se non inserito dall'utente.
  @HiveField(10)
  final double? energyFromGrid;

  /// Produzione fotovoltaica giornaliera in kWh.
  /// Leggibile dall'app ShinePhone (Growatt).
  /// Null se non inserito dall'utente.
  @HiveField(11)
  final double? pvProduction;

  /// Valori ammessi per il campo [mode].
  static const Set<String> validModes = {'heating', 'cooling'};

  /// Valori ammessi per il campo [heatpumpMode].
  static const Set<String> validHeatpumpModes = {
    'riscaldamento',
    'raffrescamento',
    'spenta',
  };

  /// Valori ammessi per il campo [boilerMode].
  static const Set<String> validBoilerModes = {
    'accesa',
    'standby',
    'spenta',
  };

  DailyRecordDTO({
    required this.dateIso,
    required this.externalTemp,
    required this.internalTemps,
    required this.consumption,
    required this.comfortRatings,
    String? note,
    String? mode,
    this.heatpumpMode,
    this.consumptionACS,
    this.boilerMode,
    this.energyFromGrid,
    this.pvProduction,
  })  : note = note ?? '',
        mode = (mode != null && validModes.contains(mode)) ? mode : 'heating';

  /// Crea una copia del record sovrascrivendo solo i campi forniti.
  DailyRecordDTO copyWith({
    String? dateIso,
    double? externalTemp,
    Map<String, double>? internalTemps,
    double? consumption,
    Map<String, String>? comfortRatings,
    String? note,
    String? mode,
    String? heatpumpMode,
    bool clearHeatpumpMode = false,
    double? consumptionACS,
    bool clearConsumptionACS = false,
    String? boilerMode,
    bool clearBoilerMode = false,
    double? energyFromGrid,
    bool clearEnergyFromGrid = false,
    double? pvProduction,
    bool clearPvProduction = false,
  }) {
    return DailyRecordDTO(
      dateIso: dateIso ?? this.dateIso,
      externalTemp: externalTemp ?? this.externalTemp,
      internalTemps: internalTemps != null
          ? Map<String, double>.from(internalTemps)
          : Map<String, double>.from(this.internalTemps),
      consumption: consumption ?? this.consumption,
      comfortRatings: comfortRatings != null
          ? Map<String, String>.from(comfortRatings)
          : Map<String, String>.from(this.comfortRatings),
      note: note ?? this.note,
      mode: mode ?? this.mode,
      heatpumpMode: clearHeatpumpMode
          ? null
          : (heatpumpMode ?? this.heatpumpMode),
      consumptionACS: clearConsumptionACS
          ? null
          : (consumptionACS ?? this.consumptionACS),
      boilerMode: clearBoilerMode
          ? null
          : (boilerMode ?? this.boilerMode),
      energyFromGrid: clearEnergyFromGrid
          ? null
          : (energyFromGrid ?? this.energyFromGrid),
      pvProduction: clearPvProduction
          ? null
          : (pvProduction ?? this.pvProduction),
    );
  }

  /// Costruisce un [DailyRecordDTO] da una mappa JSON.
  factory DailyRecordDTO.fromJson(Map<String, dynamic> json) {
    final rawDate = json['dateIso'];
    if (rawDate == null || rawDate is! String || rawDate.trim().isEmpty) {
      throw FormatException(
        'DailyRecordDTO.fromJson: campo "dateIso" mancante o non valido.',
      );
    }

    final rawHeatpumpMode = json['heatpumpMode'];
    final rawBoilerMode = json['boilerMode'];

    return DailyRecordDTO(
      dateIso: rawDate.trim(),
      externalTemp: _parseDouble(json['externalTemp']),
      internalTemps: _parseStringDoubleMap(json['internalTemps']),
      consumption: _parseDouble(json['consumption']),
      comfortRatings: _parseStringStringMap(json['comfortRatings']),
      note: json['note'] is String ? json['note'] as String : '',
      mode: json['mode'] is String ? json['mode'] as String : 'heating',
      heatpumpMode: (rawHeatpumpMode is String &&
              validHeatpumpModes.contains(rawHeatpumpMode))
          ? rawHeatpumpMode
          : null,
      consumptionACS: json['consumptionACS'] != null
          ? _parseDouble(json['consumptionACS'])
          : null,
      boilerMode: (rawBoilerMode is String &&
              validBoilerModes.contains(rawBoilerMode))
          ? rawBoilerMode
          : null,
      energyFromGrid: json['energyFromGrid'] != null
          ? _parseDouble(json['energyFromGrid'])
          : null,
      pvProduction: json['pvProduction'] != null
          ? _parseDouble(json['pvProduction'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dateIso': dateIso,
      'externalTemp': externalTemp,
      'internalTemps': internalTemps,
      'consumption': consumption,
      'comfortRatings': comfortRatings,
      'note': note,
      'mode': mode,
      if (heatpumpMode != null) 'heatpumpMode': heatpumpMode,
      if (consumptionACS != null) 'consumptionACS': consumptionACS,
      if (boilerMode != null) 'boilerMode': boilerMode,
      if (energyFromGrid != null) 'energyFromGrid': energyFromGrid,
      if (pvProduction != null) 'pvProduction': pvProduction,
    };
  }

  // ---------------------------------------------------------------------------
  // Helper privati di parsing
  // ---------------------------------------------------------------------------

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static Map<String, double> _parseStringDoubleMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is! Map) return {};
    final result = <String, double>{};
    for (final entry in raw.entries) {
      if (entry.key is String) {
        result[entry.key as String] = _parseDouble(entry.value);
      }
    }
    return result;
  }

  static Map<String, String> _parseStringStringMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is! Map) return {};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value is String) {
        result[entry.key as String] = entry.value as String;
      }
    }
    return result;
  }
}

// --- ADAPTER MANUALE ---
class DailyRecordDTOAdapter extends TypeAdapter<DailyRecordDTO> {
  @override
  final int typeId = 0;

  @override
  DailyRecordDTO read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailyRecordDTO(
      dateIso: fields[0] as String,
      externalTemp: fields[1] as double,
      internalTemps: (fields[2] as Map).cast<String, double>(),
      consumption: fields[3] as double,
      comfortRatings: (fields[4] as Map).cast<String, String>(),
      note: fields[5] as String? ?? '',
      mode: fields[6] as String? ?? 'heating',
      heatpumpMode: fields[7] as String?,
      consumptionACS: fields[8] as double?,
      boilerMode: fields[9] as String?,
      energyFromGrid: fields[10] as double?,
      pvProduction: fields[11] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, DailyRecordDTO obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.dateIso)
      ..writeByte(1)
      ..write(obj.externalTemp)
      ..writeByte(2)
      ..write(obj.internalTemps)
      ..writeByte(3)
      ..write(obj.consumption)
      ..writeByte(4)
      ..write(obj.comfortRatings)
      ..writeByte(5)
      ..write(obj.note)
      ..writeByte(6)
      ..write(obj.mode)
      ..writeByte(7)
      ..write(obj.heatpumpMode)
      ..writeByte(8)
      ..write(obj.consumptionACS)
      ..writeByte(9)
      ..write(obj.boilerMode)
      ..writeByte(10)
      ..write(obj.energyFromGrid)
      ..writeByte(11)
      ..write(obj.pvProduction);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyRecordDTOAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
