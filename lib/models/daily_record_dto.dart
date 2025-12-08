// lib/models/daily_record_dto.dart

import 'package:hive/hive.dart';
import 'dart:convert';

// NOTA: Rimuovi "part 'daily_record_dto.g.dart';" se presente

@HiveType(typeId: 0)
class DailyRecordDTO extends HiveObject {
  @HiveField(0)
  final String dateIso; // "YYYY-MM-DD"

  @HiveField(1)
  final double externalTemp;

  @HiveField(2)
  final Map internalTemps;

  @HiveField(3)
  final double consumption;

  @HiveField(4)
  final Map comfortRatings; // 'freddo', 'ok', 'caldo'

  @HiveField(5)
  final String note;

  DailyRecordDTO({
    required this.dateIso,
    required this.externalTemp,
    required this.internalTemps,
    required this.consumption,
    required this.comfortRatings,
    required this.note,
  });

  // --- METODI MANCANTI AGGIUNTI ---

  // Converte da Mappa a Oggetto (per loadRecords)
  factory DailyRecordDTO.fromMap(Map map) {
    return DailyRecordDTO(
      dateIso: map['dateIso'] as String,
      externalTemp: (map['externalTemp'] as num).toDouble(),
      internalTemps: Map.from(map['internalTemps'] ?? {}),
      consumption: (map['consumption'] as num).toDouble(),
      comfortRatings: Map.from(map['comfortRatings'] ?? {}),
      note: map['note'] as String? ?? '',
    );
  }

  // Converte da Oggetto a Mappa (per saveRecords)
  Map toMap() {
    return {
      'dateIso': dateIso,
      'externalTemp': externalTemp,
      'internalTemps': internalTemps,
      'consumption': consumption,
      'comfortRatings': comfortRatings,
      'note': note,
    };
  }

  // === NUOVI METODI PER BACKUP JSON ===
  factory DailyRecordDTO.fromJson(Map<String, dynamic> json) {
    return DailyRecordDTO(
      dateIso: json['dateIso'] as String,
      externalTemp: (json['externalTemp'] as num).toDouble(),
      internalTemps: Map.from(json['internalTemps'] ?? {}),
      consumption: (json['consumption'] as num).toDouble(),
      comfortRatings: Map.from(json['comfortRatings'] ?? {}),
      note: json['note'] as String? ?? '',
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
    };
  }
}

// --- ADAPTER MANUALE (COPIA QUESTO IN FONDO AL FILE) ---
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
      note: fields[5] as String,
    );
  }

  @override
  void write(BinaryWriter writer, DailyRecordDTO obj) {
    writer
      ..writeByte(6)
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
      ..write(obj.note);
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
