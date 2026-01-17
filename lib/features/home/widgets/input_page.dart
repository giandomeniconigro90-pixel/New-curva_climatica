// lib/features/home/widgets/input_page.dart

import 'package:flutter/material.dart';
import '../../../../models/daily_record_dto.dart';

// --- INPUT PAGE: TADO STYLE (FINAL) ---
class InputPage extends StatefulWidget {
  final TextEditingController externalTempController;
  final TextEditingController consumptionController;
  final TextEditingController noteController;
  final Map<String, TextEditingController> internalTempControllers;
  final Map<String, String> comfortRatings;
  final List<DailyRecordDTO> records;
  final VoidCallback onAddRecord;
  final Function(int) onDeleteRecord;
  final Function(int) onEditRecord;
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
  final List<String> orderedRooms = [
    'Soggiorno/Cucina',
    'Bagno PT',
    'Cameretta Stefano',
    'Camera Giochi',
    'Camera Mamma e Papà',
    'Bagno 1P'
  ];

  @override
  Widget build(BuildContext context) {
    List<Widget> gridItems = [];

    // 1. Esterna
    gridItems.add(_buildTadoTile(
      title: "Esterna",
      subtitle: "Benessere",
      controller: widget.externalTempController,
      icon: Icons.wb_sunny_outlined,
      color: const Color(0xFF4DB6AC), // Ciano
      isRoom: false,
      suffix: "°",
    ));

    // 2. Consumo
    gridItems.add(_buildTadoTile(
      title: "Consumo",
      subtitle: "Energy Cockpit",
      controller: widget.consumptionController,
      icon: Icons.eco_outlined,
      color: const Color(0xFF66BB6A), // Verde
      isRoom: false,
      suffix: "kWh",
    ));

    // 3. Stanze
    for (var room in orderedRooms) {
      var ctrl = widget.internalTempControllers[room];
      if (ctrl == null) {
        ctrl = TextEditingController();
        widget.internalTempControllers[room] = ctrl;
      }
      gridItems.add(_buildTadoTile(
        title: room,
        subtitle: "Riscaldamento",
        controller: ctrl,
        icon: null,
        color: const Color(0xFFFFB74D), // Arancione
        isRoom: true,
        suffix: "°",
      ));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isPhone = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAddRecord,
        backgroundColor: Colors.black87,
        icon: Icon(widget.isEditing ? Icons.save_as : Icons.check, color: Colors.white),
        label: Text(
          widget.isEditing ? 'AGGIORNA' : 'SALVA TUTTO',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Home",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF263238)),
                  ),
                  if (!widget.isEditing)
                    IconButton(
                      onPressed: widget.onDuplicateFromYesterday,
                      icon: const Icon(Icons.copy_all, color: Colors.grey),
                      tooltip: "Copia da ieri",
                    )
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: isPhone
                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.35,
              )
                  : const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              delegate: SliverChildBuilderDelegate(
                    (context, index) => gridItems[index],
                childCount: gridItems.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildTadoTile({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required IconData? icon,
    required Color color,
    required bool isRoom,
    required String suffix,
  }) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        double? val = double.tryParse(controller.text.replaceAll(',', '.'));
        String displayVal = val != null ? val.toStringAsFixed(1) : "--";

        return GestureDetector(
          onTap: () => _openControlPage(title, controller, suffix == 'kWh', isRoom),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isRoom || val != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayVal,
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, height: 1.0),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, left: 2),
                        child: Text(
                          suffix,
                          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.topRight,
                    child: Icon(icon ?? Icons.help_outline, size: 36, color: Colors.white.withOpacity(0.3)),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 9, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openControlPage(String title, TextEditingController controller, bool isConsumption, bool isRoom) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isTablet = shortestSide >= 550;

    if (isTablet) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 450,
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.98
              ),
              color: Colors.white,
              child: RoomControlPage(
                title: title,
                controller: controller,
                isConsumption: isConsumption,
                isRoom: isRoom,
                comfortRatings: widget.comfortRatings,
                onSave: () => setState(() {}),
              ),
            ),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => RoomControlPage(
            title: title,
            controller: controller,
            isConsumption: isConsumption,
            isRoom: isRoom,
            comfortRatings: widget.comfortRatings,
            onSave: () => setState(() {}),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeOutQuint;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        ),
      );
    }
  }
}

// --- PAINTER PER IL CERCHIO GRADO ---
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
    // Offset spostato un "pelo" a destra: da 2.0 a 6.0
    final center = Offset(10 + radius, -9.0);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


// --- PAGINA CONTROLLO ---
class RoomControlPage extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final bool isConsumption;
  final bool isRoom;
  final Map<String, String>? comfortRatings;
  final VoidCallback onSave;

  const RoomControlPage({
    super.key,
    required this.title,
    required this.controller,
    required this.isConsumption,
    required this.isRoom,
    this.comfortRatings,
    required this.onSave,
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

  final double _sliderHeight = 380.0;

  @override
  void initState() {
    super.initState();
    _currentValue = double.tryParse(widget.controller.text.replaceAll(',', '.')) ??
        (widget.isConsumption ? 15.0 : (widget.isRoom ? 20.0 : 12.0));

    if (widget.isRoom && widget.comfortRatings != null) {
      _currentComfort = widget.comfortRatings![widget.title] ?? 'ok';
    } else {
      _currentComfort = 'ok';
    }

    if (widget.isConsumption) {
      _min = 0; _max = 100;
      _mainColor = const Color(0xFF66BB6A);
      _headerText = "CONSUMO GIORNALIERO";
    } else if (widget.isRoom) {
      _min = 15; _max = 28;
      _mainColor = const Color(0xFFFFB74D);
      _headerText = "TEMPERATURA INTERNA";
    } else {
      _min = -10; _max = 40;
      _mainColor = const Color(0xFF4DB6AC);
      _headerText = "TEMPERATURA ESTERNA";
    }
  }

  @override
  Widget build(BuildContext context) {
    double percentage = (_currentValue - _min) / (_max - _min);
    percentage = percentage.clamp(0.0, 1.0);

    String fullText = _currentValue.toStringAsFixed(1);
    List<String> parts = fullText.split('.');
    String integerPart = parts[0];
    String decimalPart = parts.length > 1 ? parts[1] : "0";

    return Scaffold(
      backgroundColor: _mainColor,
      body: SafeArea(
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
                  Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.white, size: 28),
                    onPressed: _saveAndExit,
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),

            Column(
              children: [
                Text(_headerText, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                        integerPart,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 50,
                            fontWeight: FontWeight.bold,
                            height: 1.0
                        )
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
                              style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "kWh",
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 18, fontWeight: FontWeight.bold),
                            )
                          ],
                        ),
                      )
                    else
                      Transform.translate(
                        offset: const Offset(-5.0, 0.0),
                        child: CustomPaint(
                          foregroundPainter: DegreePainter(color: Colors.white),
                          child: Text(
                            ".$decimalPart",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                                height: 1.0
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            const Spacer(flex: 1),

            Center(
              child: Container(
                width: 220,
                height: _sliderHeight,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(40)
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        width: double.infinity,
                        height: _sliderHeight * percentage,
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
                                  inactiveTrackColor: Colors.transparent
                              ),
                              child: Slider(
                                  value: _currentValue,
                                  min: _min,
                                  max: _max,
                                  onChanged: (val) {
                                    setState(() { _currentValue = val; });
                                  }
                              )
                          )
                      ),
                      Positioned(
                          bottom: (_sliderHeight * percentage) - 10,
                          child: Container(
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                  color: _mainColor.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(5)
                              )
                          )
                      )
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
                        _buildComfortOption('caldo', Icons.local_fire_department)
                      ]
                  )
              )
            else const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildComfortOption(String value, IconData icon) {
    final isSelected = _currentComfort == value;
    return GestureDetector(
      onTap: () => setState(() => _currentComfort = value),
      child: Column(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: isSelected ? _mainColor : Colors.white, size: 24)), const SizedBox(height: 8), Text(value.toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold))]),
    );
  }

  void _saveAndExit() {
    widget.controller.text = _currentValue.toStringAsFixed(1);
    if (widget.isRoom && widget.comfortRatings != null) {
      widget.comfortRatings![widget.title] = _currentComfort;
    }
    widget.onSave();
    Navigator.pop(context);
  }
}
