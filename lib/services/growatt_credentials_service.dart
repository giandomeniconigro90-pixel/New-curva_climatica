// lib/services/growatt_credentials_service.dart
//
// Salva e carica le credenziali Growatt (username + password)
// usando flutter_secure_storage — mai in chiaro nel codice.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GrowattCredentialsService {
  static const _storage = FlutterSecureStorage();
  static const _keyUsername = 'growatt_username';
  static const _keyPassword = 'growatt_password';

  /// Salva username e password
  static Future<void> save(String username, String password) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
  }

  /// Carica le credenziali — restituisce null se non configurate
  static Future<({String username, String password})?> load() async {
    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);
    if (username == null || username.isEmpty ||
        password == null || password.isEmpty) return null;
    return (username: username, password: password);
  }

  /// Elimina le credenziali salvate
  static Future<void> clear() async {
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
  }

  /// True se le credenziali sono già state configurate
  static Future<bool> isConfigured() async {
    final creds = await load();
    return creds != null;
  }
}
