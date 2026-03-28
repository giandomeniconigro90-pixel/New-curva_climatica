// lib/features/home/widgets/input_page.dart

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../../../core/constants/room_constants.dart';
import '../../../../models/daily_record_dto.dart';
import '../../../../services/weather_service.dart';
import 'room_control_page.dart';

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
  final bool isCooling;
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
    required this.isCooling,
    required this.onDuplicateFromYesterday,
    required this.onExportCsv,
    required this.onExportPdf,
    required this.onDeleteToday,
  });

  @override
  State<InputPage> createState() => _InputPageState();
}

class _InputPageState extends State<InputPage> {
  bool _isLoadingWeather = false;
  String? _weatherLocation;

  Future<void> _fetchWeather() async {
    setState(() => _isLoadingWeather = true);
    try {
      final result = await WeatherService.getDailyAvgTemp();
      if (result != null && mounted) {
        setState(() {
          widget.externalTempController.text =
              (result.temp as double).toStringAsFixed(1);
          _weatherLocation = result.locationName.toString();
        });
        Fluttertoast.showToast(
          msg: 'Meteo aggiornato da $_weatherLocation',
          backgroundColor: Colors.green.shade600,
          textColor: Colors.white,
          fontSize: 14,
        );
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Errore recupero meteo',
          backgroundColor: Colors.red.shade600,
          textColor: Colors.white,
          fontSize: 14,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> gridItems = [];

    gridItems.add(_buildTadoTile(
      title: 'Esterna',
      subtitle: _weatherLocation ?? 'Benessere',
      controller: widget.externalTempController,
      icon: Icons.cloud_sync,
      color: const Color(0xFF1976D2),
      isRoom: false,
      isWeatherTile: true,
      suffix: '°',
    ));

    gridItems.add(_buildTadoTile(
      title: 'Consumo',
      subtitle: 'Energy Cockpit',
      controller: widget.consumptionController,
      icon: Icons.eco_outlined,
      color: const Color(0xFF66BB6A),
      isRoom: false,
      suffix: 'kWh',
    ));

    // Unica sorgente di verità: RoomConstants.defaultRooms
    for (final room in RoomConstants.defaultRooms) {
      final ctrl = widget.internalTempControllers[room] ??
          (widget.internalTempControllers[room] = TextEditingController());
      gridItems.add(_buildTadoTile(
        title: room,
        subtitle: widget.isCooling ? 'Raffrescamento' : 'Riscaldamento',
        controller: ctrl,
        icon: null,
        color: widget.isCooling
            ? const Color(0xFF4DB6AC)
            : const Color(0xFFFFB74D),
        isRoom: true,
        suffix: '°',
      ));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isPhone = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAddRecord,
        backgroundColor: Colors.blue.shade900,
        icon: Icon(
          widget.isEditing ? Icons.save_as : Icons.check,
          color: Colors.white,
        ),
        label: Text(
          widget.isEditing ? 'AGGIORNA' : 'SALVA TUTTO',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Home',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF263238),
                    ),
                  ),
                  if (widget.records.isNotEmpty)
                    Tooltip(
                      message: 'Copia dall\'ultima registrazione',
                      child: IconButton(
                        icon: const Icon(
                          Icons.copy_all_outlined,
                          color: Color(0xFF263238),
                        ),
                        onPressed: widget.onDuplicateFromYesterday,
                      ),
                    ),
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
    bool isWeatherTile = false,
  }) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final double? val =
            double.tryParse(controller.text.replaceAll(',', '.'));
        final String displayVal = val != null ? val.toStringAsFixed(1) : '--';

        return GestureDetector(
          onTap: () =>
              _openControlPage(title, controller, suffix == 'kWh', isRoom),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isRoom || val != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayVal,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 2),
                            child: Text(
                              suffix,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox(),
                    if (isWeatherTile)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isLoadingWeather ? null : _fetchWeather,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: _isLoadingWeather
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    Icons.cloud_sync,
                                    size: 28,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                          ),
                        ),
                      )
                    else if (!isRoom && val == null)
                      Align(
                        alignment: Alignment.topRight,
                        child: Icon(
                          icon ?? Icons.help_outline,
                          size: 36,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
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

  void _openControlPage(
    String title,
    TextEditingController controller,
    bool isConsumption,
    bool isRoom,
  ) {
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
                maxHeight: MediaQuery.of(context).size.height * 0.98,
              ),
              color: Colors.white,
              child: RoomControlPage(
                title: title,
                controller: controller,
                isConsumption: isConsumption,
                isRoom: isRoom,
                comfortRatings: widget.comfortRatings,
                onSave: () => setState(() {}),
                isCooling: widget.isCooling,
              ),
            ),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              RoomControlPage(
            title: title,
            controller: controller,
            isConsumption: isConsumption,
            isRoom: isRoom,
            comfortRatings: widget.comfortRatings,
            onSave: () => setState(() {}),
            isCooling: widget.isCooling,
          ),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeOutQuint;
            final tween =
                Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
                position: animation.drive(tween), child: child);
          },
        ),
      );
    }
  }
}
