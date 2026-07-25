// lib/services/growatt_credentials_service.dart
//
// Salva e legge il token API Growatt in modo sicuro usando
// flutter_secure_storage (Android Keystore / iOS Keychain).
//
// Il token NON viene mai scritto in chiaro su disco
// né su SharedPreferences.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GrowattCredentialsService {
  static const _keyToken = 'growatt_api_token';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Salva l'API token nel keystore del dispositivo.
  static Future<void> save({required String token}) async {
    await _storage.write(key: _keyToken, value: token);
  }

  /// Legge il token salvato.
  /// Restituisce null se non è stato ancora inserito.
  static Future<String?> load() async {
    return _storage.read(key: _keyToken);
  }

  /// Cancella il token salvato (logout).
  static Future<void> clear() async {
    await _storage.delete(key: _keyToken);
  }

  /// Restituisce true se il token è già stato salvato.
  static Future<bool> hasToken() async {
    final token = await load();
    return token != null && token.isNotEmpty;
  }
}
