// lib/features/home/widgets/results_page.dart

import 'package:flutter/material.dart';
import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../logic/curve_logic.dart';

class ResultsPage extends StatefulWidget {
  final List<DailyRecordDTO> records;
  final double slope;
  final double offset;
  final CurveSuggestion suggestion;
  final CurveStats stats;
  final VoidCallback onApplyAiCurve;
  final Function(int) onDeleteRecord;
  final Function(int) onEditRecord;

  const ResultsPage({
    super.key,
    required this.records,
    required this.slope,
    required this.offset,
    required this.suggestion,
    required this.stats,
    required this.onApplyAiCurve,
    required this.onDeleteRecord,
    required this.onEditRecord,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  double _costPerKwh = 0.0;

  // Blocca il pulsante dopo l'applicazione
  bool _hasAppliedThisSession = false;

  @override
  void initState() {
    super.initState();
    _loadCost();
  }

  @override
  void didUpdateWidget(ResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _loadCost() async {
    final cost = await AppStorage.getCostPerKwh();
    if (mounted) {
      setState(() {
        _costPerKwh = cost;
      });
    }
  }

  Future<void> _editCost(BuildContext context) async {
    final initialText = _costPerKwh == 0 ? '' : _costPerKwh.toString();
    final TextEditingController controller = TextEditingController(text: initialText);

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
                suffixText: '€/kWh',
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.replaceAll(',', '.');
              final newVal = double.tryParse(text) ?? 0.0;
              await AppStorage.saveCostPerKwh(newVal);
              setState(() => _costPerKwh = newVal);
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  // NUOVO WIDGET: Distribuzione Comfort
  Widget _buildComfortDistribution() {
    if (widget.records.isEmpty) return const SizedBox.shrink();

    int cold = 0;
    int hot = 0;
    int ok = 0;

    for (var r in widget.records) {
      if (r.comfortRatings.values.contains('freddo')) cold++;
      else if (r.comfortRatings.values.contains('caldo')) hot++;
      else ok++;
    }

    final total = widget.records.length;
    if (total == 0) return const SizedBox.shrink();

    // Calcolo percentuali per la larghezza (Flex)
    final int flexCold = (cold / total * 100).round();
    final int flexHot = (hot / total * 100).round();
    final int flexOk = (ok / total * 100).round();

    if (flexCold + flexHot + flexOk == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DISTRIBUZIONE COMFORT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1)),
          const SizedBox(height: 16),

          // Barra Colorata
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 20,
              child: Row(
                children: [
                  if (flexCold > 0) Expanded(flex: flexCold, child: Container(color: Colors.blue.shade300)),
                  if (flexOk > 0) Expanded(flex: flexOk, child: Container(color: Colors.green.shade400)),
                  if (flexHot > 0) Expanded(flex: flexHot, child: Container(color: Colors.red.shade300)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Legenda Sotto
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (cold > 0) _buildLegendDot('Freddo', Colors.blue.shade300, '$cold gg'),
              if (ok > 0) _buildLegendDot('Ottimale', Colors.green.shade400, '$ok gg'),
              if (hot > 0) _buildLegendDot('Caldo', Colors.red.shade300, '$hot gg'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color, String count) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ($count)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEnergyWalletCard() {
    final bool isActive = _costPerKwh > 0;
    final double todayCost = widget.records.isNotEmpty
        ? widget.records.last.consumption * _costPerKwh
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF263238),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.wallet_rounded, color: Colors.amberAccent, size: 20),
                  const SizedBox(width: 8),
                  Text('ENERGY WALLET', style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
                onPressed: () => _editCost(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            ],
          ),
          const SizedBox(height: 16),
          if (!isActive)
            Center(
              child: TextButton.icon(
                onPressed: () => _editCost(context),
                icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                label: const Text('Imposta Costo Energia', style: TextStyle(color: Colors.white70)),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('€ ${todayCost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Spesa stimata oggi', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TARIFFA', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                    Text('€ $_costPerKwh /kWh', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (widget.records.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Nessuna registrazione presente.")));
    }

    final sortedRecords = List.from(widget.records.asMap().entries.toList())
      ..sort((a, b) => b.value.dateIso.compareTo(a.value.dateIso));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Text("STORICO REGISTRAZIONI", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedRecords.length,
          itemBuilder: (context, index) {
            final entry = sortedRecords[index];
            final originalIndex = entry.key;
            final r = entry.value;

            double avgInt = 0;
            if (r.internalTemps.isNotEmpty) {
              avgInt = r.internalTemps.values.map((e) => e as num).reduce((a, b) => a + b) / r.internalTemps.length;
            }

            return Card(
              elevation: 0,
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(r.dateIso, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text(
                  "Est: ${r.externalTemp}°C • Int: ${avgInt.toStringAsFixed(1)}°C • ${r.consumption} kWh",
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20),
                      onPressed: () => widget.onEditRecord(originalIndex),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                      onPressed: () => _confirmDelete(originalIndex),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina Registrazione'),
        content: const Text('Sei sicuro di voler eliminare questi dati?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Elimina')),
        ],
      ),
    );

    if (confirm == true) {
      widget.onDeleteRecord(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLearning = widget.suggestion.isLearning;

    final bool isAlreadyOptimized =
        (widget.slope - widget.suggestion.suggestedSlope).abs() < 0.01 &&
            (widget.offset - widget.suggestion.suggestedOffset).abs() < 0.01;

    final bool isButtonDisabled = isLearning || _hasAppliedThisSession || isAlreadyOptimized;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. METRICHE
                Row(
                  children: [
                    _buildMetricCard(
                        'COMFORT',
                        '${(widget.suggestion.comfortScore * 100).toInt()}%',
                        Icons.sentiment_satisfied_rounded,
                        Colors.orange
                    ),
                    const SizedBox(width: 12),
                    _buildMetricCard(
                        'EFFICIENZA',
                        '${(widget.suggestion.energyScore * 100).toInt()}%',
                        Icons.eco_rounded,
                        Colors.green
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 2. BARRA DISTRIBUZIONE COMFORT
                _buildComfortDistribution(),

                const SizedBox(height: 24),

                // 3. CARD AI PRINCIPALE
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isLearning
                          ? [Colors.grey.shade800, Colors.grey.shade900]
                          : [const Color(0xFF00695C), const Color(0xFF004D40)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: (isLearning ? Colors.grey : const Color(0xFF00695C)).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Analisi AI ClimaSense', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                const SizedBox(height: 4),
                                Text(
                                    isLearning ? 'Apprendimento in corso...' : 'Ottimizzazione Disponibile',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _hasAppliedThisSession
                                    ? "Modifica salvata. Attendi almeno 4 giorni prima di fare altri cambiamenti, per valutare correttamente il comfort."
                                    : widget.suggestion.smartTip,
                                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLearning) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('PENDENZA', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(widget.slope.toStringAsFixed(1), style: TextStyle(color: Colors.white.withOpacity(0.6), decoration: TextDecoration.lineThrough)),
                                      const SizedBox(width: 8),
                                      Text(widget.suggestion.suggestedSlope.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('PARALLELA', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(widget.offset.toStringAsFixed(1), style: TextStyle(color: Colors.white.withOpacity(0.6), decoration: TextDecoration.lineThrough)),
                                      const SizedBox(width: 8),
                                      Text(widget.suggestion.suggestedOffset.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isButtonDisabled
                                ? null
                                : () {
                              setState(() {
                                _hasAppliedThisSession = true;
                              });
                              widget.onApplyAiCurve();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF004D40),
                              disabledBackgroundColor: Colors.white24,
                              disabledForegroundColor: Colors.white38,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: Text(
                                _hasAppliedThisSession
                                    ? 'MODIFICA APPLICATA'
                                    : (isAlreadyOptimized ? 'PARAMETRI OTTIMIZZATI' : 'APPLICA NUOVI PARAMETRI'),
                                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- NUOVO BOX SUGGERIMENTO PRATICO ---
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "COME IMPOSTARE LA MACCHINA:",
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "• PENDENZA (Slope): Sulla Sherpa corrisponde al numero della 'Curva Climatica' (es. Curva 4 o 5). Controlla il manuale per trovare quella più vicina a ${widget.suggestion.suggestedSlope}.\n"
                                          "• PARALLELA (Offset): Cerca la voce 'Spostamento Curva' o 'K Value' nel menu temperature.",
                                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ---------------------------------------
                      ],
                      if (isLearning) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: widget.suggestion.learningProgress / 5.0,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Servono ancora ${5 - widget.suggestion.learningProgress} giorni di dati',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                        ),
                      ]
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4. ENERGY WALLET
                _buildEnergyWalletCard(),

                const SizedBox(height: 24),

                // 5. INFO TECNICHE
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DETTAGLI TECNICI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1)),
                      const SizedBox(height: 16),
                      _buildStatRow('Giorni Analizzati', '${widget.stats.totalDays}'),
                      const Divider(),
                      _buildStatRow('Consumo Medio', '${widget.stats.avgConsumption.toStringAsFixed(1)} kWh'),
                      const Divider(),
                      _buildStatRow('Temp. Esterna Min/Max', '${widget.stats.minExternalTemp.toStringAsFixed(1)}° / ${widget.stats.maxExternalTemp.toStringAsFixed(1)}°'),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // 6. STORICO REGISTRAZIONI
                _buildHistoryList(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
