// lib/features/home/widgets/room_control_page.dart
//
// Refactor #6 — validazione real-time:
//   • errorText inline sotto il TextField (senza dialog)
//   • Pulsante Salva disabilitato se il valore non è valido
//   • Bordo rosso sul TextField in caso di errore

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../logic/record_form_validator.dart';

class RoomControlPage extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final bool isConsumption;
  final bool isRoom;
  final Map<String, String> comfortRatings;
  final VoidCallback onSave;
  final bool isCooling;
  final Color cardColor;

  const RoomControlPage({
    super.key,
    required this.title,
    required this.controller,
    required this.isConsumption,
    required this.isRoom,
    required this.comfortRatings,
    required this.onSave,
    required this.isCooling,
    required this.cardColor,
  });

  @override
  State<RoomControlPage> createState() => _RoomControlPageState();
}

class _RoomControlPageState extends State<RoomControlPage> {
  late TextEditingController _localCtrl;
  String? _errorText;
  late FieldKind _fieldKind;

  // Valori per il rating di comfort (solo stanze)
  static const _comfortOptions = [
    ('\uD83E\uDD76', 'Troppo freddo'),
    ('\uD83D\uDE42', 'Confortevole'),
    ('\uD83E\uDD75', 'Troppo caldo'),
  ];

  @override
  void initState() {
    super.initState();
    _localCtrl = TextEditingController(text: widget.controller.text);
    _fieldKind = _resolveKind();
    // Valida il valore iniziale
    _errorText = RecordFormValidator.validateField(
      _localCtrl.text,
      kind: _fieldKind,
      label: widget.title,
    );
    _localCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _localCtrl.removeListener(_onChanged);
    _localCtrl.dispose();
    super.dispose();
  }

  FieldKind _resolveKind() {
    if (widget.isRoom) return FieldKind.internalTemp;
    if (widget.title == 'Esterna') return FieldKind.externalTemp;
    if (widget.title == 'Consumo') return FieldKind.consumption;
    if (widget.title == 'ACS') return FieldKind.consumptionAcs;
    if (widget.title == 'Rete') return FieldKind.energyFromGrid;
    if (widget.title == 'Fotovoltaico') return FieldKind.pvProduction;
    return FieldKind.consumption;
  }

  void _onChanged() {
    final err = RecordFormValidator.validateField(
      _localCtrl.text,
      kind: _fieldKind,
      label: widget.title,
    );
    if (err != _errorText) setState(() => _errorText = err);
  }

  void _save() {
    if (_errorText != null) return;
    widget.controller.text = _localCtrl.text;
    widget.onSave();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _adjust(double delta) {
    final current =
        double.tryParse(_localCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final next = (current + delta);
    _localCtrl.text = next.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool hasError = _errorText != null;
    final bool canSave = !hasError;

    final String suffix = widget.isConsumption ? 'kWh' : '\u00b0C';
    final String hintText = widget.isConsumption
        ? 'Es. 12.5 kWh'
        : widget.isRoom
            ? 'Es. 20.5 \u00b0C'
            : 'Es. -2.0 \u00b0C';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: widget.cardColor,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Pulsante Salva disabilitato se errore
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: TextButton.icon(
              key: ValueKey(canSave),
              onPressed: canSave ? _save : null,
              icon: Icon(
                Icons.check,
                color: canSave ? Colors.white : Colors.white38,
              ),
              label: Text(
                'Salva',
                style: TextStyle(
                  color: canSave ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // ----------------------------------------------------------------
            // TextField principale con errorText inline
            // ----------------------------------------------------------------
            TextField(
              controller: _localCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
              ],
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: hasError ? cs.error : cs.onSurface,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: 18,
                  color: hasError ? cs.error : cs.primary,
                  fontWeight: FontWeight.w600,
                ),
                // Messaggio di errore inline — nessun dialog
                errorText: _errorText,
                errorStyle: TextStyle(
                  color: cs.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: hasError
                    ? cs.errorContainer.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: hasError
                      ? BorderSide(color: cs.error, width: 2)
                      : BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: hasError ? cs.error : cs.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
            // ----------------------------------------------------------------
            // Stepper +/- (non mostrato in caso di errore non-numerico)
            // ----------------------------------------------------------------
            const SizedBox(height: 20),
            Row(
              children: [
                _stepButton(
                    icon: Icons.remove,
                    delta: widget.isConsumption ? -0.5 : -0.5,
                    cs: cs),
                const SizedBox(width: 12),
                _stepButton(
                    icon: Icons.add,
                    delta: widget.isConsumption ? 0.5 : 0.5,
                    cs: cs),
                if (!widget.isConsumption) ...[
                  const SizedBox(width: 12),
                  _stepButton(icon: Icons.remove, delta: -1.0, cs: cs,
                      label: '\u22121\u00b0'),
                  const SizedBox(width: 12),
                  _stepButton(icon: Icons.add, delta: 1.0, cs: cs,
                      label: '+1\u00b0'),
                ],
              ],
            ),
            // ----------------------------------------------------------------
            // Rating comfort (solo stanze)
            // ----------------------------------------------------------------
            if (widget.isRoom) ...[
              const SizedBox(height: 32),
              Text(
                'Come ti sei sentito?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _comfortOptions.map((opt) {
                  final emoji = opt.$1;
                  final label = opt.$2;
                  final isSelected =
                      widget.comfortRatings[widget.title] == label;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        widget.comfortRatings[widget.title] = label;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? widget.cardColor.withValues(alpha: 0.15)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? widget.cardColor
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(emoji,
                              style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required double delta,
    required ColorScheme cs,
    String? label,
  }) {
    return InkWell(
      onTap: () => _adjust(delta),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: label != null
            ? Text(
                label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface),
              )
            : Icon(icon, color: cs.onSurface, size: 20),
      ),
    );
  }
}
