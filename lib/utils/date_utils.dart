// lib/utils/date_utils.dart

/// Parsa una data in formato italiano dd/MM/yyyy o ISO yyyy-MM-dd / yyyy-MM-ddTHH:mm:ss.
/// Restituisce null se il formato non è riconosciuto OPPURE se i valori sono
/// fuori range (es. mese 13, giorno 32) — Dart silenziosamente fa overflow
/// su DateTime() senza lanciare eccezioni.
DateTime? parseItalianDateSafe(String s) {
  // Formato italiano dd/MM/yyyy
  final slashParts = s.split('/');
  if (slashParts.length == 3) {
    final d = int.tryParse(slashParts[0]);
    final m = int.tryParse(slashParts[1]);
    final y = int.tryParse(slashParts[2]);
    if (d == null || m == null || y == null) return null;
    if (!_isValidDate(y, m, d)) return null;
    return DateTime(y, m, d);
  }
  // Formato ISO yyyy-MM-dd o yyyy-MM-ddTHH:mm:ss
  try {
    final dt = DateTime.parse(s);
    // DateTime.parse lancia FormatException su formati errati, ma verifichiamo
    // che i valori parsati corrispondano a quelli attesi (nessun overflow).
    if (dt.year < 1900 || dt.year > 2100) return null;
    return dt;
  } catch (_) {}
  return null;
}

/// Verifica che anno/mese/giorno siano in range valido e coerenti tra loro.
bool _isValidDate(int y, int m, int d) {
  if (y < 1900 || y > 2100) return false;
  if (m < 1 || m > 12) return false;
  if (d < 1 || d > _daysInMonth(y, m)) return false;
  return true;
}

/// Restituisce il numero di giorni nel mese dato, anno incluso per i bisestili.
int _daysInMonth(int year, int month) {
  const List<int> days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) return 29;
  return days[month];
}

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);

/// Formatta una data in formato italiano dd/MM/yyyy.
String formatItalianDate(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}
