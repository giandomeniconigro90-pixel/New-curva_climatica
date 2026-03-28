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

  /// Valori ammessi per il campo [mode].
  static const Set<String> validModes = {'heating', 'cooling'};

  DailyRecordDTO({
    required this.dateIso,
    required this.externalTemp,
    required this.internalTemps,
    required this.consumption,
    required this.comfortRatings,
    String? note,
    String? mode,
  })  : note = note ?? '',
        mode = (mode != null && validModes.contains(mode)) ? mode : 'heating';

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
    // dateIso è obbligatorio: senza non possiamo identificare il record
    final rawDate = json['dateIso'];
    if (rawDate == null || rawDate is! String || rawDate.trim().isEmpty) {
      throw FormatException(
        'DailyRecordDTO.fromJson: campo "dateIso" mancante o non valido.',
      );
    }

    return DailyRecordDTO(
      dateIso: rawDate.trim(),
      externalTemp: _parseDouble(json['externalTemp']),
      internalTemps: _parseStringDoubleMap(json['internalTemps']),
      consumption: _parseDouble(json['consumption']),
      comfortRatings: _parseStringStringMap(json['comfortRatings']),
      note: json['note'] is String ? json['note'] as String : '',
      mode: json['mode'] is String ? json['mode'] as String : 'heating',
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
    };
  }

  // ---------------------------------------------------------------------------
  // Helper privati di parsing
  // ---------------------------------------------------------------------------

  /// Converte un valore dinamico in double, restituisce 0.0 se non è un numero.
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Converte una mappa dinamica in Map<String, double>.
  /// Le coppie con chiave non-String o valore non-num vengono scartate.
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

  /// Converte una mappa dinamica in Map<String, String>.
  /// Le coppie con chiave o valore non-String vengono scartate.
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
      // Compatibilità con record legacy che non hanno il campo note (field 5)
      note: fields[5] as String? ?? '',
      // Compatibilità con record legacy che non hanno il campo mode (field 6)
      mode: fields[6] as String? ?? 'heating',
    );
  }

  @override
  void write(BinaryWriter writer, DailyRecordDTO obj) {
    writer
      ..writeByte(7)
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
      ..write(obj.mode);
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
