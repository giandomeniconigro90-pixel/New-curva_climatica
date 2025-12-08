// lib/features/initial_settings/initial_settings_home.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/hive_storage.dart';
import '../home/climate_curve_home.dart';

class InitialSettingsHome extends StatefulWidget {
  const InitialSettingsHome({super.key});

  @override
  State createState() => _InitialSettingsHomeState();
}

class _InitialSettingsHomeState extends State<InitialSettingsHome> {
  // Inverno
  final TextEditingController _slopeController = TextEditingController(text: "1.0");
  final TextEditingController _offsetController = TextEditingController(text: "0.0");

  // Estate
  final TextEditingController _coolingSlopeController = TextEditingController(text: "0.8");
  final TextEditingController _coolingOffsetController = TextEditingController(text: "0.0");

  @override
  void dispose() {
    _slopeController.dispose();
    _offsetController.dispose();
    _coolingSlopeController.dispose();
    _coolingOffsetController.dispose();
    super.dispose();
  }

  void _saveAndContinue() async {
    final slope = double.tryParse(_slopeController.text) ?? 1.2;
    final offset = double.tryParse(_offsetController.text) ?? 0.0;

    final cSlope = double.tryParse(_coolingSlopeController.text) ?? 0.5;
    final cOffset = double.tryParse(_coolingOffsetController.text) ?? 0.0;

    // 1. Salva parametri Inverno
    await AppStorage.saveSlope(slope);
    await AppStorage.saveOffset(offset);

    // 2. Salva parametri Estate
    await AppStorage.saveCoolingSlope(cSlope);
    await AppStorage.saveCoolingOffset(cOffset);

    // 3. Segna l'app come INIZIALIZZATA
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ICONA HEADLINE
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tune_rounded, size: 48, color: Colors.teal),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Calibrazione Impianto',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Imposta le curve climatiche della tua Pompa di Calore.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 40),

                // --- SEZIONE INVERNO ---
                _buildSectionTitle("RISCALDAMENTO (Inverno)", Icons.local_fire_department_rounded, Colors.orange.shade800),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildDialCard(
                      title: "Pendenza",
                      controller: _slopeController,
                      min: 0.1,
                      max: 3.0,
                      step: 0.1,
                      color: Colors.orange,
                    ),
                    _buildDialCard(
                      title: "Parallela",
                      controller: _offsetController,
                      min: -5.0,
                      max: 5.0,
                      step: 0.5,
                      color: Colors.orange,
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // --- SEZIONE ESTATE ---
                _buildSectionTitle("RAFFRESCAMENTO (Estate)", Icons.ac_unit_rounded, Colors.lightBlue.shade700),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildDialCard(
                      title: "Pendenza",
                      controller: _coolingSlopeController,
                      min: 0.1,
                      max: 3.0,
                      step: 0.1,
                      color: Colors.lightBlue,
                    ),
                    _buildDialCard(
                      title: "Parallela",
                      controller: _coolingOffsetController,
                      min: -5.0,
                      max: 5.0,
                      step: 0.5,
                      color: Colors.lightBlue,
                    ),
                  ],
                ),

                const SizedBox(height: 50),

                // PULSANTE SALVA
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: Colors.teal.withOpacity(0.4),
                    ),
                    child: const Text(
                      'Salva e Inizia',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildDialCard({
    required String title,
    required TextEditingController controller,
    required double min,
    required double max,
    required double step,
    required Color color,
  }) {
    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.grey.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: ThermostatDial(
            controller: controller,
            min: min,
            max: max,
            step: step,
            size: 120, // Dimensione manopola
            suffix: '',
            activeColor: color,
            useDynamicColor: false,
          ),
        ),
      ],
    );
  }
}

// --- WIDGET MANOPOLA (Copiato da input_page.dart per indipendenza) ---

class ThermostatDial extends StatefulWidget {
  final TextEditingController controller;
  final double min;
  final double max;
  final double step;
  final double size;
  final String suffix;
  final Color activeColor;
  final bool useDynamicColor;

  const ThermostatDial({
    super.key,
    required this.controller,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.size = 150,
    this.suffix = '',
    this.activeColor = Colors.blue,
    this.useDynamicColor = false,
  });

  @override
  State<ThermostatDial> createState() => _ThermostatDialState();
}

class _ThermostatDialState extends State<ThermostatDial> {
  static const double _startAngle = 2.35619; // 135 degrees in radians
  static const double _sweepAngle = 4.71239; // 270 degrees in radians

  double _currentValue = 0.0;
  double _currentAngle = _startAngle;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _updateFromController();
    widget.controller.addListener(_updateFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateFromController);
    super.dispose();
  }

  void _updateFromController() {
    if (_isDragging) return;
    double? val = double.tryParse(widget.controller.text.replaceAll(',', '.'));
    if (val == null) {
      val = widget.min; // Default safe
    }
    // Clamp value
    val = val!.clamp(widget.min, widget.max);

    setState(() {
      _currentValue = val!;
      // Map value to angle
      double t = (val! - widget.min) / (widget.max - widget.min);
      _currentAngle = _startAngle + (t * _sweepAngle);
    });
  }

  Color _getDynamicColor(double t) {
    if (!widget.useDynamicColor) return widget.activeColor;
    if (t < 0.5) return Color.lerp(Colors.lightBlueAccent, Colors.green, t * 2)!;
    return Color.lerp(Colors.green, Colors.orangeAccent, (t - 0.5) * 2)!;
  }

  void _handlePan(DragUpdateDetails details) {
    RenderBox box = context.findRenderObject() as RenderBox;
    Offset center = box.size.center(Offset.zero);
    Offset position = box.globalToLocal(details.globalPosition);

    double angle = math.atan2(position.dy - center.dy, position.dx - center.dx);
    // Normalize angle [0, 2pi]
    if (angle < 0) angle += 2 * math.pi;

    // Convert to relative angle from start
    double relativeAngle = angle - _startAngle;
    if (relativeAngle < 0) relativeAngle += 2 * math.pi;

    // Handle wrapping/bounds
    if (relativeAngle > _sweepAngle) {
      double deadZoneCenter = _sweepAngle + (2 * math.pi - _sweepAngle) / 2;
      if (relativeAngle < deadZoneCenter) {
        relativeAngle = _sweepAngle;
      } else {
        relativeAngle = 0;
      }
    }

    relativeAngle = relativeAngle.clamp(0.0, _sweepAngle);

    setState(() {
      _currentAngle = _startAngle + relativeAngle;
    });

    // Calculate value
    double t = relativeAngle / _sweepAngle;
    double rawValue = widget.min + (t * (widget.max - widget.min));

    // Snap to step
    double steppedValue = ((rawValue / widget.step).round() * widget.step);
    steppedValue = steppedValue.clamp(widget.min, widget.max);

    if ((steppedValue - _currentValue).abs() >= 0.001) {
      _currentValue = steppedValue;
      widget.controller.text = steppedValue.toStringAsFixed(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    double t = (_currentValue - widget.min) / (widget.max - widget.min);
    if (widget.max == widget.min) t = 0.0;

    Color currentColor = _getDynamicColor(t);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) {
        _isDragging = true;
        _handlePan(DragUpdateDetails(globalPosition: d.globalPosition, delta: Offset.zero));
      },
      onPanUpdate: _handlePan,
      onPanEnd: (_) => setState(() => _isDragging = false),
      // Supporto Vertical Drag per evitare conflitti in scroll view
      onVerticalDragStart: (d) {
        _isDragging = true;
        _handlePan(DragUpdateDetails(globalPosition: d.globalPosition, delta: Offset.zero));
      },
      onVerticalDragUpdate: _handlePan,
      onVerticalDragEnd: (_) => setState(() => _isDragging = false),

      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _DialPainter(
                angle: _currentAngle,
                activeColor: currentColor,
                startAngle: _startAngle,
                sweepAngle: _sweepAngle,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentValue.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: widget.size * 0.24,
                        fontWeight: FontWeight.bold,
                        color: currentColor,
                      ),
                    ),
                    if (widget.suffix.isNotEmpty)
                      Text(
                        widget.suffix,
                        style: TextStyle(
                          fontSize: widget.size * 0.12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Indicatore durante il trascinamento (opzionale, per feedback visivo)
            if (_isDragging)
              Positioned(
                top: -20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: currentColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: currentColor.withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 3)
                        )
                      ]
                  ),
                  child: Text(
                    '${_currentValue.toStringAsFixed(1)}${widget.suffix}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double angle;
  final Color activeColor;
  final double startAngle;
  final double sweepAngle;

  _DialPainter({
    required this.angle,
    required this.activeColor,
    required this.startAngle,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final strokeWidth = 14.0; // Leggermente più sottile per la config

    // Sfondo arco
    final bgPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Arco attivo
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    double currentSweep = angle - startAngle;
    if (currentSweep < 0) currentSweep = 0;
    if (currentSweep > sweepAngle) currentSweep = sweepAngle;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      currentSweep,
      false,
      activePaint,
    );

    // Pomello (Knob)
    final knobRadius = 10.0;
    final knobCenter = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );

    final knobPaint = Paint()..color = Colors.white;
    final knobBorder = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final knobShadow = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(knobCenter, knobRadius, knobShadow);
    canvas.drawCircle(knobCenter, knobRadius, knobPaint);
    canvas.drawCircle(knobCenter, knobRadius, knobBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
