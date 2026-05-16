// lib/features/home/widgets/room_control_page.dart
//
// UX Tado-style — barra verticale:
//   • Barra verticale che si riempie dal basso verso l'alto
//   • Trascina su/giù sulla barra per cambiare il valore
//   • Tap diretto sulla barra per impostare il valore in proporzione
//   • Validazione real-time mantenuta (RecordFormValidator)
//   • Pulsante Salva disabilitato se errore
//   • Stepper +/- come fallback

import 'dart:math' as math;
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

class _RoomControlPageState extends State<RoomControlPage>
    with SingleTickerProviderStateMixin {
  late double _currentValue;
  String? _errorText;
  late FieldKind _fieldKind;
  late AnimationController _animCtrl;
  late Animation<double> _fillAnim;
  double _prevFill = 0.0;

  // Range dipendente dal tipo di campo
  late double _minVal;
  late double _maxVal;

  static const _comfortOptions = [
    ('\uD83E\uDD76', 'Troppo freddo'),
    ('\uD83D\uDE42', 'Confortevole'),
    ('\uD83E\uDD75', 'Troppo caldo'),
  ];

  @override
  void initState() {
    super.initState();
    _fieldKind = _resolveKind();
    _setRange();
    _currentValue = (double.tryParse(
                widget.controller.text.replaceAll(',', '.')) ??
            (widget.isConsumption ? 0.0 : 20.0))
        .clamp(_minVal, _maxVal);
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fillAnim = Tween<double>(begin: _fillFraction, end: _fillFraction)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _prevFill = _fillFraction;
    _validate();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
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

  void _setRange() {
    if (widget.isConsumption) {
      _minVal = 0.0;
      _maxVal = 100.0;
    } else if (_fieldKind == FieldKind.externalTemp) {
      _minVal = -30.0;
      _maxVal = 50.0;
    } else {
      _minVal = 0.0;
      _maxVal = 40.0;
    }
  }

  double get _fillFraction =>
      ((_currentValue - _minVal) / (_maxVal - _minVal)).clamp(0.0, 1.0);

  void _animateTo(double newFill) {
    _fillAnim = Tween<double>(begin: _prevFill, end: newFill).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _prevFill = newFill;
    _animCtrl
      ..reset()
      ..forward();
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
    const step = 0.5;
    final snapped = ((newVal / step).round() * step).clamp(_minVal, _maxVal);
    if (snapped == _currentValue) return;
    setState(() => _currentValue = snapped);
    _animateTo(_fillFraction);
    _validate();
  }

  void _adjust(double delta) => _updateValue(_currentValue + delta);

  void _save() {
    if (_errorText != null) return;
    widget.controller.text = _currentValue.toStringAsFixed(1);
    widget.onSave();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  // Drag sulla barra
  double _barHeight = 300.0;
  double _dragStartY = 0.0;
  double _dragStartVal = 0.0;

  void _onBarTapDown(TapDownDetails d, double barH) {
    final fraction = 1.0 - (d.localPosition.dy / barH).clamp(0.0, 1.0);
    _updateValue(_minVal + fraction * (_maxVal - _minVal));
  }

  void _onDragStart(DragStartDetails d) {
    _dragStartY = d.localPosition.dy;
    _dragStartVal = _currentValue;
  }

  void _onDragUpdate(DragUpdateDetails d, double barH) {
    final dy = d.localPosition.dy - _dragStartY;
    final delta = -(dy / barH) * (_maxVal - _minVal);
    _updateValue(_dragStartVal + delta);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool hasError = _errorText != null;
    final bool canSave = !hasError;
    final String suffix = widget.isConsumption ? 'kWh' : '\u00b0C';
    final Color barColor = hasError ? cs.error : widget.cardColor;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: widget.cardColor,
        foregroundColor: Colors.white,
        title:
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: TextButton.icon(
              key: ValueKey(canSave),
              onPressed: canSave ? _save : null,
              icon: Icon(Icons.check,
                  color: canSave ? Colors.white : Colors.white38),
              label: Text('Salva',
                  style: TextStyle(
                      color: canSave ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),

            // ----------------------------------------------------------------
            // Layout principale: barra a sinistra + valore a destra
            // ----------------------------------------------------------------
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // -------------- BARRA VERTICALE TADO ----------------------
                  LayoutBuilder(builder: (ctx, constraints) {
                    _barHeight = constraints.maxHeight;
                    return GestureDetector(
                      onTapDown: (d) => _onBarTapDown(d, _barHeight),
                      onVerticalDragStart: _onDragStart,
                      onVerticalDragUpdate: (d) =>
                          _onDragUpdate(d, _barHeight),
                      child: SizedBox(
                        width: 72,
                        height: _barHeight,
                        child: AnimatedBuilder(
                          animation: _fillAnim,
                          builder: (_, __) {
                            final fill = _fillAnim.value;
                            return CustomPaint(
                              painter: _TadoBarPainter(
                                fillFraction: fill,
                                fillColor: barColor,
                                trackColor: cs.surfaceContainerHighest,
                                radius: 36,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }),

                  const SizedBox(width: 32),

                  // -------------- VALORE + STEPPER --------------------------
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Valore numerico grande
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _currentValue.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 72,
                                  fontWeight: FontWeight.w300,
                                  color: hasError ? cs.error : cs.onSurface,
                                  height: 1.0,
                                  letterSpacing: -2,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10, left: 4),
                                child: Text(
                                  suffix,
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: hasError
                                        ? cs.error
                                        : cs.onSurface.withValues(alpha: 0.55),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Errore
                        if (hasError) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: cs.error, size: 15),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(_errorText!,
                                    style: TextStyle(
                                        color: cs.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 32),

                        // Stepper +/-
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _stepButton(
                                icon: Icons.remove,
                                delta: -0.5,
                                cs: cs),
                            _stepButton(
                                icon: Icons.add,
                                delta: 0.5,
                                cs: cs),
                            if (!widget.isConsumption) ...[
                              _stepButton(
                                  icon: Icons.remove,
                                  delta: -1.0,
                                  cs: cs,
                                  label: '\u22121\u00b0'),
                              _stepButton(
                                  icon: Icons.add,
                                  delta: 1.0,
                                  cs: cs,
                                  label: '+1\u00b0'),
                            ],
                          ],
                        ),

                        const SizedBox(height: 16),
                        Text(
                          'Scorri la barra o usa i tasti',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.35)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ----------------------------------------------------------------
            // Rating comfort (solo stanze)
            // ----------------------------------------------------------------
            if (widget.isRoom) ...[
              const SizedBox(height: 16),
              Text('Come ti sei sentito?',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _comfortOptions.map((opt) {
                  final emoji = opt.$1;
                  final label = opt.$2;
                  final isSelected =
                      widget.comfortRatings[widget.title] == label;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => widget.comfortRatings[widget.title] = label),
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
                          Text(emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 4),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
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
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: label != null
            ? Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface))
            : Icon(icon, color: cs.onSurface, size: 20),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CustomPainter — barra verticale stile Tado
// ---------------------------------------------------------------------------

class _TadoBarPainter extends CustomPainter {
  final double fillFraction;
  final Color fillColor;
  final Color trackColor;
  final double radius;

  const _TadoBarPainter({
    required this.fillFraction,
    required this.fillColor,
    required this.trackColor,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rr = math.min(radius, size.width / 2);
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(rr));

    // Track (sfondo)
    canvas.drawRRect(rrect, Paint()..color = trackColor);

    // Fill dal basso
    final fillHeight = size.height * fillFraction;
    if (fillHeight > 0) {
      final fillRect = Rect.fromLTWH(
          0, size.height - fillHeight, size.width, fillHeight);
      final fillRRect = RRect.fromRectAndCorners(
        fillRect,
        bottomLeft: Radius.circular(rr),
        bottomRight: Radius.circular(rr),
        topLeft: fillFraction >= 0.99 ? Radius.circular(rr) : Radius.zero,
        topRight: fillFraction >= 0.99 ? Radius.circular(rr) : Radius.zero,
      );
      // Gradient verticale per effetto Tado
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            fillColor,
            fillColor.withValues(alpha: 0.75),
          ],
        ).createShader(fillRect);
      canvas.drawRRect(fillRRect, paint);

      // Linea indicatore in cima al fill
      if (fillFraction > 0.01 && fillFraction < 0.99) {
        final lineY = size.height - fillHeight;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, lineY, size.width, 3),
            const Radius.circular(2),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.9),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TadoBarPainter old) =>
      old.fillFraction != fillFraction ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor;
}
