// lib/features/home/widgets/help_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/hive_storage.dart';
import '../../../services/theme_notifier.dart';
import '../../../utils/app_toast.dart';

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
      AppToast.show(
        city.isEmpty
            ? 'Citt\u00e0 rimossa: verr\u00e0 usato il GPS'
            : 'Citt\u00e0 impostata: $city',
        context: context,
        level: ToastLevel.success,
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

          // ── SEZIONE 1: PRIMI PASSI ────────────────────────────────────────
          _buildSectionTitle(context, 'Inizia da Qui'),
          _buildExpandableCard(
            context: context,
            icon: Icons.checklist_rtl,
            iconColor: Colors.teal,
            title: '\ud83d\ude80 Checklist per il Nuovo Utente',
            // FIX #2: passo 7 corretto — la notifica si imposta dall'icona
            // campanella 🔔 in alto a destra nella barra Home, non da un menu ⋮.
            content:
                'Segui questi passi per impostare correttamente l\u2019app dal primo giorno:\n\n'
                '1\ufe0f\u20e3  Configura le stanze: vai in Guida \u2192 Gestisci Stanze e aggiungi i locali della tua casa.\n\n'
                '2\ufe0f\u20e3  Imposta i valori iniziali della curva: se hai una casa X-LAM + VMC usa slope 0.8 e offset 0.0 come punto di partenza. Per case tradizionali slope 1.5\u20132.0.\n\n'
                '3\ufe0f\u20e3  Scegli la modalit\u00e0: usa il toggle in alto nella pagina Home per selezionare Riscaldamento (inverno) o Raffrescamento (estate).\n\n'
                '4\ufe0f\u20e3  Inizia a registrare: ogni giorno, preferibilmente alla stessa ora, inserisci i dati dalla griglia Home e premi SALVA.\n\n'
                '5\ufe0f\u20e3  Attendi 5 giorni: dopo 5 registrazioni l\u2019AI sar\u00e0 pronta per il primo suggerimento.\n\n'
                '6\ufe0f\u20e3  Applica il suggerimento AI: valuta la curva proposta nella pagina Analisi e premi \u201cApplica Curva AI\u201d se ti convince.\n\n'
                '7\ufe0f\u20e3  Imposta un promemoria: tocca l\u2019icona \ud83d\udd14 in alto a destra nella barra Home per scegliere l\u2019ora del promemoria giornaliero.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 2: UTILIZZO QUOTIDIANO ───────────────────────────────
          _buildSectionTitle(context, 'Utilizzo Quotidiano'),
          _buildExpandableCard(
            context: context,
            icon: Icons.edit_note,
            iconColor: Colors.green,
            title: 'Come Registrare un Dato Giornaliero',
            content:
                'Ogni giorno, preferibilmente alla stessa ora (es. mattina), compila le tile nella griglia Home:\n\n'
                '1. Esterna: temperatura esterna rilevata dal GPS o dalla citt\u00e0 configurata. Tocca l\u2019icona \u2601\ufe0f per aggiornare manualmente.\n'
                '2. Consumo: kWh giornalieri letti dal contatore o dal display della PdC.\n'
                '3. ACS, Rete, Fotovoltaico: compila queste tile solo se il tuo impianto le prevede.\n'
                '4. Pompa di calore / Caldaia: imposta la modalit\u00e0 operativa dal menu a tendina della tile.\n'
                '5. Temperature interne: tocca ogni stanza per inserire la temperatura e il giudizio di comfort.\n'
                '6. Nota (tile viola): tocca per aggiungere osservazioni libere come \u201cfinestre aperte\u201d, \u201cospiti a cena\u201d o \u201ccaldaia in manutenzione\u201d. La nota compare in anteprima direttamente sulla tile e viene inclusa nel PDF esportato.\n\n'
                'Premi SALVA TUTTO. Il dato viene memorizzato con la data di oggi.\n\n'
                'Consiglio: usa il pulsante \u201cCopia dall\u2019ultima registrazione\u201d (icona in alto a destra) per pre-compilare le temperature interne se sono simili al giorno precedente.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.edit,
            iconColor: Colors.amber,
            title: 'Modificare o Eliminare una Registrazione',
            content:
                'Nella pagina Storico trovi tutte le registrazioni in ordine cronologico.\n\n'
                '\u2022 Per modificare: tocca il record desiderato \u2192 i campi vengono pre-compilati nella pagina Home \u2192 modifica e premi AGGIORNA.\n\n'
                '\u2022 Per eliminare: scorri il record verso sinistra e conferma. Oppure usa \u201cElimina oggi\u201d dal menu \u22ee per cancellare rapidamente il record odierno.\n\n'
                'Nota: non \u00e8 possibile inserire due registrazioni per la stessa data e modalit\u00e0. Se esiste gi\u00e0 un record per oggi, l\u2019app ti avvisa e devi modificare quello esistente.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.ac_unit,
            iconColor: Colors.cyan,
            title: 'Modalit\u00e0 Riscaldamento vs Raffrescamento',
            content:
                'L\u2019app gestisce due modalit\u00e0 separate, ognuna con la propria curva:\n\n'
                '\u2022 Riscaldamento (Inverno): la temperatura di mandata sale al calare di quella esterna.\n'
                '\u2022 Raffrescamento (Estate): la temperatura dell\u2019acqua fredda sale all\u2019aumentare di quella esterna.\n\n'
                'Le due curve, le registrazioni e le analisi AI sono completamente separate. Cambia modalit\u00e0 con il toggle in alto nella pagina Home.\n\n'
                'Quando ripristini un backup, la modalit\u00e0 attiva viene recuperata correttamente dal file, quindi non perdi l\u2019impostazione salvata.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 3: TILE HOME ──────────────────────────────────────────
          _buildSectionTitle(context, 'Griglia Home e Tile'),
          _buildExpandableCard(
            context: context,
            icon: Icons.cloud_sync,
            iconColor: Colors.blue,
            title: 'Tile Temperatura Esterna',
            content:
                'La tile \u201cEsterna\u201d mostra la temperatura esterna scaricata automaticamente all\u2019apertura dell\u2019app (GPS o citt\u00e0 configurata).\n\n'
                'Il sottotitolo indica la freschezza del dato:\n'
                '\u2022 \u201cBenessere\u201d: dato non ancora scaricato in questa sessione.\n'
                '\u2022 \u201cAdesso\u201d: aggiornato meno di un minuto fa.\n'
                '\u2022 \u201c5 min fa\u201d, \u201c12 min fa\u201d\u2026: dalla cache.\n'
                '\u2022 Nome citt\u00e0 (es. \u201cBologna\u201d): scaricato in questa sessione.\n\n'
                'Tocca l\u2019icona \u2601\ufe0f per forzare un aggiornamento manuale in qualsiasi momento.\n\n'
                'Auto-fetch intelligente: se il tentativo automatico fallisce (GPS assente o nessuna connessione), l\u2019app riprova automaticamente al prossimo cambio di tab o quando torni in primo piano. Il tap manuale non \u00e8 mai bloccato da questo meccanismo.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.sticky_note_2,
            iconColor: const Color(0xFF7E57C2),
            title: 'Tile Nota',
            content:
                'La tile viola \u201cNota\u201d \u00e8 sempre visibile nella griglia Home.\n\n'
                '\u2022 Tocca la tile per aprire l\u2019editor: un campo testo libero su pi\u00f9 righe, con hint \u201cEs: finestra aperta, ospiti, anomalia caldaia\u2026\u201d\n'
                '\u2022 Premi \u2714 per salvare. La tile mostra subito un pallino bianco e la prima riga della nota come anteprima.\n'
                '\u2022 Premi \u201cCancella nota\u201d per svuotare il campo.\n\n'
                'La nota viene inclusa nel report PDF e nello storico registrazioni. Usa questo campo per annotare eventi che i numeri non catturano: open space, guasti temporanei, giornate anomale.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.meeting_room_outlined,
            iconColor: Colors.brown,
            title: 'Tile Stanze',
            content:
                'Per ogni stanza configurata appare una tile con il colore del modo attivo (arancio = riscaldamento, teal = raffrescamento).\n\n'
                'Tocca la tile per aprire il selettore: uno slider verticale per la temperatura e le icone di comfort (\u2603 Freddo / \u2714 Ok / \u2600 Caldo).\n\n'
                'Se solo una stanza \u00e8 sempre fredda mentre le altre sono ok, il problema non \u00e8 la curva climatica ma il bilanciamento idraulico o una valvola termostatica da regolare.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 4: CONCETTI BASE ──────────────────────────────────────
          _buildSectionTitle(context, 'Concetti della Curva Climatica'),
          _buildExpandableCard(
            context: context,
            icon: Icons.thermostat,
            iconColor: Colors.orange,
            title: 'Cos\u2019\u00e8 la Curva Climatica?',
            content:
                'La curva climatica dice all\u2019impianto a che temperatura portare l\u2019acqua in funzione della temperatura esterna, garantendo comfort senza continui on/off.\n\n'
                'Esempio pratico:\n'
                '\u2022 Fuori -5 \u2103 \u2192 acqua a 50 \u2103\n'
                '\u2022 Fuori +10 \u2103 \u2192 acqua a 38 \u2103\n\n'
                'L\u2019obiettivo \u00e8 un funzionamento continuo e modulante, che risparmia energia e aumenta il comfort rispetto all\u2019on/off.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.show_chart,
            iconColor: Colors.blue,
            title: 'Pendenza (Slope)',
            content:
                'Determina quanto varia la temperatura di mandata al variare di quella esterna.\n\n'
                '\u2022 Alta (es. 2.0): grandi variazioni. Case poco isolate o termosifoni tradizionali.\n'
                '\u2022 Bassa (es. 0.5): variazioni dolci. Case ben isolate o pannelli a pavimento.\n\n'
                'Regola pratica:\n'
                '  - Freddo solo con temperature esterne estreme \u2192 aumenta la pendenza.\n'
                '  - Caldo con temperature esterne miti \u2192 riduci la pendenza.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.height,
            iconColor: Colors.purple,
            title: 'Parallela (Offset)',
            content:
                'Sposta tutta la curva verso l\u2019alto o il basso senza cambiarne la forma.\n\n'
                '\u2022 Offset positivo (+3): acqua sempre pi\u00f9 calda di 3 \u2103. Casa sistematicamente fresca.\n'
                '\u2022 Offset negativo (-2): acqua sempre pi\u00f9 fredda di 2 \u2103. Casa sistematicamente calda.\n\n'
                'Regola pratica: se il disagio \u00e8 costante a tutte le temperature esterne, agisci sull\u2019offset. Se si manifesta solo con freddo o caldo estremi, agisci sulla pendenza.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 5: AI E ANALISI ───────────────────────────────────────
          _buildSectionTitle(context, 'Intelligenza Artificiale'),
          _buildExpandableCard(
            context: context,
            icon: Icons.psychology,
            iconColor: Colors.indigo,
            title: 'Come Funziona l\u2019AI',
            content:
                'L\u2019AI analizza le registrazioni per suggerire una curva ottimizzata in 3 fasi:\n\n'
                '1. Apprendimento (0\u20134 giorni): meno di 5 dati, suggerimento sospeso.\n\n'
                '2. Analisi (5+ giorni): conta i giorni per comfort e decide la direzione:\n'
                '   \u2022 Pi\u00f9 giorni freddi \u2192 aumenta offset (e pendenza se >30% freddi)\n'
                '   \u2022 Pi\u00f9 giorni caldi \u2192 riduce offset\n'
                '   \u2022 Tutti ok \u2192 ottimizza i consumi riducendo leggermente la potenza\n\n'
                '3. Prudenza: modifica massima per applicazione: \u00b10.1 slope e \u00b11.0 offset.\n\n'
                'Dopo ogni applicazione l\u2019app attende 5 nuovi giorni prima di un\u2019altra analisi.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.timeline,
            iconColor: Colors.green,
            title: 'Interpretare il Grafico della Curva',
            content:
                'Il grafico mostra la temperatura di mandata (asse Y) in funzione di quella esterna (asse X).\n\n'
                '\u2022 Linea blu piena: curva attuale.\n'
                '\u2022 Linea verde tratteggiata: curva suggerita dall\u2019AI (visibile solo se disponibile).\n\n'
                'Zona rossa:\n'
                '  - Inverno: mandata <35 \u2103. Poco efficiente per termosifoni, ok per pannelli a pavimento.\n'
                '  - Estate: mandata <15 \u2103. Alto rischio condensa sui terminali.\n\n'
                'Se la curva tocca spesso la zona rossa in inverno con termosifoni, aumenta pendenza o offset.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.bar_chart,
            iconColor: Colors.teal,
            title: 'Punteggio Comfort & Energia',
            content:
                '\u2022 Punteggio Comfort: % di giorni con valutazione \u201cok\u201d. 100% = sempre confortevole.\n\n'
                '\u2022 Punteggio Energia: indice relativo ai consumi medi. Obiettivo: massimo comfort con il minimo consumo.\n\n'
                'Visibili nella pagina Analisi e nel report PDF.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 6: COMFORT E STANZE ───────────────────────────────────
          _buildSectionTitle(context, 'Comfort e Stanze'),
          _buildExpandableCard(
            context: context,
            icon: Icons.sentiment_satisfied_alt,
            iconColor: Colors.orange,
            title: 'Come Valutare il Comfort',
            content:
                'Per ogni stanza scegli:\n\n'
                '\u2603 Freddo: la stanza non raggiunge la temperatura desiderata.\n'
                '\u2714 Ok: comfort ottimale, l\u2019obiettivo da mantenere.\n'
                '\u2600 Caldo: la stanza \u00e8 surriscaldata.\n\n'
                'L\u2019AI usa questi giudizi per calcolare la direzione del suggerimento. Pi\u00f9 dati inserisci, pi\u00f9 accurato sar\u00e0 il suggerimento.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.meeting_room_outlined,
            iconColor: Colors.brown,
            title: 'Gestione Stanze',
            content:
                'Puoi aggiungere, rinominare o rimuovere le stanze in qualsiasi momento da Guida \u2192 Gestisci Stanze.\n\n'
                'Le stanze vengono usate:\n'
                '\u2022 Nel form di registrazione per temperatura e comfort.\n'
                '\u2022 Nell\u2019analisi AI per identificare problemi localizzati.\n'
                '\u2022 Nel report PDF esportato.\n\n'
                'Se una stanza specifica \u00e8 sempre fredda o calda, indica un problema localizzato (bilanciamento impianto, valvola, esposizione solare) che la curva climatica da sola non pu\u00f2 risolvere.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 7: NOTIFICHE ──────────────────────────────────────────
          _buildSectionTitle(context, 'Notifiche'),
          _buildExpandableCard(
            context: context,
            icon: Icons.notifications_outlined,
            iconColor: Colors.blue,
            title: 'Promemoria Giornaliero',
            // FIX #2: accesso notifiche tramite icona campanella in barra Home,
            // non tramite menu ⋮ che non esiste nell'UI attuale.
            content:
                'Puoi impostare un promemoria giornaliero che ti ricorda di inserire i dati.\n\n'
                'Come impostarlo: tocca l\u2019icona \ud83d\udd14 in alto a destra nella barra Home \u2192 scegli l\u2019ora.\n\n'
                'Consiglio: imposta il promemoria la mattina, sempre alla stessa ora. La costanza dei dati \u00e8 fondamentale per ottenere buoni risultati dall\u2019AI.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.tips_and_updates_outlined,
            iconColor: Colors.amber,
            title: 'Notifiche Contestuali AI',
            content:
                'Quando salvi una registrazione, l\u2019app controlla in background se l\u2019AI ha un suggerimento significativo da darti.\n\n'
                'Se la curva potrebbe essere migliorata, ricevi una notifica con un testo contestuale, ad esempio:\n'
                '\u201cLa curva di riscaldamento potrebbe essere incrementata. Valuta di applicare il suggerimento AI.\u201d\n\n'
                'Queste notifiche compaiono solo quando c\u2019\u00e8 davvero qualcosa da segnalare, non ad ogni salvataggio.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 8: STRUMENTI AVANZATI ────────────────────────────────
          _buildSectionTitle(context, 'Strumenti Avanzati'),

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
                  subtitle: const Text('Salva storico, impostazioni e modalit\u00e0 attiva in un file JSON'),
                  onTap: widget.onBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined, color: Colors.orange),
                  title: const Text('Ripristina Backup'),
                  subtitle: const Text('Carica un file .json: ripristina storico, curva e modalit\u00e0 attiva'),
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
                '2. Curva appena modificata: dopo ogni applicazione AI, l\u2019app attende 5 giorni di NUOVI dati prima di una nuova analisi.\n\n'
                '3. Curva gi\u00e0 ottimale: se il suggerimento AI coincide con i valori attuali (\u03940.05), l\u2019app lo segnala e non modifica nulla.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Posso usare l\u2019app senza internet?',
            content:
                'S\u00ec, completamente. Registrazioni, analisi AI, grafico, export CSV e PDF funzionano tutti offline.\n\n'
                'Solo la tile \u201cEsterna\u201d (temperatura meteo automatica) richiede connessione internet o GPS. Senza, puoi sempre inserire la temperatura esterna manualmente.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Ho cambiato modalit\u00e0 ma non vedo i dati precedenti',
            content:
                'I dati di riscaldamento e raffrescamento sono separati per design. In modalit\u00e0 Riscaldamento vedi solo i record invernali, e viceversa.\n\n'
                'Il backup JSON include entrambe le modalit\u00e0, quindi i dati non vengono mai persi. Quando ripristini, anche la modalit\u00e0 attiva viene recuperata correttamente.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Quanto spesso applicare la curva AI?',
            content:
                'Non esiste una frequenza fissa. Nelle prime settimane potresti applicarla ogni 5\u201310 giorni per calibrare la curva. A regime (casa ben calibrata) possono passare molte settimane tra una modifica e l\u2019altra.',
          ),
          const SizedBox(height: 12),
          _buildExpandableCard(
            context: context,
            icon: Icons.help_outline,
            iconColor: Colors.grey,
            title: 'Reset Calibrazione vs Ripristina Backup',
            content:
                '\u2022 Reset Calibrazione: azzera SOLO pendenza e offset ai valori predefiniti. Lo storico rimane intatto.\n\n'
                '\u2022 Ripristina Backup: sovrascrive tutto (storico + impostazioni + modalit\u00e0 attiva) con il contenuto del file .json scelto. \u00c8 irreversibile: fai sempre un backup prima.',
          ),
          const SizedBox(height: 24),

          // ── SEZIONE 10: APPROFONDIMENTI TECNICI ──────────────────────────
          _buildSectionTitle(context, 'Approfondimenti Tecnici'),
          _buildExpandableCard(
            context: context,
            icon: Icons.home_work_outlined,
            iconColor: Colors.green,
            title: 'Valori di Partenza per Casa X-LAM',
            content:
                'Una casa in X-LAM ha alta inerzia termica e dispersioni ridotte: risponde lentamente e mantiene il calore a lungo.\n\n'
                'Valori di partenza consigliati:\n'
                '\u2022 Pendenza (slope): 0.8\n'
                '\u2022 Offset: 0.0 (alzalo di +1 o +2 solo se la casa risulta sistematicamente fresca)\n\n'
                'Confronto per tipo di abitazione:\n'
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
            title: 'VMC con Recuperatore di Calore',
            content:
                'La VMC recupera il 70\u201390% del calore dall\u2019aria espulsa, riducendo le dispersioni e stabilizzando la temperatura interna.\n\n'
                'Effetti sulla curva climatica:\n'
                '\u2022 L\u2019impianto deve \u201cintegrare\u201d meno \u2192 pendenza ottimale pi\u00f9 bassa.\n'
                '\u2022 Le variazioni esterne impattano meno sull\u2019interno.\n'
                '\u2022 L\u2019offset pu\u00f2 restare vicino allo zero.\n\n'
                'Con VMC + recuperatore l\u2019AI converger\u00e0 pi\u00f9 rapidamente perch\u00e9 il sistema \u00e8 intrinsecamente pi\u00f9 stabile.',
          ),
          const SizedBox(height: 40),

          // ── FOOTER ────────────────────────────────────────────────────────
          // FIX #1: versione allineata a pubspec.yaml (1.0.0+1)
          Center(
            child: Column(
              children: [
                Text(
                  'ClimaSense v1.0.0',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'App creata da Nigro Giandomenico',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── CARD CITTÀ METEO ───────────────────────────────────────────────────
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

  // ── WIDGETS ───────────────────────────────────────────────────────────

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
