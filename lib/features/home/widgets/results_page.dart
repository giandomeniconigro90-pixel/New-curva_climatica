// lib/features/home/widgets/results_page.dart

import 'package:flutter/material.dart';

import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../../../utils/date_utils.dart';
import '../logic/curve_logic.dart'; // Importa CurveSuggestion e CurveStats

class ResultsPage extends StatefulWidget {
  final List<DailyRecordDTO> records;

  // Parametri opzionali per supportare la modalità "Avanzata" (chiamata da ClimateCurveHome)
  final double? slope;
  final double? offset;
  final CurveSuggestion? suggestion;
  final CurveStats? stats;
  final VoidCallback? onApplyAiCurve;

  // Callbacks basate su indice (per compatibilità con DashboardHome, ecc.)
  final Function(int)? onDeleteRecord;
  final Function(int)? onEditRecord;

  // NUOVE callbacks opzionali basate su dateIso (per evitare problemi con lista ordinata)
  final void Function(String dateIso)? onEditRecordByDateIso;
  final void Function(String dateIso)? onDeleteRecordByDateIso;

  const ResultsPage({
    super.key,
    required this.records,
    this.slope,
    this.offset,
    this.suggestion,
    this.stats,
    this.onApplyAiCurve,
    this.onDeleteRecord,
    this.onEditRecord,
    this.onEditRecordByDateIso,
    this.onDeleteRecordByDateIso,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  double _costPerKwh = 0.0;
  bool _showAdvancedStats = false;

  @override
  void initState() {
    super.initState();
    // Mostra UI avanzata (AI, grafici extra) solo se i parametri sono stati passati
    _showAdvancedStats = widget.slope != null && widget.suggestion != null;
    _loadCost();
  }

  Future<void> _loadCost() async {
    final cost = AppStorage.getCostPerKwh();
    if (mounted) setState(() => _costPerKwh = cost);
  }

  Future<void> _editCost(BuildContext context) async {
    final TextEditingController controller = TextEditingController(
      text: _costPerKwh == 0 ? '' : _costPerKwh.toString(),
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.euro_symbol_rounded, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            const Text('Costo Energia'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Inserisci il costo al kWh dalla tua bolletta.\nLascia vuoto o 0 per nascondere i costi.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                suffixText: '\u20ac/kWh',
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.replaceAll(',', '.');
              final newVal = double.tryParse(text) ?? 0.0;
              await AppStorage.saveCostPerKwh(newVal);
              if (!ctx.mounted) return;
              setState(() => _costPerKwh = newVal);
              Navigator.of(ctx).pop();
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) {
      return const Center(
        child: Text(
          "Nessun dato registrato",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Ordina record per data decrescente
    final sortedRecords = List<DailyRecordDTO>.from(widget.records);
    sortedRecords.sort((a, b) {
      final da = parseItalianDateSafe(a.dateIso) ?? DateTime.now();
      final db = parseItalianDateSafe(b.dateIso) ?? DateTime.now();
      return db.compareTo(da); // più recenti prima
    });

    final lastRecord = sortedRecords.first;
    final todayCost = lastRecord.consumption * _costPerKwh;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SEZIONE 1: Energy Wallet ---
              const Text(
                "Riepilogo",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _editCost(context),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF263238),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.wallet_rounded,
                                color: Colors.amberAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ENERGY WALLET',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                          const Icon(Icons.edit, color: Colors.white54, size: 18),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _costPerKwh > 0
                                    ? '\u20ac ${todayCost.toStringAsFixed(2)}'
                                    : 'Configura',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Spesa stimata oggi',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${lastRecord.consumption} kWh',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // --- SEZIONE 2: AI Suggestion (solo se modalità Avanzata) ---
              if (_showAdvancedStats && widget.suggestion != null) ...[
                _buildAiCard(widget.suggestion!),
                const SizedBox(height: 24),
              ],

              // --- SEZIONE 3: Lista Storico ---
              const Text(
                "Storico Recente",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedRecords.length,
                itemBuilder: (context, index) {
                  final r = sortedRecords[index];
                  final date = parseItalianDateSafe(r.dateIso) ?? DateTime.now();

                  void handleEditTap() {
                    if (widget.onEditRecordByDateIso != null) {
                      widget.onEditRecordByDateIso!(r.dateIso);
                    } else if (widget.onEditRecord != null) {
                      widget.onEditRecord!(index);
                    }
                  }

                  void handleDeleteTap() {
                    if (widget.onDeleteRecordByDateIso != null) {
                      widget.onDeleteRecordByDateIso!(r.dateIso);
                    } else if (widget.onDeleteRecord != null) {
                      widget.onDeleteRecord!(index);
                    }
                  }

                  return InkWell(
                    onTap: widget.onEditRecordByDateIso != null ||
                        widget.onEditRecord != null
                        ? handleEditTap
                        : null,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // DATA
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  "${date.day}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                                Text(
                                  "${date.month}",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 16),

                          // DATI PRINCIPALI
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.thermostat,
                                      size: 14,
                                      color: Colors.orange,
                                    ),
                                    SizedBox(width: 4),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const SizedBox(width: 18),
                                    Text(
                                      "Esterna: ${r.externalTemp}\u00b0C",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.flash_on,
                                      size: 14,
                                      color: Colors.amber,
                                    ),
                                    SizedBox(width: 4),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const SizedBox(width: 18),
                                    Text(
                                      "Consumo: ${r.consumption} kWh",
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // NOTE
                          if (r.note != null && r.note!.isNotEmpty)
                            const Icon(
                              Icons.sticky_note_2_outlined,
                              color: Colors.grey,
                              size: 18,
                            ),

                          const SizedBox(width: 12),

                          // Icona modifica
                          if (widget.onEditRecordByDateIso != null ||
                              widget.onEditRecord != null) ...[
                            IconButton(
                              onPressed: handleEditTap,
                              icon: Icon(
                                Icons.edit,
                                size: 20,
                                color: Colors.blue.shade600,
                              ),
                              tooltip: 'Modifica',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],

                          // Icona elimina
                          if (widget.onDeleteRecordByDateIso != null ||
                              widget.onDeleteRecord != null) ...[
                            IconButton(
                              onPressed: handleDeleteTap,
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red.shade600,
                              ),
                              tooltip: 'Elimina',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiCard(CurveSuggestion suggestion) {
    // widget.records contiene già solo i record filtrati dopo l'ultima AI apply,
    // passati correttamente da climate_curve_home.dart
    final int recentRecordsCount = widget.records.length;
    final bool hasEnoughData = recentRecordsCount >= 5;

    final bool valuesAreEqual = widget.slope != null &&
        widget.offset != null &&
        (suggestion.suggestedSlope - widget.slope!).abs() < 0.05 &&
        (suggestion.suggestedOffset - widget.offset!).abs() < 0.05;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.indigo.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.shade50,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.indigo.shade400,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "AI Advisor",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          // Badge rilevamenti
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: hasEnoughData
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasEnoughData ? Colors.green : Colors.orange,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasEnoughData ? Icons.check_circle : Icons.schedule,
                  size: 16,
                  color: hasEnoughData
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  'Rilevamenti: $recentRecordsCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: hasEnoughData
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.smartTip,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          if (widget.onApplyAiCurve != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                hasEnoughData && !valuesAreEqual ? widget.onApplyAiCurve : null,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  valuesAreEqual
                      ? "Valori identici (nessuna modifica)"
                      : hasEnoughData
                      ? "Applica Curva (S:${suggestion.suggestedSlope.toStringAsFixed(1)} O:${suggestion.suggestedOffset.toStringAsFixed(1)})"
                      : "Serve 5+ rilevamenti ($recentRecordsCount)",
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasEnoughData && !valuesAreEqual
                      ? Colors.indigo
                      : Colors.grey.shade300,
                  foregroundColor: hasEnoughData && !valuesAreEqual
                      ? Colors.white
                      : Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
