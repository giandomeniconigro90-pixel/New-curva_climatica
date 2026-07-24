// lib/features/home/widgets/growatt_settings_page.dart
//
// Schermata di configurazione credenziali Growatt.
// Accessibile dalle impostazioni dell'app.
//
// Flusso:
//   1. Utente inserisce username (o email) + password Shine Phone
//   2. Tap "Connetti" → login() → se OK salva con GrowattCredentialsService
//   3. Da quel momento GrowattService può fare fetchToday() automaticamente
//
// fix: il campo username accetta sia email (mario@example.com)
//      che username puro (es. "mariobianchi") — Growatt supporta entrambi.

import 'package:flutter/material.dart';
import '../../../services/growatt_credentials_service.dart';
import '../../../services/growatt_service.dart';
import '../../../utils/app_toast.dart';

class GrowattSettingsPage extends StatefulWidget {
  const GrowattSettingsPage({super.key});

  @override
  State<GrowattSettingsPage> createState() => _GrowattSettingsPageState();
}

class _GrowattSettingsPageState extends State<GrowattSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isConnected = false;

  GrowattData? _lastData;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await GrowattCredentialsService.load();
    if (creds != null && mounted) {
      setState(() {
        _usernameCtrl.text = creds.username;
        _passwordCtrl.text = creds.password;
        _isConnected = true;
      });
    }
  }

  Future<void> _onConnect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final service = GrowattService();
    final loginResult = await service.login(
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (!mounted) return;

    if (loginResult is GrowattError) {
      setState(() => _isLoading = false);
      AppToast.show(
        _errorMessage(loginResult),
        context: context,
        level: ToastLevel.error,
      );
      return;
    }

    // Login OK — salva credenziali e fai subito un fetch di test
    await GrowattCredentialsService.save(
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    final fetchResult = await service.fetchToday();
    service.dispose();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (fetchResult is GrowattOk) {
      setState(() {
        _isConnected = true;
        _lastData = fetchResult.data;
      });
      AppToast.show(
        'Growatt connesso! Produzione oggi: ${fetchResult.data.pvTodayKwh.toStringAsFixed(2)} kWh',
        context: context,
        level: ToastLevel.success,
      );
    } else if (fetchResult is GrowattError) {
      setState(() => _isConnected = true); // login OK anche se fetch fallisce
      AppToast.show(
        'Login OK ma fetch dati fallito: ${_errorMessage(fetchResult)}',
        context: context,
        level: ToastLevel.warning,
      );
    }
  }

  Future<void> _onDisconnect() async {
    await GrowattCredentialsService.clear();
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _lastData = null;
      _usernameCtrl.clear();
      _passwordCtrl.clear();
    });
    AppToast.show('Account Growatt rimosso.', context: context, level: ToastLevel.info);
  }

  String _errorMessage(GrowattError e) {
    switch (e.kind) {
      case GrowattErrorKind.authFailed:
        return 'Credenziali errate. Verifica username/email e password Shine Phone.';
      case GrowattErrorKind.networkError:
        return 'Nessuna connessione. Controlla la rete e riprova.';
      case GrowattErrorKind.sessionExpired:
        return 'Sessione scaduta. Riconnetti.';
      case GrowattErrorKind.plantNotFound:
        return 'Impianto non trovato. Verifica il Plant ID.';
      default:
        return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotovoltaico Growatt'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header stato connessione ──────────────────────────────────
            _ConnectionStatusCard(isConnected: _isConnected, data: _lastData),
            const SizedBox(height: 28),

            // ── Form credenziali ─────────────────────────────────────────
            Text(
              'Account Shine Phone',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Inserisci le stesse credenziali che usi per accedere al sito Growatt o all\'app Shine Phone. Puoi usare sia la email che lo username. Le credenziali vengono salvate in modo cifrato nel keystore del dispositivo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  // USERNAME — accetta sia email che username puro
                  TextFormField(
                    controller: _usernameCtrl,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username o Email Shine Phone',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                      hintText: 'es. mario.bianchi oppure mario@example.com',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Inserisci lo username o la email';
                      }
                      return null; // accetta qualsiasi stringa non vuota
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password Shine Phone',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Inserisci la password';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bottoni ──────────────────────────────────────────────────
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...
              [
                FilledButton.icon(
                  onPressed: _onConnect,
                  icon: const Icon(Icons.power_settings_new),
                  label: Text(_isConnected ? 'Riconnetti' : 'Connetti'),
                ),
                if (_isConnected) ...
                  [
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _onDisconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnetti account'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(color: colors.error),
                      ),
                    ),
                  ],
              ],

            const SizedBox(height: 32),

            // ── Info Plant ID ────────────────────────────────────────────
            _PlantIdInfoCard(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget ausiliari
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionStatusCard extends StatelessWidget {
  final bool isConnected;
  final GrowattData? data;

  const _ConnectionStatusCard({required this.isConnected, this.data});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = isConnected ? Colors.green : colors.outline;
    final icon = isConnected ? Icons.solar_power : Icons.solar_power_outlined;
    final label = isConnected ? 'Connesso' : 'Non connesso';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Growatt — Impianto 6kW',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  if (data != null) ...
                    [
                      const SizedBox(height: 4),
                      Text(
                        'Oggi: ${data!.pvTodayKwh.toStringAsFixed(2)} kWh prodotti  •  '
                        '${data!.pvPowerW.toStringAsFixed(0)} W istantanei',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlantIdInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Plant ID configurato',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Plant ID: ${GrowattService.defaultPlantId}\n'
                    'Impianto: Nigro — SantAgata Bolognese\n'
                    'Capacità: 6000 W',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
