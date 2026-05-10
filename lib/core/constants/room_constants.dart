/// Costanti globali per i nomi delle zone termiche.
///
/// L'impianto è diviso in 2 zone controllabili tramite termostato:
/// - Piano Terra  (Soggiorno, Cucina, Bagno PT)
/// - Primo Piano  (Camere, Bagno 1P)
///
/// Centralizzare qui i nomi permette di modificarli o estenderli
/// in un unico posto senza toccare la logica dell'app.
abstract class RoomConstants {
  /// Lista delle zone termiche dell'impianto.
  /// Ogni zona corrisponde a un termostato fisico indipendente.
  static const List<String> defaultRooms = [
    'Piano Terra',
    'Primo Piano',
  ];
}
