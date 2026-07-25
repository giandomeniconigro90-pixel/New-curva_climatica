// lib/features/home/widgets/growatt_settings_page.dart
//
// Schermata di configurazione credenziali Growatt (username + password).
//
// Flusso:
//   1. Utente inserisce email e password dell'account server.growatt.com
//   2. Tap "Connetti" → GrowattService.fetchToday() (login + fetch)
//   3. Se OK → salva con GrowattCredentialsService e aggiorna il notifier

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/growatt_credentials_service.dart';
import '../../../services/growatt_notifier.dart';
import '../../../services/growatt_service.dart';
import '../../../utils/app_toast.dart';

class GrowattSettingsPage extends StatefulWidget {
  const GrowattSettingsPage({super.key});

  @override
  State<GrowattSettingsPage> createState() => _GrowattSettingsPageState();
}

class _GrowattSettingsPageState extends State<GrowattSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscurePass = true;
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
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await GrowattCredentialsService.load();
    if (creds != null && mounted) {
      setState(() {
        _userCtrl.text = creds.username;
        _passCtrl.text = creds.password;
        _isConnected = true;
      });
    }
  }

  Future<void> _onConnect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final service = GrowattService(
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    final fetchResult = await service.fetchToday();
    service.dispose();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (fetchResult is GrowattOk) {
      await GrowattCredentialsService.save(
        _userCtrl.text.trim(),
        _passCtrl.text,
      );
      // Aggiorna il notifier globale con le nuove credenziali
      if (mounted) {
        await context.read<GrowattNotifier>().reconfigure();
      }
      setState(() {
        _isConnected = true;
        _lastData = fetchResult.data;
      });
      AppToast.show(
        'Growatt connesso! Produzione oggi: '
        '${fetchResult.data.pvTodayKwh.toStringAsFixed(2)} kWh',
        context: context,
        level: ToastLevel.success,
      );
    } else if (fetchResult is GrowattError) {
      AppToast.show(
        _errorMessage(fetchResult),
        context: context,
        level: ToastLevel.error,
      );
    }
  }

  Future<void> _onDisconnect() async {
    await GrowattCredentialsService.clear();
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _lastData = null;
      _userCtrl.clear();
      _passCtrl.clear();
    });
    AppToast.show('Account Growatt rimosso.',
        context: context, level: ToastLevel.info);
  }

  String _errorMessage(GrowattError e) {
    switch (e.kind) {
      case GrowattErrorKind.authFailed:
        return 'Credenziali non valide. Verifica email e password di server.growatt.com.';
      case GrowattErrorKind.networkError:
        return 'Nessuna connessione. Controlla la rete e riprova.';
      case GrowattErrorKind.sessionExpired:
        return 'Sessione scaduta. Riprova.';
      case GrowattErrorKind.plantNotFound:
        return 'Nessun impianto trovato per questo account.';
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
            // ── Stato connessione ─────────────────────────────────────────
            _ConnectionStatusCard(isConnected: _isConnected, data: _lastData),
            const SizedBox(height: 28),

            // ── Titolo sezione ────────────────────────────────────────────
            Text(
              'Accesso Growatt',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Inserisci le credenziali del tuo account server.growatt.com. '
              'Username e password vengono salvati in modo cifrato nel '
              'keystore del dispositivo.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurface.withOpacity(0.6)),
            ),
            const SizedBox(height: 16),

            // ── Form ──────────────────────────────────────────────────────
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Username / email
                  TextFormField(
                    controller: _userCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username / Email',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                      hintText: 'es. mario@email.com',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Inserisci il tuo username o email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Password
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePass
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Inserisci la password';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bottoni ───────────────────────────────────────────────────
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              FilledButton.icon(
                onPressed: _onConnect,
                icon: const Icon(Icons.power_settings_new),
                label: Text(_isConnected ? 'Riconnetti' : 'Connetti'),
              ),
              if (_isConnected) ...[
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

            // ── Info ──────────────────────────────────────────────────────
            _LoginInfoCard(),
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
    final icon =
        isConnected ? Icons.solar_power : Icons.solar_power_outlined;
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
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  if (data != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Oggi: ${data!.pvTodayKwh.toStringAsFixed(2)} kWh  •  '
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

class _LoginInfoCard extends StatelessWidget {
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
                    'Come accedere',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1. Usa le stesse credenziali di server.growatt.com\n'
                    '2. Oppure dell\'app ufficiale Growatt\n'
                    '3. La password viene cifrata MD5 prima dell\'invio',
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
