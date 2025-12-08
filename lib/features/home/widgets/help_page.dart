// lib/features/home/widgets/help_page.dart

import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Guida & Supporto',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeader(),
          const SizedBox(height: 24),

          const Text(
            "ISTRUZIONI RAPIDE",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),

          _buildSection(
            title: '1. Inserimento Dati',
            icon: Icons.edit_note_rounded,
            color: Colors.blue,
            content: """
• TEMPERATURA ESTERNA: Ruota la manopola arancione. Più dati inserisci (mattina, sera), più preciso sarà il risultato.
• METEO AUTOMATICO: Usa il tasto ☁️ per scaricare la media reale di oggi (richiede GPS attivo).
• CONSUMO: Inserisci i kWh consumati dalla Pompa di Calore nelle ultime 24h (leggili dal contatore o dall'app della PdC).
• COMFORT: Per ogni stanza, sii onesto: se hai avuto freddo, segna 'Freddo'. L'AI userà questo dato per alzare la curva.""",
          ),

          _buildSection(
            title: '2. Interpretare la Curva',
            icon: Icons.show_chart_rounded,
            color: Colors.purple,
            content: """
Il grafico ti mostra la tua "firma termica":
• Punti Verdi: La tua casa è in equilibrio (comfort OK).
• Punti Rossi: Hai sprecato energia (troppo caldo).
• Punti Blu: La PdC ha lavorato poco (troppo freddo).
• LINEA GIALLA: È l'obiettivo. Prova a impostare la tua Pompa di Calore seguendo questa linea per risparmiare senza perdere comfort.""",
          ),

          _buildSection(
            title: '3. Esportazione e Notifiche',
            icon: Icons.settings_suggest_rounded,
            color: Colors.orange,
            content: """
• PDF/CSV: Salva i report mensili da inviare al tuo termotecnico o per il tuo archivio (cartella Documenti).
• NOTIFICHE: L'app ti ricorda alle 21:00 di registrare i dati. La costanza è il segreto per un'ottimizzazione perfetta.""",
          ),

          const SizedBox(height: 30),
          const Text(
            "DOMANDE FREQUENTI (FAQ)",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),

          _buildFaqItem(
            question: "Perché la posizione GPS non è precisa?",
            answer: "Su PC Windows non c'è un chip GPS vero e proprio, quindi la posizione è stimata tramite Internet. Su Tablet e Telefono è precisa al metro.",
          ),
          _buildFaqItem(
            question: "Quanti giorni di dati servono?",
            answer: "L'AI inizia a dare suggerimenti utili dopo circa 5-7 giorni di registrazioni con temperature esterne diverse (giorni freddi e giorni miti).",
          ),
          _buildFaqItem(
            question: "Posso modificare un dato sbagliato?",
            answer: "Sì. Vai nella sezione 'Storico Dati' (icona lista in alto), tocca la matita accanto al giorno sbagliato e correggi.",
          ),

          const SizedBox(height: 40),
          _buildFooter(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.tips_and_updates_rounded, size: 36, color: Colors.amber),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              "Benvenuto in ClimaSense!\nQui impari a far lavorare la tua casa per te, non viceversa.",
              style: TextStyle(fontSize: 15, height: 1.4, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              content,
              style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem({required String question, required String answer}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            question,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Colors.black87),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              answer,
              style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        // LOGO DELL'APP
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4)
              )
            ],
            // Assicurati che l'immagine 'assets/images/logo.png' esista!
            // Se non esiste, l'app mostrerà uno spazio vuoto o un errore in console, ma non crasherà.
            image: const DecorationImage(
              image: AssetImage('assets/images/logo.png'),
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "ClimaSense v1.0",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          "Sviluppata da\nNigro Giandomenico",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 4),
        Text(
          "Ottimizza il comfort, riduci gli sprechi.",
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
        ),
      ],
    );
  }
}
