// lib/features/home/widgets/room_control_page.dart
//
// UX Tado-style:
//   • Trascina su/giù sul display numerico per cambiare il valore
//   • Validazione real-time mantenuta (RecordFormValidator)
//   • Pulsante Salva disabilitato se errore
//   • Stepper +/- come fallback

import 'package:flutter/material.dart';
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
  late double _currentValue;
  String? _errorText;
  late FieldKind _fieldKind;

  // Sensibilità drag: quanti pixel verticali = 1 unità
  static const double _pixelsPerUnit = 8.0;
  double _dragAccum = 0.0;

  static const _comfortOptions = [
    ('\uD83E\uDD76', 'Troppo freddo'),
    ('\uD83D\uDE42', 'Confortevole'),
    ('\uD83E\uDD75', 'Troppo caldo'),
  ];

  @override
  void initState() {
    super.initState();
    _fieldKind = _resolveKind();
    _currentValue =
        double.tryParse(widget.controller.text.replaceAll(',', '.')) ??
            (widget.isConsumption ? 0.0 : 20.0);
    _validate();
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

  void _validate() {
    final err = RecordFormValidator.validateField(
      _currentValue.toStringAsFixed(1),
      kind: _fieldKind,
      label: widget.title,
    );
    if (err != _errorText) setState(() => _errorText = err);
  }

  void _updateValue(double newVal) {
    final step = widget.isConsumption ? 0.5 : 0.5;
    // Arrotonda al mezzo più vicino
    final snapped = (newVal / step).round() * step;
    setState(() => _currentValue = snapped);
    _validate();
  }

  void _adjust(double delta) {
    _updateValue(_currentValue + delta);
  }

  void _save() {
    if (_errorText != null) return;
    widget.controller.text = _currentValue.toStringAsFixed(1);
    widget.onSave();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool hasError = _errorText != null;
    final bool canSave = !hasError;
    final String suffix = widget.isConsumption ? 'kWh' : '\u00b0C';
    final String displayText = _currentValue.toStringAsFixed(1);

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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),

            // ----------------------------------------------------------------
            // Display numerico Tado-style — trascina su/giù
            // ----------------------------------------------------------------
            GestureDetector(
              onVerticalDragStart: (_) => _dragAccum = 0.0,
              onVerticalDragUpdate: (details) {
                _dragAccum -= details.delta.dy;
                if (_dragAccum.abs() >= _pixelsPerUnit) {
                  final steps = (_dragAccum / _pixelsPerUnit).truncate();
                  _adjust(steps * (widget.isConsumption ? 0.5 : 0.5));
                  _dragAccum -= steps * _pixelsPerUnit;
                }
              },
              child: Column(
                children: [
                  // Freccia su
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 36,
                    color: hasError
                        ? cs.error.withValues(alpha: 0.5)
                        : widget.cardColor.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 4),
                  // Valore principale
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w300,
                          color: hasError ? cs.error : cs.onSurface,
                          height: 1.0,
                          letterSpacing: -2,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12, left: 4),
                        child: Text(
                          suffix,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: hasError
                                ? cs.error
                                : cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Freccia giù
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 36,
                    color: hasError
                        ? cs.error.withValues(alpha: 0.5)
                        : widget.cardColor.withValues(alpha: 0.5),
                  ),
                  // Hint drag
                  const SizedBox(height: 8),
                  Text(
                    'Trascina su / giù per modificare',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),

            // Messaggio errore inline
            if (hasError) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: cs.error, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: cs.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Stepper +/- come fallback
            // ----------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                  _stepButton(
                      icon: Icons.remove,
                      delta: -1.0,
                      cs: cs,
                      label: '\u22121\u00b0'),
                  const SizedBox(width: 12),
                  _stepButton(
                      icon: Icons.add, delta: 1.0, cs: cs, label: '+1\u00b0'),
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
