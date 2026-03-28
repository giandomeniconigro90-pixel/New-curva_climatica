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

          // ── SEZIONE 1: CONCETTI BASE ─────────────────────────────────────
          _buildSectionTitle(context, 'Concetti Base'),
          _buildExpandableCard(
            context: context,
            icon: Icons.thermostat,
            iconColor: Colors.orange,
            title: 'Cos\u2019\u00e8 la Curva Climatica?',
            content:
                'La curva climatica (o curva di riscaldamento) è una legge che dice alla pompa di calore o alla caldaia a che temperatura portare l\u2019acqua che circola nell\u2019impianto (termosifoni, pannelli radianti, fancoil), in funzione della temperatura esterna.\n\n'
                'Esempio pratico:\n'
                '\u2022 Fuori ci sono -5 ℃ → l\u2019acqua va scaldata a 50 ℃\n'
                '\u2022 Fuori ci sono +10 ℃ → l\u2019acqua va scaldata a 38 ℃\n\n'
                'L\u2019obiettivo è mantenere la casa a 20 ℃ senza accensioni e spegnimenti continui (on/off), ma con un funzionamento continuo e modulante. Questo risparmia energia e aumenta il comfort.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.show_chart,
            iconColor: Colors.blue,
            title: 'Pendenza (Slope)',
            content:
                'La pendenza determina quanto velocemente sale la temperatura di mandata al calare di quella esterna.\n\n'
                '• Pendenza alta (es. 2.0): l\u2019acqua si scalda molto al calare del freddo. Adatta a case poco isolate o con termosifoni.\n'
                '• Pendenza bassa (es. 0.5): variazione più dolce. Adatta a case ben isolate o con pannelli radianti a pavimento.\n\n'
                'Regola pratica:\n'
                '  - Se in inverno hai freddo quando fuori fa molto freddo → aumenta la pendenza.\n'
                '  - Se hai caldo quando fuori fa meno freddo → riduci la pendenza.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.height,
            iconColor: Colors.purple,
            title: 'Parallela (Offset)',
            content:
                'L\u2019offset sposta tutta la curva verso l\u2019alto o verso il basso, senza cambiarne la forma.\n\n'
                '• Offset positivo (+3): l\u2019acqua è sempre più calda di 3 ℃. Utile se casa sempre fredda a prescindere dalla temperatura esterna.\n'
                '• Offset negativo (-2): l\u2019acqua è sempre più fresca di 2 ℃. Utile se casa sempre troppo calda.\n\n'
                'Regola pratica: se la casa è sempre troppo fredda O sempre troppo calda indipendentemente dalla stagione, agisci sull\u2019offset. Se il problema si manifesta solo con temperature esterne estreme, agisci sulla pendenza.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.ac_unit,
            iconColor: Colors.cyan,
            title: 'Modalità Riscaldamento vs Raffrescamento',
            content:
                'L\u2019app gestisce due modalità separate, ognuna con la propria curva:\n\n'
                '• Riscaldamento (Inverno): attiva da autunno a primavera. La temperatura di mandata sale al calare di quella esterna.\n'
                '• Raffrescamento (Estate): attiva in estate. La temperatura di mandata dell\u2019acqua fredda sale all\u2019aumentare di quella esterna (più caldo fuori, più fredda l\u2019acqua).\n\n'
                'Le due curve, i registramenti e le analisi AI sono completamente separati. Cambia modalità con il toggle in alto nella pagina Registra.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 2: FLUSSO QUOTIDIANO ─────────────────────────────────
          _buildSectionTitle(context, 'Utilizzo Quotidiano'),
          _buildExpandableCard(
            context: context,
            icon: Icons.edit_note,
            iconColor: Colors.green,
            title: 'Come Registrare un Dato Giornaliero',
            content:
                'Ogni giorno, preferibilmente alla stessa ora (es. mattina), compila:\n\n'
                '1. Temperatura Esterna: quella che leggi dal tuo sensore esterno o da un\u2019app meteo. È il dato più importante.\n'
                '2. Consumo: kWh giornalieri letti dal contatore o dal display della PdC.\n'
                '3. Temperature Interne: la temperatura misurata in ogni stanza.\n'
                '4. Comfort per stanza: indica se la stanza era Fredda ☃, Ok ✔ o Calda ☀.\n'
                '5. Note (opzionale): qualsiasi osservazione utile (es. \u201cfinestre aperte\u201d, \u201cospiti\u201d).\n\n'
                'Premi SALVA. Il dato viene memorizzato con la data di oggi.\n\n'
                'Consiglio: usa il pulsante \u201cCopia dall\u2019ultima registrazione\u201d per pre-compilare le temperature interne se sono simili al giorno precedente.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.edit,
            iconColor: Colors.amber,
            title: 'Modificare o Eliminare una Registrazione',
            content:
                'Nella pagina Storico trovi tutte le registrazioni in ordine cronologico.\n\n'
                '• Per modificare: tocca il record desiderato → i campi vengono pre-compilati nella pagina Registra → modifica e premi AGGIORNA. Il toast mostrerà la data del record aggiornato.\n\n'
                '• Per eliminare: scorri il record verso sinistra e conferma. Oppure usa \u201cElimina oggi\u201d dal menu in alto per cancellare rapidamente il record di oggi.\n\n'
                'Nota: non è possibile inserire due registrazioni per la stessa data e modalità. Se esiste già un record per oggi, l\u2019app ti avvisa e devi modificare quello esistente.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 3: AI E ANALISI ───────────────────────────────────────
          _buildSectionTitle(context, 'Intelligenza Artificiale'),
          _buildExpandableCard(
            context: context,
            icon: Icons.psychology,
            iconColor: Colors.indigo,
            title: 'Come Funziona l\u2019AI',
            content:
                'L\u2019AI di ClimaSense analizza le registrazioni per suggerire una curva climatica ottimizzata. Il processo ha 3 fasi:\n\n'
                '1. Apprendimento (0–4 giorni): con meno di 5 dati l\u2019AI non ha ancora abbastanza informazioni. Il suggerimento è sospeso.\n\n'
                '2. Analisi (5+ giorni): l\u2019AI conta i giorni con comfort \u201cfreddo\u201d, \u201cok\u201d e \u201ccaldo\u201d, e decide la direzione del cambiamento:\n'
                '   • Più giorni freddi → aumenta offset (e pendenza se >30% freddi)\n'
                '   • Più giorni caldi → riduce offset\n'
                '   • Tutti ok → ottimizza i consumi riducendo leggermente la potenza\n\n'
                '3. Prudenza: la modifica massima per applicazione è di ±0.1 sulla pendenza e ±1.0 sull\u2019offset. Non ci sono salti bruschi.\n\n'
                'Dopo aver applicato la curva AI, l\u2019app attende 5 nuovi giorni prima di fare un\u2019altra analisi.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.bar_chart,
            iconColor: Colors.teal,
            title: 'Punteggio Comfort & Energia',
            content:
                '• Punteggio Comfort: percentuale di giorni con valutazione \u201cok\u201d sul totale dei giorni analizzati. 100% = sempre confortevole.\n\n'
                '• Punteggio Energia: indice relativo ai consumi medi. L\u2019obiettivo è mantenere il massimo comfort con il minimo consumo.\n\n'
                'Questi punteggi sono visibili nella pagina Analisi e nel report PDF.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.timeline,
            iconColor: Colors.green,
            title: 'Interpretare il Grafico della Curva',
            content:
                'Il grafico mostra la temperatura di mandata (asse Y) in funzione della temperatura esterna (asse X).\n\n'
                '• Linea blu piena: la curva attualmente impostata.\n'
                '• Linea verde tratteggiata: la curva suggerita dall\u2019AI (visibile solo se l\u2019AI ha un suggerimento attivo).\n\n'
                'Zona rossa (in basso nel grafico):\n'
                '  - Inverno: temperature di mandata <35 ℃. Poco efficiente per termosifoni tradizionali, ma ok per pannelli a pavimento.\n'
                '  - Estate: temperature di mandata <15 ℃. Alto rischio di condensa sui terminali.\n\n'
                'Se la curva attuale tocca spesso la zona rossa in inverno, considera di aumentare pendenza o offset.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 4: COMFORT E STANZE ───────────────────────────────────
          _buildSectionTitle(context, 'Comfort e Stanze'),
          _buildExpandableCard(
            context: context,
            icon: Icons.meeting_room_outlined,
            iconColor: Colors.brown,
            title: 'Gestione Stanze',
            content:
                'Puoi configurare le stanze della tua casa per registrare temperatura e comfort stanza per stanza.\n\n'
                'Come aggiungere/rimuovere stanze: vai in Guida → Gestisci Stanze e usa i controlli presenti.\n\n'
                'Le stanze vengono usate:\n'
                '• Nel form di registrazione per inserire la temperatura di ogni locale.\n'
                '• Nella pagina Stanze (se presente) per una panoramica live.\n'
                '• Nell\u2019analisi AI: se una stanza specifica è sempre fredda o calda, indica un problema localizzato (bilanciamento impianto, valvola, esposizione solare).',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.sentiment_satisfied_alt,
            iconColor: Colors.orange,
            title: 'Come Valutare il Comfort',
            content:
                'Per ogni stanza scegli:\n\n'
                '☃ Freddo: la stanza non raggiunge la temperatura desiderata. Suggerisce di aumentare la potenza dell\u2019impianto.\n'
                '✔ Ok: comfort ottimale. L\u2019obiettivo da mantenere.\n'
                '☀ Caldo: la stanza è surriscaldata. Suggerisce di ridurre la potenza o ribilanciare l\u2019impianto.\n\n'
                'Consiglio: se solo una stanza è sempre fredda mentre le altre sono ok, il problema non è la curva climatica ma il bilanciamento idraulico o una valvola termostatica da regolare.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 5: TILE ESTERNA ───────────────────────────────────────
          _buildSectionTitle(context, 'Tile Temperatura Esterna'),
          _buildExpandableCard(
            context: context,
            icon: Icons.wb_sunny_outlined,
            iconColor: Colors.amber,
            title: 'Cos\u2019è e Come Si Aggiorna',
            content:
                'La tile \u201cEsterna\u201d nella home mostra la temperatura esterna rilevata automaticamente dalla posizione GPS (solo con connessione internet).\n\n'
                'Il sottotitolo indica quando è stato aggiornato:\n'
                '• \u201cBenessere\u201d: dato mai caricato in questa sessione.\n'
                '• \u201cAdesso\u201d: aggiornato meno di un minuto fa.\n'
                '• \u201c5 min fa\u201d, \u201c12 min fa\u201d…: indica il tempo trascorso dalla cache.\n'
                '• Nome città (es. \u201cBologna\u201d): il dato è stato appena scaricato in questa sessione.\n\n'
                'La temperatura scaricata può essere usata come suggerimento per compilare il campo \u201cTemperatura Esterna\u201d nel form di registrazione.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 6: NOTIFICHE ──────────────────────────────────────────
          _buildSectionTitle(context, 'Notifiche'),
          _buildExpandableCard(
            context: context,
            icon: Icons.notifications_outlined,
            iconColor: Colors.blue,
            title: 'Promemoria Giornaliero',
            content:
                'Puoi impostare un promemoria giornaliero che ti ricorda di inserire i dati.\n\n'
                'Come impostarlo: dal menu in alto (icona ⋮) → \u201cImpostazioni Notifica\u201d → scegli l\u2019ora.\n\n'
                'Consiglio: imposta il promemoria la mattina, sempre alla stessa ora. La costanza dei dati è fondamentale per ottenere buoni risultati dall\u2019AI.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 7: STRUMENTI AVANZATI ─────────────────────────────────
          _buildSectionTitle(context, 'Strumenti Avanzati'),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.meeting_room_outlined, color: Colors.teal),
              title: const Text('Gestisci Stanze'),
              subtitle: const Text('Aggiungi, rimuovi o riordina le stanze dell\u2019impianto'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onManageRooms,
            ),
          ),
          const SizedBox(height: 12),

          _buildThemeCard(context),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined, color: Colors.green),
                  title: const Text('Esporta CSV'),
                  subtitle: const Text('Storico completo in formato foglio di calcolo'),
                  onTap: onExportCsv,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
                  title: const Text('Esporta PDF'),
                  subtitle: const Text('Report completo con grafico, statistiche e suggerimento AI'),
                  onTap: onExportPdf,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
                  title: const Text('Backup Dati'),
                  subtitle: const Text('Salva storico e impostazioni in un file JSON'),
                  onTap: onBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined, color: Colors.orange),
                  title: const Text('Ripristina Backup'),
                  subtitle: const Text('Carica un file .json salvato in precedenza'),
                  onTap: onRestore,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Reset Calibrazione'),
                  subtitle: const Text(
                      'Riporta pendenza e offset ai valori di fabbrica. Non cancella lo storico.'),
                  onTap: onResetCalibration,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 8: FAQ ────────────────────────────────────────────────
          _buildSectionTitle(context, 'Domande Frequenti'),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'L\u2019AI non mi dà suggerimenti, perché?',
            content:
                'Ci sono 3 motivi possibili:\n\n'
                '1. Meno di 5 registrazioni: l\u2019AI ha bisogno di almeno 5 giorni di dati validi per la modalità corrente.\n\n'
                '2. Curva appena modificata: dopo ogni applicazione AI, l\u2019app attende 5 giorni di NUOVI dati prima di fare una nuova analisi.\n\n'
                '3. Curva già ottimale: se i suggerimenti AI coincidono con i valori attuali (Δ<0.05), l\u2019app lo segnala e non modifica nulla.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Posso usare l\u2019app senza internet?',
            content:
                'Sì, completamente. Tutte le registrazioni, l\u2019analisi AI, il grafico, l\u2019export CSV e PDF funzionano offline.\n\n'
                'Solo la temperatura esterna automatica (tile \u201cEsterna\u201d) richiede connessione internet. Senza internet puoi inserirla manualmente nel form.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Ho cambiato modalità ma non vedo i dati precedenti',
            content:
                'I dati di riscaldamento e raffrescamento sono separati per design. Quando sei in modalità Riscaldamento vedi solo i record invernali, e viceversa.\n\n'
                'Il backup JSON include ENTRAMBE le modalità, quindi i dati non vengono persi.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Quanto spesso devo applicare la curva AI?',
            content:
                'Non esiste una frequenza fissa. L\u2019AI ti suggerirà una modifica solo quando ha abbastanza dati e il suggerimento differisce significativamente dalla curva attuale.\n\n'
                'In pratica, nelle prime settimane di utilizzo potresti applicarla ogni 5–10 giorni per calibrare la curva. A regime (casa ben calibrata), potrebbe passare molto tempo tra una modifica e l\u2019altra.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Reset Calibrazione vs Ripristina Backup: qual è la differenza?',
            content:
                '• Reset Calibrazione: azzera SOLO i parametri della curva (pendenza e offset) ai valori predefiniti. Lo storico delle registrazioni rimane intatto.\n\n'
                '• Ripristina Backup: sovrascrive TUTTO (storico + impostazioni) con il contenuto del file .json scelto. È un\u2019operazione irreversibile: fai un backup prima.',
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

  // ── WIDGETS ────────────────────────────────────────────────────────────────

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
              style: const ButtonStyle(
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
          'Tutto quello che devi sapere per usare ClimaSense al meglio.',
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

  /// Card espandibile con ExpansionTile per non appesantire lo scroll
  Widget _buildExpandableCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: iconColor, size: 24),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        childrenPadding:
            const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
