// lib/features/home/widgets/help_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/hive_storage.dart';
import '../../../services/theme_notifier.dart';

class HelpPage extends StatefulWidget {
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
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  late TextEditingController _cityController;
  String? _savedCity;

  @override
  void initState() {
    super.initState();
    _savedCity = AppStorage.getCityOverride();
    _cityController = TextEditingController(text: _savedCity ?? '');
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _saveCity() async {
    final city = _cityController.text.trim();
    await AppStorage.saveCityOverride(city.isEmpty ? null : city);
    setState(() => _savedCity = city.isEmpty ? null : city);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            city.isEmpty
                ? 'Città rimossa: verrà usato il GPS'
                : 'Città impostata: $city',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),

          // ── SEZIONE 1: CONCETTI BASE ─────────────────────────────────
          _buildSectionTitle(context, 'Concetti Base'),
          _buildExpandableCard(
            context: context,
            icon: Icons.thermostat,
            iconColor: Colors.orange,
            title: 'Cos\u2019\u00e8 la Curva Climatica?',
            content:
                'La curva climatica (o curva di riscaldamento) \u00e8 una legge che dice alla pompa di calore o alla caldaia a che temperatura portare l\u2019acqua che circola nell\u2019impianto (termosifoni, pannelli radianti, fancoil), in funzione della temperatura esterna.\n\n'
                'Esempio pratico:\n'
                '\u2022 Fuori ci sono -5 \u2103 \u2192 l\u2019acqua va scaldata a 50 \u2103\n'
                '\u2022 Fuori ci sono +10 \u2103 \u2192 l\u2019acqua va scaldata a 38 \u2103\n\n'
                'L\u2019obiettivo \u00e8 mantenere la casa a 20 \u2103 senza accensioni e spegnimenti continui (on/off), ma con un funzionamento continuo e modulante. Questo risparmia energia e aumenta il comfort.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.show_chart,
            iconColor: Colors.blue,
            title: 'Pendenza (Slope)',
            content:
                'La pendenza determina quanto velocemente sale la temperatura di mandata al calare di quella esterna.\n\n'
                '\u2022 Pendenza alta (es. 2.0): l\u2019acqua si scalda molto al calare del freddo. Adatta a case poco isolate o con termosifoni.\n'
                '\u2022 Pendenza bassa (es. 0.5): variazione pi\u00f9 dolce. Adatta a case ben isolate o con pannelli radianti a pavimento.\n\n'
                'Regola pratica:\n'
                '  - Se in inverno hai freddo quando fuori fa molto freddo \u2192 aumenta la pendenza.\n'
                '  - Se hai caldo quando fuori fa meno freddo \u2192 riduci la pendenza.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.height,
            iconColor: Colors.purple,
            title: 'Parallela (Offset)',
            content:
                'L\u2019offset sposta tutta la curva verso l\u2019alto o verso il basso, senza cambiarne la forma.\n\n'
                '\u2022 Offset positivo (+3): l\u2019acqua \u00e8 sempre pi\u00f9 calda di 3 \u2103. Utile se casa sempre fredda a prescindere dalla temperatura esterna.\n'
                '\u2022 Offset negativo (-2): l\u2019acqua \u00e8 sempre pi\u00f9 fresca di 2 \u2103. Utile se casa sempre troppo calda.\n\n'
                'Regola pratica: se la casa \u00e8 sempre troppo fredda O sempre troppo calda indipendentemente dalla stagione, agisci sull\u2019offset. Se il problema si manifesta solo con temperature esterne estreme, agisci sulla pendenza.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.ac_unit,
            iconColor: Colors.cyan,
            title: 'Modalit\u00e0 Riscaldamento vs Raffrescamento',
            content:
                'L\u2019app gestisce due modalit\u00e0 separate, ognuna con la propria curva:\n\n'
                '\u2022 Riscaldamento (Inverno): attiva da autunno a primavera. La temperatura di mandata sale al calare di quella esterna.\n'
                '\u2022 Raffrescamento (Estate): attiva in estate. La temperatura di mandata dell\u2019acqua fredda sale all\u2019aumentare di quella esterna (pi\u00f9 caldo fuori, pi\u00f9 fredda l\u2019acqua).\n\n'
                'Le due curve, i registramenti e le analisi AI sono completamente separati. Cambia modalit\u00e0 con il toggle in alto nella pagina Registra.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 2: FLUSSO QUOTIDIANO ───────────────────────────────
          _buildSectionTitle(context, 'Utilizzo Quotidiano'),
          _buildExpandableCard(
            context: context,
            icon: Icons.edit_note,
            iconColor: Colors.green,
            title: 'Come Registrare un Dato Giornaliero',
            content:
                'Ogni giorno, preferibilmente alla stessa ora (es. mattina), compila:\n\n'
                '1. Temperatura Esterna: quella che leggi dal tuo sensore esterno o da un\u2019app meteo. \u00c8 il dato pi\u00f9 importante.\n'
                '2. Consumo: kWh giornalieri letti dal contatore o dal display della PdC.\n'
                '3. Temperature Interne: la temperatura misurata in ogni stanza.\n'
                '4. Comfort per stanza: indica se la stanza era Fredda \u2603, Ok \u2714 o Calda \u2600.\n'
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
                '\u2022 Per modificare: tocca il record desiderato \u2192 i campi vengono pre-compilati nella pagina Registra \u2192 modifica e premi AGGIORNA. Il toast mostrer\u00e0 la data del record aggiornato.\n\n'
                '\u2022 Per eliminare: scorri il record verso sinistra e conferma. Oppure usa \u201cElimina oggi\u201d dal menu in alto per cancellare rapidamente il record di oggi.\n\n'
                'Nota: non \u00e8 possibile inserire due registrazioni per la stessa data e modalit\u00e0. Se esiste gi\u00e0 un record per oggi, l\u2019app ti avvisa e devi modificare quello esistente.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 3: AI E ANALISI ──────────────────────────────────────
          _buildSectionTitle(context, 'Intelligenza Artificiale'),
          _buildExpandableCard(
            context: context,
            icon: Icons.psychology,
            iconColor: Colors.indigo,
            title: 'Come Funziona l\u2019AI',
            content:
                'L\u2019AI di ClimaSense analizza le registrazioni per suggerire una curva climatica ottimizzata. Il processo ha 3 fasi:\n\n'
                '1. Apprendimento (0\u20134 giorni): con meno di 5 dati l\u2019AI non ha ancora abbastanza informazioni. Il suggerimento \u00e8 sospeso.\n\n'
                '2. Analisi (5+ giorni): l\u2019AI conta i giorni con comfort \u201cfreddo\u201d, \u201cok\u201d e \u201ccaldo\u201d, e decide la direzione del cambiamento:\n'
                '   \u2022 Pi\u00f9 giorni freddi \u2192 aumenta offset (e pendenza se >30% freddi)\n'
                '   \u2022 Pi\u00f9 giorni caldi \u2192 riduce offset\n'
                '   \u2022 Tutti ok \u2192 ottimizza i consumi riducendo leggermente la potenza\n\n'
                '3. Prudenza: la modifica massima per applicazione \u00e8 di \u00b10.1 sulla pendenza e \u00b11.0 sull\u2019offset. Non ci sono salti bruschi.\n\n'
                'Dopo aver applicato la curva AI, l\u2019app attende 5 nuovi giorni prima di fare un\u2019altra analisi.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.bar_chart,
            iconColor: Colors.teal,
            title: 'Punteggio Comfort & Energia',
            content:
                '\u2022 Punteggio Comfort: percentuale di giorni con valutazione \u201cok\u201d sul totale dei giorni analizzati. 100% = sempre confortevole.\n\n'
                '\u2022 Punteggio Energia: indice relativo ai consumi medi. L\u2019obiettivo \u00e8 mantenere il massimo comfort con il minimo consumo.\n\n'
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
                '\u2022 Linea blu piena: la curva attualmente impostata.\n'
                '\u2022 Linea verde tratteggiata: la curva suggerita dall\u2019AI (visibile solo se l\u2019AI ha un suggerimento attivo).\n\n'
                'Zona rossa (in basso nel grafico):\n'
                '  - Inverno: temperature di mandata <35 \u2103. Poco efficiente per termosifoni tradizionali, ma ok per pannelli a pavimento.\n'
                '  - Estate: temperature di mandata <15 \u2103. Alto rischio di condensa sui terminali.\n\n'
                'Se la curva attuale tocca spesso la zona rossa in inverno, considera di aumentare pendenza o offset.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 4: COMFORT E STANZE ────────────────────────────────
          _buildSectionTitle(context, 'Comfort e Stanze'),
          _buildExpandableCard(
            context: context,
            icon: Icons.meeting_room_outlined,
            iconColor: Colors.brown,
            title: 'Gestione Stanze',
            content:
                'Puoi configurare le stanze della tua casa per registrare temperatura e comfort stanza per stanza.\n\n'
                'Come aggiungere/rimuovere stanze: vai in Guida \u2192 Gestisci Stanze e usa i controlli presenti.\n\n'
                'Le stanze vengono usate:\n'
                '\u2022 Nel form di registrazione per inserire la temperatura di ogni locale.\n'
                '\u2022 Nella pagina Stanze (se presente) per una panoramica live.\n'
                '\u2022 Nell\u2019analisi AI: se una stanza specifica \u00e8 sempre fredda o calda, indica un problema localizzato (bilanciamento impianto, valvola, esposizione solare).',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.sentiment_satisfied_alt,
            iconColor: Colors.orange,
            title: 'Come Valutare il Comfort',
            content:
                'Per ogni stanza scegli:\n\n'
                '\u2603 Freddo: la stanza non raggiunge la temperatura desiderata. Suggerisce di aumentare la potenza dell\u2019impianto.\n'
                '\u2714 Ok: comfort ottimale. L\u2019obiettivo da mantenere.\n'
                '\u2600 Caldo: la stanza \u00e8 surriscaldata. Suggerisce di ridurre la potenza o ribilanciare l\u2019impianto.\n\n'
                'Consiglio: se solo una stanza \u00e8 sempre fredda mentre le altre sono ok, il problema non \u00e8 la curva climatica ma il bilanciamento idraulico o una valvola termostatica da regolare.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 5: TILE ESTERNA ──────────────────────────────────────
          _buildSectionTitle(context, 'Tile Temperatura Esterna'),
          _buildExpandableCard(
            context: context,
            icon: Icons.wb_sunny_outlined,
            iconColor: Colors.amber,
            title: 'Cos\u2019\u00e8 e Come Si Aggiorna',
            content:
                'La tile \u201cEsterna\u201d nella home mostra la temperatura esterna rilevata automaticamente dalla posizione GPS (solo con connessione internet).\n\n'
                'Il sottotitolo indica quando \u00e8 stato aggiornato:\n'
                '\u2022 \u201cBenessere\u201d: dato mai caricato in questa sessione.\n'
                '\u2022 \u201cAdesso\u201d: aggiornato meno di un minuto fa.\n'
                '\u2022 \u201c5 min fa\u201d, \u201c12 min fa\u201d\u2026: indica il tempo trascorso dalla cache.\n'
                '\u2022 Nome citt\u00e0 (es. \u201cBologna\u201d): il dato \u00e8 stato appena scaricato in questa sessione.\n\n'
                'La temperatura scaricata pu\u00f2 essere usata come suggerimento per compilare il campo \u201cTemperatura Esterna\u201d nel form di registrazione.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 6: NOTIFICHE ────────────────────────────────────────
          _buildSectionTitle(context, 'Notifiche'),
          _buildExpandableCard(
            context: context,
            icon: Icons.notifications_outlined,
            iconColor: Colors.blue,
            title: 'Promemoria Giornaliero',
            content:
                'Puoi impostare un promemoria giornaliero che ti ricorda di inserire i dati.\n\n'
                'Come impostarlo: dal menu in alto (icona \u22ee) \u2192 \u201cImpostazioni Notifica\u201d \u2192 scegli l\u2019ora.\n\n'
                'Consiglio: imposta il promemoria la mattina, sempre alla stessa ora. La costanza dei dati \u00e8 fondamentale per ottenere buoni risultati dall\u2019AI.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 7: CASA X-LAM E VMC ────────────────────────────────
          _buildSectionTitle(context, 'Casa X-LAM + VMC con Recuperatore'),
          _buildExpandableCard(
            context: context,
            icon: Icons.home_work_outlined,
            iconColor: Colors.green,
            title: 'Valori di Partenza Consigliati per X-LAM',
            content:
                'Una casa in X-LAM ha un\u2019inerzia termica molto alta e dispersioni ridotte. Questo significa che risponde lentamente alle variazioni di temperatura esterna e mantiene il calore a lungo.\n\n'
                'Valori di partenza consigliati:\n'
                '\u2022 Pendenza (slope): 0.8 \u2014 bassa perch\u00e9 la casa \u00e8 ben isolata e non ha bisogno di grandi variazioni di mandata.\n'
                '\u2022 Offset: 0.0 \u2014 neutro come punto di partenza; alzalo di +1 o +2 solo se la casa risulta sistematicamente fresca.\n\n'
                'Confronto con case tradizionali:\n'
                '\u2022 Casa poco isolata / termosifoni: slope 1.5\u20132.0\n'
                '\u2022 Casa media / fan coil: slope 1.0\u20131.3\n'
                '\u2022 Casa ben isolata / pannelli a pavimento: slope 0.6\u20130.9\n'
                '\u2022 X-LAM con VMC: slope 0.7\u20130.9 (consigliato: 0.8)',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.air,
            iconColor: Colors.lightBlue,
            title: 'Come la VMC con Recuperatore Influenza i Parametri',
            content:
                'La VMC (Ventilazione Meccanica Controllata) con recuperatore di calore recupera il 70\u201390% del calore dall\u2019aria espulsa, riducendo significativamente le dispersioni termiche.\n\n'
                'Effetti pratici sulla curva climatica:\n'
                '\u2022 L\u2019impianto di riscaldamento deve \'integrare\' meno: la VMC mantiene gi\u00e0 buona parte del calore.\n'
                '\u2022 Le variazioni di temperatura esterna impattano meno sulla temperatura interna \u2192 la pendenza ottimale \u00e8 pi\u00f9 bassa.\n'
                '\u2022 L\u2019offset pu\u00f2 restare vicino allo zero: piccole correzioni (+1 o -1) sono di solito sufficienti.\n\n'
                'Con VMC + recuperatore, l\u2019AI impiegher\u00e0 meno aggiustamenti per trovare il punto ottimale perch\u00e9 il sistema \u00e8 intrinsecamente pi\u00f9 stabile. Segnali confortevoli anche con piccole variazioni di offset sono normali.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.checklist_rtl,
            iconColor: Colors.teal,
            title: '\ud83d\ude80 Primi Passi: Checklist per il Nuovo Utente',
            content:
                'Segui questi passi per impostare correttamente l\u2019app dal primo giorno:\n\n'
                '1\ufe0f\u20e3  Configura le stanze: vai in Guida \u2192 Gestisci Stanze e aggiungi i locali della tua casa.\n\n'
                '2\ufe0f\u20e3  Imposta i valori iniziali: se hai una casa X-LAM + VMC, usa slope 0.8 e offset 0.0 come punto di partenza (vedi \u201cValori di Partenza Consigliati\u201d).\n\n'
                '3\ufe0f\u20e3  Inizia a registrare: ogni giorno, preferibilmente alla stessa ora, inserisci temperatura esterna, consumo, temperature interne e comfort.\n\n'
                '4\ufe0f\u20e3  Attendi 5 giorni: dopo 5 registrazioni l\u2019AI sar\u00e0 pronta a suggerire una prima ottimizzazione.\n\n'
                '5\ufe0f\u20e3  Applica il suggerimento AI: valuta il suggerimento nella pagina Analisi. Se ti convince, premi \u201cApplica Curva AI\u201d.\n\n'
                '6\ufe0f\u20e3  Ripeti: dopo ogni applicazione, l\u2019AI attende altri 5 giorni di nuovi dati. Con il tempo la curva converger\u00e0 ai valori ottimali per la tua casa.\n\n'
                'Consiglio finale: imposta un promemoria giornaliero (Guida \u2192 Impostazioni Notifica) per non dimenticare la registrazione!',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 8: STRUMENTI AVANZATI ──────────────────────────────
          _buildSectionTitle(context, 'Strumenti Avanzati'),

          // ── CARD CITTÀ METEO ──────────────────────────────────────────
          _buildCityCard(context),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.meeting_room_outlined, color: Colors.teal),
              title: const Text('Gestisci Stanze'),
              subtitle: const Text('Aggiungi, rimuovi o riordina le stanze dell\u2019impianto'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onManageRooms,
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
                  onTap: widget.onExportCsv,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
                  title: const Text('Esporta PDF'),
                  subtitle: const Text('Report completo con grafico, statistiche e suggerimento AI'),
                  onTap: widget.onExportPdf,
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
                  onTap: widget.onBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined, color: Colors.orange),
                  title: const Text('Ripristina Backup'),
                  subtitle: const Text('Carica un file .json salvato in precedenza'),
                  onTap: widget.onRestore,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Reset Calibrazione'),
                  subtitle: const Text(
                      'Riporta pendenza e offset ai valori di fabbrica. Non cancella lo storico.'),
                  onTap: widget.onResetCalibration,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 9: FAQ ────────────────────────────────────────────────
          _buildSectionTitle(context, 'Domande Frequenti'),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'L\u2019AI non mi d\u00e0 suggerimenti, perch\u00e9?',
            content:
                'Ci sono 3 motivi possibili:\n\n'
                '1. Meno di 5 registrazioni: l\u2019AI ha bisogno di almeno 5 giorni di dati validi per la modalit\u00e0 corrente.\n\n'
                '2. Curva appena modificata: dopo ogni applicazione AI, l\u2019app attende 5 giorni di NUOVI dati prima di fare una nuova analisi.\n\n'
                '3. Curva gi\u00e0 ottimale: se i suggerimenti AI coincidono con i valori attuali (\u03940.05), l\u2019app lo segnala e non modifica nulla.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Posso usare l\u2019app senza internet?',
            content:
                'S\u00ec, completamente. Tutte le registrazioni, l\u2019analisi AI, il grafico, l\u2019export CSV e PDF funzionano offline.\n\n'
                'Solo la temperatura esterna automatica (tile \u201cEsterna\u201d) richiede connessione internet. Senza internet puoi inserirla manualmente nel form.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Ho cambiato modalit\u00e0 ma non vedo i dati precedenti',
            content:
                'I dati di riscaldamento e raffrescamento sono separati per design. Quando sei in modalit\u00e0 Riscaldamento vedi solo i record invernali, e viceversa.\n\n'
                'Il backup JSON include ENTRAMBE le modalit\u00e0, quindi i dati non vengono persi.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Quanto spesso devo applicare la curva AI?',
            content:
                'Non esiste una frequenza fissa. L\u2019AI ti suggerir\u00e0 una modifica solo quando ha abbastanza dati e il suggerimento differisce significativamente dalla curva attuale.\n\n'
                'In pratica, nelle prime settimane di utilizzo potresti applicarla ogni 5\u201310 giorni per calibrare la curva. A regime (casa ben calibrata), potrebbe passare molto tempo tra una modifica e l\u2019altra.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Reset Calibrazione vs Ripristina Backup: qual \u00e8 la differenza?',
            content:
                '\u2022 Reset Calibrazione: azzera SOLO i parametri della curva (pendenza e offset) ai valori predefiniti. Lo storico delle registrazioni rimane intatto.\n\n'
                '\u2022 Ripristina Backup: sovrascrive TUTTO (storico + impostazioni) con il contenuto del file .json scelto. \u00c8 un\u2019operazione irreversibile: fai un backup prima.',
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

  // ── CARD CITTÀ METEO ─────────────────────────────────────────────────────
  Widget _buildCityCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_city_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Citt\u00e0 Meteo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                if (_savedCity != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _savedCity!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'GPS auto',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Se il GPS non funziona o usi desktop, inserisci il nome della citt\u00e0 per ottenere il meteo. Lascia vuoto per usare il GPS automatico.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'es. Bologna, Milano, Roma\u2026',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _cityController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _cityController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _saveCity(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saveCity,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Salva'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── WIDGETS ───────────────────────────────────────────────────────────────

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
