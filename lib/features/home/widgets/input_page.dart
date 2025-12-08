// lib/features/home/widgets/input_page.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/daily_record_dto.dart';
import '../../../services/hive_storage.dart';
import '../../../services/weather_service.dart'; // Importa il servizio aggiornato

class InputPage extends StatefulWidget {
  final TextEditingController externalTempController;
  final TextEditingController consumptionController;
  final TextEditingController noteController;
  final Map<String, TextEditingController> internalTempControllers;
  final Map<String, String> comfortRatings;
  final List<DailyRecordDTO> records;
  final VoidCallback onAddRecord;
  final void Function(int index) onDeleteRecord;
  final void Function(int index) onEditRecord;
  final bool isEditing;
  final VoidCallback onDuplicateFromYesterday;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;
  final VoidCallback onDeleteToday;

  const InputPage({
    super.key,
    required this.externalTempController,
    required this.consumptionController,
    required this.noteController,
    required this.internalTempControllers,
    required this.comfortRatings,
    required this.records,
    required this.onAddRecord,
    required this.onDeleteRecord,
    required this.onEditRecord,
    required this.isEditing,
    required this.onDuplicateFromYesterday,
    required this.onExportCsv,
    required this.onExportPdf,
    required this.onDeleteToday,
  });

  @override
  State<InputPage> createState() => _InputPageState();
}

class _InputPageState extends State<InputPage> {
  String _systemMode = 'heating';
  bool _isLoadingWeather = false;

  @override
  void initState() {
    super.initState();
    _loadSystemMode();
  }

  Future<void> _loadSystemMode() async {
    final mode = await AppStorage.getSystemMode();
    if (mounted) {
      setState(() {
        _systemMode = mode;
      });
    }
  }

  // --- LOGICA METEO AGGIORNATA ---
  Future<void> _fetchAutomaticWeather() async {
    setState(() => _isLoadingWeather = true);

    // Ora riceviamo un oggetto WeatherData (temp + cittÃ )
    final WeatherData? data = await WeatherService.getDailyAvgTemp();

    if (mounted) {
      setState(() {
        _isLoadingWeather = false;
        if (data != null) {
          widget.externalTempController.text = data.temp.toStringAsFixed(1);

          // Messaggio che include la CITTÃ€
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text("Meteo: ${data.locationName} (${data.temp}Â°C)")),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              )
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Impossibile trovare posizione o meteo."),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red,
              )
          );
        }
      });
    }
  }

  void _validateAndSubmit() {
    final double? extTemp = double.tryParse(widget.externalTempController.text.replaceAll(',', '.'));
    if (extTemp == null || extTemp < -20 || extTemp > 45) {
      _showError('Temperatura esterna non valida (-20 a 45)');
      return;
    }

    final double? cons = double.tryParse(widget.consumptionController.text.replaceAll(',', '.'));
    if (cons == null || cons < 0) {
      _showError('Consumo non valido');
      return;
    }

    widget.onAddRecord();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Color _getSeasonalColor() {
    if (widget.isEditing) return Colors.amber.shade900;
    return _systemMode == 'heating'
        ? const Color(0xFFE65100)
        : const Color(0xFF00695C);
  }

  Widget _buildComfortIcon(String room, String value, IconData icon, Color color) {
    final isSelected = widget.comfortRatings[room] == value;
    return GestureDetector(
      onTap: () => setState(() => widget.comfortRatings[room] = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))]
              : [],
        ),
        child: Icon(icon, color: isSelected ? Colors.white : Colors.grey.shade400, size: 18),
      ),
    );
  }

  Widget _buildExternalDataCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required String suffix,
    double min = -50,
    double max = 100,
  }) {
    final bool isTempCard = title == 'ESTERNA';

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5)),

                if (isTempCard) ...[
                  const SizedBox(width: 8),
                  if (_isLoadingWeather)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
                  else
                    InkWell(
                      onTap: _fetchAutomaticWeather,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                        child: const Icon(Icons.cloud_download_rounded, size: 16, color: Colors.blue),
                      ),
                    )
                ]
              ],
            ),
            const SizedBox(height: 4),
            ThermostatDial(
              controller: controller,
              min: min,
              max: max,
              step: 0.1,
              size: 130,
              suffix: suffix,
              activeColor: iconColor,
              useDynamicColor: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomTile(String room, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            room,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF455A64)),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          ThermostatDial(
            controller: controller,
            min: 0,
            max: 45,
            step: 0.1,
            size: 145,
            suffix: 'Â°C',
            useDynamicColor: true,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildComfortIcon(room, 'freddo', Icons.ac_unit_rounded, Colors.blue),
                _buildComfortIcon(room, 'ok', Icons.check, Colors.green),
                _buildComfortIcon(room, 'caldo', Icons.local_fire_department_rounded, Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderedRooms = widget.internalTempControllers.keys.toList()..sort();
    final buttonColor = _getSeasonalColor();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SEZIONE ESTERNA
              Row(
                children: [
                  _buildExternalDataCard(
                    title: 'ESTERNA',
                    icon: Icons.wb_sunny_rounded,
                    iconColor: Colors.orange,
                    controller: widget.externalTempController,
                    suffix: 'Â°C',
                    min: -20,
                    max: 45,
                  ),
                  const SizedBox(width: 12),
                  _buildExternalDataCard(
                    title: 'CONSUMO',
                    icon: Icons.flash_on_rounded,
                    iconColor: Colors.blue,
                    controller: widget.consumptionController,
                    suffix: 'kWh',
                    min: 0,
                    max: 25,
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  'TEMPERATURE INTERNE',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                ),
              ),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: orderedRooms.map((room) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 12) / 2;
                      return SizedBox(
                        width: width,
                        child: _buildRoomTile(room, widget.internalTempControllers[room]!),
                      );
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: widget.noteController,
                  decoration: const InputDecoration(
                    hintText: 'Note opzionali...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 15),
                    border: InputBorder.none,
                    icon: Icon(Icons.notes_rounded, color: Colors.grey, size: 22),
                  ),
                  maxLines: 1,
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _validateAndSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text(
                    widget.isEditing ? 'SALVA MODIFICHE' : 'AGGIUNGI REGISTRAZIONE',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (!widget.isEditing)
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: widget.onDuplicateFromYesterday,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copia da Ieri', style: TextStyle(fontSize: 14)),
                        style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                      ),
                    ),
                    Container(width: 1, height: 16, color: Colors.grey.shade300),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: widget.onDeleteToday,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Elimina Oggi', style: TextStyle(fontSize: 14)),
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- WIDGET MANOPOLA (Resta invariato) ---
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
  static const double _startAngle = 2.35619;
  static const double _sweepAngle = 4.71239;

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
    if (val == null) val = widget.min;
    val = val!.clamp(widget.min, widget.max);

    setState(() {
      _currentValue = val!;
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
    if (angle < 0) angle += 2 * math.pi;

    double relativeAngle = angle - _startAngle;
    if (relativeAngle < 0) relativeAngle += 2 * math.pi;

    if (relativeAngle > _sweepAngle) {
      double deadZoneCenter = _sweepAngle + (2 * math.pi - _sweepAngle) / 2;
      if (relativeAngle < deadZoneCenter) relativeAngle = _sweepAngle;
      else relativeAngle = 0;
    }

    relativeAngle = relativeAngle.clamp(0.0, _sweepAngle);

    setState(() => _currentAngle = _startAngle + relativeAngle);

    double t = relativeAngle / _sweepAngle;
    double rawValue = widget.min + (t * (widget.max - widget.min));
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
                      style: TextStyle(fontSize: widget.size * 0.24, fontWeight: FontWeight.bold, color: currentColor),
                    ),
                    Text(widget.suffix, style: TextStyle(fontSize: widget.size * 0.12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            if (_isDragging)
              Positioned(
                top: -20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: currentColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: currentColor.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 3))]
                  ),
                  child: Text('${_currentValue.toStringAsFixed(1)}${widget.suffix}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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

  _DialPainter({required this.angle, required this.activeColor, required this.startAngle, required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final strokeWidth = 18.0;

    final bgPaint = Paint()..color = Colors.grey.shade200..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = strokeWidth;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, bgPaint);

    final activePaint = Paint()..color = activeColor..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = strokeWidth;
    double currentSweep = angle - startAngle;
    if (currentSweep < 0) currentSweep = 0;
    if (currentSweep > sweepAngle) currentSweep = sweepAngle;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, currentSweep, false, activePaint);

    final knobRadius = 12.0;
    final knobCenter = Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
    final knobPaint = Paint()..color = Colors.white;
    final knobBorder = Paint()..color = activeColor..style = PaintingStyle.stroke..strokeWidth = 3.0;
    final knobShadow = Paint()..color = Colors.black.withOpacity(0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(knobCenter, knobRadius, knobShadow);
    canvas.drawCircle(knobCenter, knobRadius, knobPaint);
    canvas.drawCircle(knobCenter, knobRadius, knobBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}