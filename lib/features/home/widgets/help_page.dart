// lib/features/home/widgets/help_page.dart

import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  // Aggiungiamo i callback necessari
  final VoidCallback? onResetCalibration;
  final VoidCallback? onBackup;
  final VoidCallback? onRestore;

  const HelpPage({
    super.key,
    this.onResetCalibration,
    this.onBackup,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildSectionTitle('Come Funziona'),
          _buildCard(
            icon: Icons.thermostat,
            title: 'Curva Climatica',
            content:
            'La curva climatica regola la temperatura di mandata dell\'acqua in base alla temperatura esterna. Più fa freddo fuori, più calda sarà l\'acqua nei termosifoni/pavimento.',
          ),
          const SizedBox(height: 12),
          _buildCard(
            icon: Icons.auto_graph,
            title: 'Pendenza (Slope) & Offset',
            content:
            '• Pendenza: Quanto aggressivamente aumenta la temperatura di mandata al calare di quella esterna.\n• Offset: Sposta l\'intera curva su o giù (parallela) per correggere la temperatura interna media.',
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Strumenti Avanzati'),

          // Sezione Backup & Ripristino
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

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guida & Supporto',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey[900],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Qui trovi spiegazioni su come interpretare i dati e gestire l\'app.',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard({required IconData icon, required String title, required String content}) {
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
