// lib/features/home/widgets/room_control_page.dart
//
// UX originale Tado ripristinata:
//   • Sfondo blur colorato fullscreen
//   • Slider bianco verticale che si riempie dal basso
//   • Validazione real-time mantenuta (RecordFormValidator) senza rompere l'UX

import 'dart:ui';
import 'package:flutter/material.dart';
import '../logic/record_form_validator.dart';

class DegreePainter extends CustomPainter {
  final Color color;

  DegreePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    const double radius = 5.0;
    final center = Offset(10 + radius, -9.0);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RoomControlPage extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final bool isConsumption;
  final bool isRoom;
  final Map<String, String>? comfortRatings;
  final VoidCallback onSave;
  final bool isCooling;
  final Color? cardColor;

  const RoomControlPage({
    super.key,
    required this.title,
    required this.controller,
    required this.isConsumption,
    required this.isRoom,
    this.comfortRatings,
    required this.onSave,
    required this.isCooling,
    this.cardColor,
  });

  @override
  State<RoomControlPage> createState() => _RoomControlPageState();
}

class _RoomControlPageState extends State<RoomControlPage> {
  late double _currentValue;
  late String _currentComfort;
  late double _min, _max;
  late Color _mainColor;
  late String _headerText;
  String? _errorText;
  late FieldKind _fieldKind;

  @override
  void initState() {
    super.initState();
    _currentValue = double.tryParse(widget.controller.text.replaceAll(',', '.')) ??
        (widget.isConsumption ? 5.0 : (widget.isRoom ? 20.0 : 15.0));

    if (widget.isRoom && widget.comfortRatings != null) {
      _currentComfort = widget.comfortRatings![widget.title] ?? 'ok';
    } else {
      _currentComfort = 'ok';
    }

    if (widget.isRoom) {
      _min = 10; _max = 45;
      _mainColor = widget.cardColor ??
          (widget.isCooling ? const Color(0xFF4DB6AC) : const Color(0xFFFFB74D));
      _headerText = "TEMPERATURA INTERNA";
      _fieldKind = FieldKind.internalTemp;
    } else if (widget.isConsumption) {
      _min = 0; _max = 100;
      _mainColor = widget.cardColor ?? const Color(0xFF66BB6A);
      _headerText = "CONSUMO GIORNALIERO";
      _fieldKind = _resolveConsumptionKind();
    } else {
      _min = -30; _max = 40; // esteso da -10 a -30°C
      _mainColor = widget.cardColor ?? const Color(0xFF1976D2);
      _headerText = "TEMPERATURA ESTERNA";
      _fieldKind = FieldKind.externalTemp;
    }
    _validate();
  }

  FieldKind _resolveConsumptionKind() {
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

  bool get _canSave => _errorText == null;

  @override
  Widget build(BuildContext context) {
    final double sliderHeight = MediaQuery.of(context).size.height
        .clamp(260.0 / 0.45, 420.0 / 0.45) * 0.45;

    double percentage = (_currentValue - _min) / (_max - _min);
    percentage = percentage.clamp(0.0, 1.0);

    String fullText = _currentValue.toStringAsFixed(1);
    List<String> parts = fullText.split('.');
    String integerPart = parts[0];
    String decimalPart = parts.length > 1 ? parts[1] : "0";

    final bool hasError = _errorText != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: _mainColor.withValues(alpha: 0.75),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(widget.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      Tooltip(
                        message: hasError ? (_errorText ?? '') : '',
                        child: IconButton(
                          icon: Icon(
                            Icons.check,
                            color: _canSave ? Colors.white : Colors.white38,
                            size: 28,
                          ),
                          onPressed: _canSave ? _saveAndExit : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 1),
                Column(
                  children: [
                    Text(
                      _headerText,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          integerPart,
                          style: TextStyle(
                            color: hasError ? Colors.red.shade200 : Colors.white,
                            fontSize: 50,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                        if (widget.isConsumption)
                          Padding(
                            padding: const EdgeInsets.only(top: 25),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  ".$decimalPart",
                                  style: TextStyle(
                                      color: hasError ? Colors.red.shade200 : Colors.white,
                                      fontSize: 25,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "kWh",
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        else
                          Transform.translate(
                            offset: const Offset(-1.0, 0.0),
                            child: CustomPaint(
                              foregroundPainter: DegreePainter(color: Colors.white),
                              child: Text(
                                ".$decimalPart",
                                style: TextStyle(
                                  color: hasError ? Colors.red.shade200 : Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _errorText!,
                          style: TextStyle(
                              color: Colors.red.shade200,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
                const Spacer(flex: 1),
                Center(
                  child: Container(
                    width: 220,
                    height: sliderHeight,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            width: double.infinity,
                            height: sliderHeight * percentage,
                            color: Colors.white,
                          ),
                          RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 220,
                                thumbShape: SliderComponentShape.noThumb,
                                overlayShape: SliderComponentShape.noOverlay,
                                activeTrackColor: Colors.transparent,
                                inactiveTrackColor: Colors.transparent,
                              ),
                              child: Slider(
                                value: _currentValue,
                                min: _min,
                                max: _max,
                                onChanged: (val) {
                                  setState(() => _currentValue = val);
                                  _validate();
                                },
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: (sliderHeight * percentage) - 10,
                            child: Container(
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _mainColor.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 5),
                if (widget.isRoom)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildComfortOption('freddo', Icons.ac_unit),
                        const SizedBox(width: 40),
                        _buildComfortOption('ok', Icons.sentiment_satisfied_alt),
                        const SizedBox(width: 40),
                        _buildComfortOption('caldo', Icons.local_fire_department),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComfortOption(String value, IconData icon) {
    final isSelected = _currentComfort == value;
    return GestureDetector(
      onTap: () => setState(() => _currentComfort = value),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isSelected ? _mainColor : Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            value.toUpperCase(),
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _saveAndExit() {
    if (!_canSave) return;
    widget.controller.text = _currentValue.toStringAsFixed(1);
    if (widget.isRoom && widget.comfortRatings != null) {
      widget.comfortRatings![widget.title] = _currentComfort;
    }
    widget.onSave();
    Navigator.pop(context);
  }
}
