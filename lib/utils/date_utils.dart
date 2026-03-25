// lib/utils/date_utils.dart

/// Parsa una data in formato italiano dd/MM/yyyy o ISO yyyy-MM-dd / yyyy-MM-ddTHH:mm:ss.
/// Restituisce null se il formato non è riconosciuto.
DateTime? parseItalianDateSafe(String s) {
  // Formato italiano dd/MM/yyyy
  final slashParts = s.split('/');
  if (slashParts.length == 3) {
    final d = int.tryParse(slashParts[0]);
    final m = int.tryParse(slashParts[1]);
    final y = int.tryParse(slashParts[2]);
    if (d != null && m != null && y != null) return DateTime(y, m, d);
  }
  // Formato ISO yyyy-MM-dd o yyyy-MM-ddTHH:mm:ss
  try {
    return DateTime.parse(s);
  } catch (_) {}
  return null;
}

/// Formatta una data in formato italiano dd/MM/yyyy.
String formatItalianDate(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}
