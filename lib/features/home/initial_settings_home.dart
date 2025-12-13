import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/daily_record_dto.dart';
import '../../services/hive_storage.dart';
import '../home/climate_curve_home.dart';

class InitialSettingsHome extends StatefulWidget {
  const InitialSettingsHome({super.key});

  @override
  State<InitialSettingsHome> createState() => _InitialSettingsHomeState();
}

class _InitialSettingsHomeState extends State<InitialSettingsHome> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _slopeController = TextEditingController();
  final TextEditingController _offsetController = TextEditingController();
  final TextEditingController _coolingSlopeController = TextEditingController();
  final TextEditingController _coolingOffsetController = TextEditingController();

  int _currentStep = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadyConfigured();
  }

  Future<void> _checkIfAlreadyConfigured() async {
    // Se ci sono già dati, potremmo voler saltare o precompilare
    final slope = await AppStorage.getSlope();
    final offset = await AppStorage.getOffset();
    if (slope != 1.2 || offset != 0.0) {
      // Valori custom trovati
      _slopeController.text = slope.toString();
      _offsetController.text = offset.toString();
    } else {
      _slopeController.text = "1.2";
      _offsetController.text = "0.0";
    }

    final cSlope = await AppStorage.getCoolingSlope();
    final cOffset = await AppStorage.getCoolingOffset();
    _coolingSlopeController.text = cSlope.toString();
    _coolingOffsetController.text = cOffset.toString();
  }

  @override
  void dispose() {
    _slopeController.dispose();
    _offsetController.dispose();
    _coolingSlopeController.dispose();
    _coolingOffsetController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Parsing valori Riscaldamento
      final slope = double.tryParse(_slopeController.text.replaceAll(',', '.')) ?? 1.2;
      final offset = double.tryParse(_offsetController.text.replaceAll(',', '.')) ?? 0.0;

      // Parsing valori Raffrescamento
      final cSlope = double.tryParse(_coolingSlopeController.text.replaceAll(',', '.')) ?? 0.5;
      final cOffset = double.tryParse(_coolingOffsetController.text.replaceAll(',', '.')) ?? 0.0;

      // Salvataggio su Hive
      await AppStorage.saveSlope(slope);
      await AppStorage.saveOffset(offset);
      await AppStorage.saveCoolingSlope(cSlope);
      await AppStorage.saveCoolingOffset(cOffset);

      // Imposta modalità default (Inverno)
      await AppStorage.saveSystemMode('heating');

      if (mounted) {
        // Naviga alla Home principale
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ClimateCurveOfflineHome(
              initialSlope: slope,
              initialOffset: offset,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore salvataggio: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Configurazione Iniziale"),
        backgroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
          key: _formKey,
          child: Stepper(
            type: StepperType.vertical,
            currentStep: _currentStep,
            onStepContinue: () {
              if (_currentStep < 1) {
                setState(() => _currentStep++);
              } else {
                _saveAndContinue();
              }
            },
            onStepCancel: () {
              if (_currentStep > 0) {
                setState(() => _currentStep--);
              }
            },
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          backgroundColor: Colors.blue.shade800,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_currentStep == 1 ? "TERMINA E VAI ALLA HOME" : "CONTINUA"),
                      ),
                    ),
                    if (_currentStep > 0) ...[
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: const Text("INDIETRO"),
                      ),
                    ],
                  ],
                ),
              );
            },
            steps: [
              // STEP 1: RISCALDAMENTO
              Step(
                title: const Text("Riscaldamento (Inverno)"),
                content: Column(
                  children: [
                    const Text(
                      "Inserisci i parametri attuali della tua macchina per l'inverno. Li trovi nel manuale o nel display della PdC.",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _slopeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Pendenza (Slope/Curve)",
                        border: OutlineInputBorder(),
                        hintText: "Es. 1.2",
                      ),
                      validator: (val) => val == null || val.isEmpty ? "Campo obbligatorio" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _offsetController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: "Parallela (Offset/Shift)",
                        border: OutlineInputBorder(),
                        hintText: "Es. 0.0",
                      ),
                      validator: (val) => val == null || val.isEmpty ? "Campo obbligatorio" : null,
                    ),
                  ],
                ),
                isActive: _currentStep >= 0,
                state: _currentStep > 0 ? StepState.complete : StepState.editing,
              ),

              // STEP 2: RAFFRESCAMENTO
              Step(
                title: const Text("Raffrescamento (Estate)"),
                content: Column(
                  children: [
                    const Text(
                      "Parametri per l'estate. Se non usi il raffrescamento, lascia i valori predefiniti.",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _coolingSlopeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Pendenza Estate",
                        border: OutlineInputBorder(),
                        hintText: "Es. 0.5",
                      ),
                      validator: (val) => val == null || val.isEmpty ? "Campo obbligatorio" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _coolingOffsetController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: "Parallela Estate",
                        border: OutlineInputBorder(),
                        hintText: "Es. 0.0",
                      ),
                      validator: (val) => val == null || val.isEmpty ? "Campo obbligatorio" : null,
                    ),
                  ],
                ),
                isActive: _currentStep >= 1,
                state: _currentStep == 1 ? StepState.editing : StepState.indexed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
