// lib/features/home/widgets/help_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/theme_notifier.dart';

class HelpPage extends StatelessWidget {
  final VoidCallback? onResetCalibration;
  final VoidCallback? onBackup;
  final VoidCallback? onRestore;
  final VoidCallback? onExportCsv;
  final VoidCallback? onExportPdf;
  final VoidCallback? onManageRooms;

  const HelpPage({
    super.key,
    this.onResetCalibration,
    this.onBackup,
    this.onRestore,
    this.onExportCsv,
    this.onExportPdf,
    this.onManageRooms,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),
          _buildSectionTitle(context, 'Come Funziona'),
          _buildCard(
            context: context,
            icon: Icons.thermostat,
            title: 'Curva Climatica',
            content:
                'La curva climatica regola la temperatura di mandata dell\'acqua in base alla temperatura esterna. Pi\u00f9 fa freddo fuori, pi\u00f9 calda sar\u00e0 l\'acqua nei termosifoni/pavimento.',
          ),
          const SizedBox(height: 12),
          _buildCard(
            context: context,
            icon: Icons.auto_graph,
            title: 'Pendenza (Slope) & Offset',
            content:
                '\u2022 Pendenza: Quanto aggressivamente aumenta la temperatura di mandata al calare di quella esterna.\n\u2022 Offset: Sposta l\'intera curva su o gi\u00f9 (parallela) per correggere la temperatura interna media.',
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'Strumenti Avanzati'),

          // --- Gestione Stanze ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.meeting_room_outlined, color: Colors.teal),
              title: const Text('Gestisci Stanze'),
              subtitle: const Text('Aggiungi, rimuovi o riordina le stanze dell\'impianto'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onManageRooms,
            ),
          ),
          const SizedBox(height: 16),

          // --- Tema ---
          _buildThemeCard(context),
          const SizedBox(height: 16),

          // --- Export ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined, color: Colors.green),
                  title: const Text('Esporta CSV'),
                  subtitle: const Text('Scarica lo storico in formato foglio di calcolo'),
                  onTap: onExportCsv,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
                  title: const Text('Esporta PDF'),
                  subtitle: const Text('Genera un report completo con grafico'),
                  onTap: onExportPdf,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- Backup & Ripristino ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
                  title: const Text('Backup Dati'),
                  subtitle: const Text('Salva tutto lo storico e le impostazioni'),
                  onTap: onBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined, color: Colors.orange),
                  title: const Text('Ripristina Backup'),
                  subtitle: const Text('Carica un file di backup salvato'),
                  onTap: onRestore,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Reset Calibrazione'),
                  subtitle: const Text('Cancella solo le impostazioni della curva'),
                  onTap: onResetCalibration,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
              'ClimaSense v1.0.0',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildThemeCard(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final current = themeNotifier.themeMode;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.brightness_6_outlined, color: Colors.purple),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Tema',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode, size: 18),
                  tooltip: 'Chiaro',
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto, size: 18),
                  tooltip: 'Sistema',
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode, size: 18),
                  tooltip: 'Scuro',
                ),
              ],
              selected: {current},
              onSelectionChanged: (Set<ThemeMode> selection) {
                themeNotifier.setThemeMode(selection.first);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guida & Supporto',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Qui trovi spiegazioni su come interpretare i dati e gestire l\'app.',
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue[700], size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
