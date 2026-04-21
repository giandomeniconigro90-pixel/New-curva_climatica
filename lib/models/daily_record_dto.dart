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

  /// Valori ammessi per il campo [mode].
  static const Set<String> validModes = {'heating', 'cooling'};

  /// Valori ammessi per il campo [heatpumpMode].
  static const Set<String> validHeatpumpModes = {
    'riscaldamento',
    'raffrescamento',
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
    );
  }

  /// Costruisce un [DailyRecordDTO] da una mappa JSON.
  ///
  /// Gestisce in modo difensivo:
  /// - campi mancanti o null (usa valori di default)
  /// - tipi numerici errati (usa 0.0)
  /// - campo [mode] non valido (usa 'heating')
  ///
  /// Lancia [FormatException] solo se [dateIso] è assente o non è una stringa,
  /// perché è la chiave primaria del record e senza di essa il dato è inutilizzabile.
  factory DailyRecordDTO.fromJson(Map<String, dynamic> json) {
    final rawDate = json['dateIso'];
    if (rawDate == null || rawDate is! String || rawDate.trim().isEmpty) {
      throw FormatException(
        'DailyRecordDTO.fromJson: campo "dateIso" mancante o non valido.',
      );
    }

    final rawHeatpumpMode = json['heatpumpMode'];

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
    );
  }

  @override
  void write(BinaryWriter writer, DailyRecordDTO obj) {
    writer
      ..writeByte(8)
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
      ..write(obj.heatpumpMode);
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
