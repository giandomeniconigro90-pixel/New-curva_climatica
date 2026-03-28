/// Costanti globali per i nomi delle stanze.
///
/// Centralizzare qui i nomi permette di modificarli o estenderli
/// in un unico posto senza toccare la logica dell'app.
abstract class RoomConstants {
  /// Lista predefinita delle stanze dell'impianto.
  static const List<String> defaultRooms = [
    'Soggiorno/Cucina',
    'Bagno PT',
    'Cameretta Stefano',
    'Camera Giochi',
    'Camera Mamma e Papà',
    'Bagno 1P',
  ];
}
