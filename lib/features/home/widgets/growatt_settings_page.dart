// lib/features/home/widgets/growatt_settings_page.dart
//
// Schermata di configurazione API Token Growatt.
// Accessibile dalle impostazioni dell'app.
//
// Flusso:
//   1. Utente incolla l'API Token generato su server.growatt.com
//      → Settings → API Token
//   2. Tap "Connetti" → fetchToday() con il token → se OK salva con
//      GrowattCredentialsService
//   3. Da quel momento GrowattService può fare fetchToday() automaticamente

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
  final _tokenCtrl = TextEditingController();

  bool _obscureToken = true;
  bool _isLoading = false;
  bool _isConnected = false;

  GrowattData? _lastData;

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedToken() async {
    final token = await GrowattCredentialsService.load();
    if (token != null && mounted) {
      setState(() {
        _tokenCtrl.text = token;
        _isConnected = true;
      });
    }
  }

  Future<void> _onConnect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final service = GrowattService(apiToken: _tokenCtrl.text.trim());
    final fetchResult = await service.fetchToday();
    service.dispose();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (fetchResult is GrowattOk) {
      await GrowattCredentialsService.save(token: _tokenCtrl.text.trim());
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
      _tokenCtrl.clear();
    });
    AppToast.show('Account Growatt rimosso.', context: context, level: ToastLevel.info);
  }

  String _errorMessage(GrowattError e) {
    switch (e.kind) {
      case GrowattErrorKind.authFailed:
        return 'Token non valido. Verifica su server.growatt.com → Settings → API Token.';
      case GrowattErrorKind.networkError:
        return 'Nessuna connessione. Controlla la rete e riprova.';
      case GrowattErrorKind.sessionExpired:
        return 'Token scaduto. Rigenera il token su server.growatt.com.';
      case GrowattErrorKind.plantNotFound:
        return 'Nessun impianto trovato per questo token.';
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

            // ── Istruzioni ───────────────────────────────────────────────
            Text(
              'API Token Growatt',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Incolla il token generato su server.growatt.com → '
              'Settings → API Token. Il token viene salvato in modo '
              'cifrato nel keystore del dispositivo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            Form(
              key: _formKey,
              child: TextFormField(
                controller: _tokenCtrl,
                obscureText: _obscureToken,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API Token',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: const OutlineInputBorder(),
                  hintText: 'Incolla qui il tuo API Token',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureToken
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Inserisci il token API';
                  }
                  return null;
                },
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

            // ── Info API Token ───────────────────────────────────────────
            _ApiTokenInfoCard(),
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

class _ApiTokenInfoCard extends StatelessWidget {
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
                    'Come ottenere il token',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1. Vai su server.growatt.com\n'
                    '2. Accedi con il tuo account\n'
                    '3. Settings → API Token → Generate\n'
                    '4. Copia il token e incollalo qui sopra',
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
