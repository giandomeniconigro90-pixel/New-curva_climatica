// lib/services/growatt_credentials_service.dart
//
// Salva e legge le credenziali Growatt in modo sicuro usando
// flutter_secure_storage (Android Keystore / iOS Keychain).
//
// Le credenziali NON vengono mai scritte in chiaro su disco
// né su SharedPreferences.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GrowattCredentialsService {
  static const _keyUsername = 'growatt_username';
  static const _keyPassword = 'growatt_password';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Salva username e password nel keystore del dispositivo.
  static Future<void> save({
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
  }

  /// Legge le credenziali salvate.
  /// Restituisce null se non sono state ancora inserite.
  static Future<({String username, String password})?> load() async {
    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);
    if (username == null || password == null) return null;
    return (username: username, password: password);
  }

  /// Cancella le credenziali salvate (logout).
  static Future<void> clear() async {
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
  }

  /// Restituisce true se le credenziali sono già state salvate.
  static Future<bool> hasCredentials() async {
    final creds = await load();
    return creds != null;
  }
}
