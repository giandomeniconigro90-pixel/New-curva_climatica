// lib/features/home/utils/backup_version.dart
//
// Costanti per il versioning del backup JSON.
// Aggiornare [current] ogni volta che si modifica la struttura
// di DailyRecordDTO, CurveSettings o del formato backup.
//
// Storico versioni:
//   v1 — formato originale (senza backupVersion nel metadata)
//   v2 — aggiunta backupVersion + modelVersion nel metadata (#3)

abstract final class BackupVersion {
  /// Versione corrente del formato backup prodotta da questa build.
  static const int current = 2;

  /// Versione minima supportata al restore.
  /// Backup con backupVersion < minSupported vengono rifiutati.
  static const int minSupported = 1;

  /// Versione del modello DailyRecordDTO.
  /// Incrementare quando si aggiungono/rimuovono campi obbligatori.
  static const int modelVersion = 1;

  /// Restituisce true se la versione del backup può essere importata.
  static bool isCompatible(int? version) {
    final v = version ?? 1; // v1 non aveva il campo → assumiamo 1
    return v >= minSupported && v <= current;
  }

  /// Messaggio di errore user-facing per versione non compatibile.
  static String incompatibleMessage(int? version) {
    final v = version ?? 1;
    if (v < minSupported) {
      return 'Il backup è troppo vecchio (v$v). '
          'Versione minima supportata: v$minSupported.';
    }
    return 'Il backup richiede una versione più recente dell\'app (v$v). '
        'Aggiorna ClimaSense e riprova.';
  }
}
