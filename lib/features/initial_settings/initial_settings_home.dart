import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/daily_record_dto.dart';
import '../../services/hive_storage.dart';
import '../home/climate_curve_home.dart';

// ---------------------------------------------------------------------------
// Tipi di impianto selezionabili nello Step 1
// ---------------------------------------------------------------------------
enum _PlantType { heatpump, boiler, hybrid }

extension _PlantTypeExt on _PlantType {
  String get key {
    switch (this) {
      case _PlantType.heatpump: return 'heatpump';
      case _PlantType.boiler:   return 'boiler';
      case _PlantType.hybrid:   return 'hybrid';
    }
  }

  String get label {
    switch (this) {
      case _PlantType.heatpump: return 'Pompa di Calore';
      case _PlantType.boiler:   return 'Caldaia';
      case _PlantType.hybrid:   return 'Ibrido (PdC + Caldaia)';
    }
  }

  IconData get icon {
    switch (this) {
      case _PlantType.heatpump: return Icons.heat_pump;
      case _PlantType.boiler:   return Icons.local_fire_department;
      case _PlantType.hybrid:   return Icons.device_hub;
    }
  }
}

// ---------------------------------------------------------------------------
// Widget principale
// ---------------------------------------------------------------------------
class InitialSettingsHome extends StatefulWidget {
  const InitialSettingsHome({super.key});

  @override
  State<InitialSettingsHome> createState() => _InitialSettingsHomeState();
}

class _InitialSettingsHomeState extends State<InitialSettingsHome> {
  final _formKey = GlobalKey<FormState>();

  // Step 2 — Riscaldamento
  final _slopeController   = TextEditingController();
  final _offsetController  = TextEditingController();
  // Step 3 — Raffrescamento
  final _coolingSlopeController  = TextEditingController();
  final _coolingOffsetController = TextEditingController();
  // Step 4 — Energia
  final _costController = TextEditingController();

  int _currentStep = 0;
  bool _isLoading  = false;

  // Step 1 — Impianto
  _PlantType _plantType  = _PlantType.heatpump;
  bool       _hasPv      = false;
  bool       _hasGridMeter = false;

  static const double _slopeMin  = 0.1;
  static const double _slopeMax  = 5.0;
  static const double _offsetMin = -20.0;
  static const double _offsetMax =  20.0;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    // Curva riscaldamento
    final slope  = AppStorage.getSlope();
    final offset = AppStorage.getOffset();
    _slopeController.text  = slope.toString();
    _offsetController.text = offset.toString();

    // Curva raffrescamento
    _coolingSlopeController.text  = AppStorage.getCoolingSlope().toString();
    _coolingOffsetController.text = AppStorage.getCoolingOffset().toString();

    // Costo €/kWh
    _costController.text = AppStorage.getCostPerKwh().toString();

    // Impianto
    final plantKey = AppStorage.getPlantType();
    setState(() {
      _plantType    = _PlantType.values.firstWhere((e) => e.key == plantKey, orElse: () => _PlantType.heatpump);
      _hasPv        = AppStorage.getHasPv();
      _hasGridMeter = AppStorage.getHasGridMeter();
    });
  }

  @override
  void dispose() {
    _slopeController.dispose();
    _offsetController.dispose();
    _coolingSlopeController.dispose();
    _coolingOffsetController.dispose();
    _costController.dispose();
    super.dispose();
  }

  // --- Validatori ---
  String? _validateSlope(String? val) {
    if (val == null || val.isEmpty) return 'Campo obbligatorio';
    final v = double.tryParse(val.replaceAll(',', '.'));
    if (v == null) return 'Valore non valido';
    if (v < _slopeMin || v > _slopeMax) return 'Pendenza: $_slopeMin – $_slopeMax';
    return null;
  }

  String? _validateOffset(String? val) {
    if (val == null || val.isEmpty) return 'Campo obbligatorio';
    final v = double.tryParse(val.replaceAll(',', '.'));
    if (v == null) return 'Valore non valido';
    if (v < _offsetMin || v > _offsetMax) return 'Parallela: $_offsetMin – $_offsetMax';
    return null;
  }

  String? _validateCost(String? val) {
    if (val == null || val.isEmpty) return 'Campo obbligatorio';
    final v = double.tryParse(val.replaceAll(',', '.'));
    if (v == null || v <= 0) return 'Inserisci un valore positivo';
    return null;
  }

  // --- Step continua / indietro ---
  void _onStepContinue() {
    // Step 1 (Impianto) non ha campi form → avanza direttamente
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
      return;
    }
    // Ultimi step: valida il form prima di avanzare
    if (!_formKey.currentState!.validate()) return;
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _saveAndFinish();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _saveAndFinish() async {
    setState(() => _isLoading = true);
    try {
      // Curva
      final slope  = double.tryParse(_slopeController.text.replaceAll(',', '.'))  ?? 1.0;
      final offset = double.tryParse(_offsetController.text.replaceAll(',', '.')) ?? 0.0;
      final cSlope = double.tryParse(_coolingSlopeController.text.replaceAll(',', '.'))  ?? 0.5;
      final cOffset= double.tryParse(_coolingOffsetController.text.replaceAll(',', '.')) ?? 0.0;
      final cost   = double.tryParse(_costController.text.replaceAll(',', '.'))   ?? 0.14891;

      await AppStorage.saveSlope(slope);
      await AppStorage.saveOffset(offset);
      await AppStorage.saveCoolingSlope(cSlope);
      await AppStorage.saveCoolingOffset(cOffset);
      await AppStorage.saveSystemMode('heating');
      await AppStorage.saveCostPerKwh(cost);

      // Impianto
      await AppStorage.savePlantType(_plantType.key);
      await AppStorage.saveHasPv(_hasPv);
      await AppStorage.saveHasGridMeter(_hasGridMeter);

      await AppStorage.setAppInitialized();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ClimateCurveOfflineHome(
              initialSlope: slope,
              initialOffset: offset,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore salvataggio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: cs.background,
        appBar: AppBar(
          backgroundColor: cs.background,
          elevation: 0,
          title: const Text('Configurazione Iniziale'),
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: Stepper(\n                    type: StepperType.vertical,
                    currentStep: _currentStep,
                    onStepContinue: _onStepContinue,
                    onStepCancel: _onStepCancel,
                    controlsBuilder: _buildControls,
                    steps: [
                      _buildStepImpianto(cs),
                      _buildStepRiscaldamento(cs),
                      _buildStepRaffrescamento(cs),
                      _buildStepEnergia(cs),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // --- Controls (pulsanti Continua / Indietro) ---
  Widget _buildControls(BuildContext context, ControlsDetails details) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: details.onStepContinue,
              child: Text(_currentStep == 3 ? 'TERMINA E AVVIA' : 'CONTINUA'),
            ),
          ),
          if (_currentStep > 0) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: details.onStepCancel,
              child: const Text('INDIETRO'),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 1 — Impianto
  // ---------------------------------------------------------------------------
  Step _buildStepImpianto(ColorScheme cs) {
    return Step(
      title: const Text('Tipo di Impianto'),
      subtitle: Text(_plantType.label, style: TextStyle(color: cs.primary, fontSize: 12)),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.editing,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seleziona il tipo di impianto principale installato nella tua abitazione.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Chip tipo impianto
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _PlantType.values.map((type) {
              final selected = _plantType == type;
              return ChoiceChip(
                avatar: Icon(
                  type.icon,
                  size: 18,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                label: Text(type.label),
                selected: selected,
                onSelected: (_) => setState(() => _plantType = type),
                selectedColor: cs.primary,
                labelStyle: TextStyle(
                  color: selected ? cs.onPrimary : cs.onSurface,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          // Toggle FV
          _buildToggleTile(
            cs: cs,
            icon: Icons.solar_power,
            title: 'Ho un impianto fotovoltaico',
            subtitle: 'I dati vengono letti da ShinePhone',
            value: _hasPv,
            onChanged: (v) => setState(() => _hasPv = v),
          ),
          const SizedBox(height: 10),
          // Toggle Rete
          _buildToggleTile(
            cs: cs,
            icon: Icons.electric_meter,
            title: 'Ho un contatore smart (rete)',
            subtitle: 'Energia da rete letta da ShinePhone',
            value: _hasGridMeter,
            onChanged: (v) => setState(() => _hasGridMeter = v),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2 — Riscaldamento
  // ---------------------------------------------------------------------------
  Step _buildStepRiscaldamento(ColorScheme cs) {
    return Step(
      title: const Text('Riscaldamento (Inverno)'),
      isActive: _currentStep >= 1,
      state: _currentStep > 1
          ? StepState.complete
          : _currentStep == 1
              ? StepState.editing
              : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parametri attuali dell\'impianto per la stagione invernale. '
            'Li trovi nel display della PdC o nel manuale.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildNumericField(
            controller: _slopeController,
            label: 'Pendenza (Slope / Curva)',
            hint: 'Es. 1.0',
            helper: 'Valori accettati: $_slopeMin – $_slopeMax',
            validator: _validateSlope,
            signed: false,
          ),
          const SizedBox(height: 14),
          _buildNumericField(
            controller: _offsetController,
            label: 'Parallela (Offset / Shift)',
            hint: 'Es. 0.0',
            helper: 'Valori accettati: $_offsetMin – $_offsetMax',
            validator: _validateOffset,
            signed: true,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 3 — Raffrescamento
  // ---------------------------------------------------------------------------
  Step _buildStepRaffrescamento(ColorScheme cs) {
    return Step(
      title: const Text('Raffrescamento (Estate)'),
      isActive: _currentStep >= 2,
      state: _currentStep > 2
          ? StepState.complete
          : _currentStep == 2
              ? StepState.editing
              : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parametri per la stagione estiva. '
            'Se non usi il raffrescamento, lascia i valori predefiniti.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildNumericField(
            controller: _coolingSlopeController,
            label: 'Pendenza Estate',
            hint: 'Es. 0.5',
            helper: 'Valori accettati: $_slopeMin – $_slopeMax',
            validator: _validateSlope,
            signed: false,
          ),
          const SizedBox(height: 14),
          _buildNumericField(
            controller: _coolingOffsetController,
            label: 'Parallela Estate',
            hint: 'Es. 0.0',
            helper: 'Valori accettati: $_offsetMin – $_offsetMax',
            validator: _validateOffset,
            signed: true,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 4 — Energia & Costi
  // ---------------------------------------------------------------------------
  Step _buildStepEnergia(ColorScheme cs) {
    return Step(
      title: const Text('Energia & Costi'),
      isActive: _currentStep >= 3,
      state: _currentStep == 3 ? StepState.editing : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Imposta il tuo prezzo dell\'energia elettrica. '
            'Verrà usato per calcolare i costi stimati nel grafico.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildNumericField(
            controller: _costController,
            label: 'Prezzo energia (€/kWh)',
            hint: 'Es. 0.25',
            helper: 'Controlla la tua bolletta per il valore esatto',
            validator: _validateCost,
            signed: false,
            prefixIcon: Icons.euro,
          ),
          const SizedBox(height: 20),
          // Info-box riepilogo impianto
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Riepilogo configurazione',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _summaryRow(cs, Icons.device_hub,    'Impianto',     _plantType.label),
                _summaryRow(cs, Icons.solar_power,   'Fotovoltaico', _hasPv      ? 'Sì (ShinePhone)' : 'No'),
                _summaryRow(cs, Icons.electric_meter,'Rete',         _hasGridMeter ? 'Sì (ShinePhone)' : 'No'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper widget
  // ---------------------------------------------------------------------------
  Widget _buildToggleTile({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: value ? cs.primary : cs.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        value: value,
        onChanged: onChanged,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildNumericField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String helper,
    required String? Function(String?) validator,
    required bool signed,
    IconData? prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        border: const OutlineInputBorder(),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        isDense: true,
      ),
      validator: validator,
    );
  }

  Widget _summaryRow(ColorScheme cs, IconData icon, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('$key: ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
