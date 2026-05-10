// lib/features/home/widgets/input_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../../../../models/daily_record_dto.dart';
import '../../../../services/hive_storage.dart';
import '../../../../services/weather_service.dart';
import '../../../../utils/app_toast.dart';
import 'room_control_page.dart';

class InputPage extends StatefulWidget {
  final TextEditingController externalTempController;
  final TextEditingController consumptionController;
  final TextEditingController consumptionAcsController;
  final TextEditingController energyFromGridController;
  final TextEditingController pvProductionController;
  final TextEditingController noteController;
  final ValueNotifier<String> heatpumpModeNotifier;
  final ValueNotifier<String> boilerModeNotifier;
  final Map<String, TextEditingController> internalTempControllers;
  final Map<String, String> comfortRatings;
  final List<DailyRecordDTO> records;
  final List<String> rooms;
  final VoidCallback onAddRecord;
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
    required this.consumptionAcsController,
    required this.energyFromGridController,
    required this.pvProductionController,
    required this.noteController,
    required this.heatpumpModeNotifier,
    required this.boilerModeNotifier,
    required this.internalTempControllers,
    required this.comfortRatings,
    required this.records,
    required this.rooms,
    required this.onAddRecord,
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

class _InputPageState extends State<InputPage> with WidgetsBindingObserver {
  bool _isLoadingWeather = false;
  String? _weatherLocation;

  // true dopo un auto-fetch RIUSCITO: blocca re-fetch automatici inutili.
  // Si resetta se il fetch fallisce, se la città cambia o se l'app torna da background.
  // Il tap manuale ☁️ NON è mai influenzato da questo flag.
  bool _autoFetchDone = false;

  // Città al momento dell'ultimo auto-fetch riuscito.
  String? _lastAutoFetchCity;

  static const Color _colorEsterna      = Color(0xFF1976D2);
  static const Color _colorConsumo      = Color(0xFF66BB6A);
  static const Color _colorAcs          = Color(0xFF26A69A);
  static const Color _colorRete         = Color(0xFFF57C00);
  static const Color _colorFotovoltaico = Color(0xFFFDD835);
  static const Color _colorNota         = Color(0xFF7E57C2);

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFetchIfNeeded());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoFetchDone = false;
      _autoFetchIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant InputPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _autoFetchIfNeeded();
  }

  void _autoFetchIfNeeded() {
    if (!mounted) return;
    final currentCity = AppStorage.getCityOverride();

    // Resetta se la città è cambiata.
    if (_autoFetchDone && currentCity != _lastAutoFetchCity) {
      _autoFetchDone = false;
    }

    // Auto-fetch già riuscito in questa sessione: niente da fare.
    if (_autoFetchDone) return;

    // Marca la città corrente: se il fetch fallisce, _autoFetchDone resterà false
    // e il prossimo trigger (cambio tab, resume) riproverà automaticamente.
    _lastAutoFetchCity = currentCity;

    _fetchWeather(silent: true, isAutoFetch: true);
  }

  Color _cardColor(BuildContext context, Color base) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? base.withValues(alpha: 0.55) : base;
  }

  String get _weatherSubtitle {
    if (_weatherLocation != null) return _weatherLocation!;
    final age = WeatherService.getCacheAgeMinutes();
    if (age == null) return 'Benessere';
    if (age == 0) return 'Adesso';
    return '$age min fa';
  }

  /// [isAutoFetch] = true: aggiorna _autoFetchDone solo in caso di successo.
  /// Se fallisce, _autoFetchDone rimane false e il prossimo trigger riprova.
  /// Il tap manuale usa isAutoFetch = false: non tocca mai _autoFetchDone.
  Future<void> _fetchWeather({
    bool silent = false,
    bool isAutoFetch = false,
  }) async {
    if (_isLoadingWeather) return;

    setState(() => _isLoadingWeather = true);
    try {
      final result = await WeatherService.getDailyAvgTemp();
      if (!mounted) return;
      if (result != null) {
        // Successo: marca l'auto-fetch come completato.
        if (isAutoFetch) _autoFetchDone = true;
        setState(() {
          widget.externalTempController.text = result.temp.toStringAsFixed(1);
          _weatherLocation = result.locationName;
        });
        if (!silent) {
          AppToast.show(
            'Meteo aggiornato da $_weatherLocation',
            context: context,
            level: ToastLevel.success,
          );
        }
      } else {
        // Fallimento: se era auto-fetch, _autoFetchDone resta false → riproverà.
        if (!silent) {
          AppToast.show(
            'Meteo non disponibile. Controlla GPS e connessione.',
            context: context,
            level: ToastLevel.warning,
            duration: const Duration(seconds: 5),
          );
        }
      }
    } catch (e) {
      // Errore: stesso comportamento del fallimento.
      if (mounted && !silent) {
        AppToast.show(
          'Errore recupero meteo',
          context: context,
          level: ToastLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool hasGridMeter = AppStorage.getHasGridMeter();
    final bool hasPv        = AppStorage.getHasPv();
    final List<Widget> gridItems = [];

    gridItems.add(_buildTadoTile(title: 'Esterna', subtitle: _weatherSubtitle, controller: widget.externalTempController, icon: Icons.cloud_sync, color: _colorEsterna, isRoom: false, isWeatherTile: true, suffix: '\u00b0'));
    gridItems.add(_buildTadoTile(title: 'Consumo', subtitle: 'ShinePhone', controller: widget.consumptionController, icon: Icons.eco_outlined, color: _colorConsumo, isRoom: false, suffix: 'kWh'));
    gridItems.add(_buildTadoTile(title: 'ACS', subtitle: 'Cozytouch', controller: widget.consumptionAcsController, icon: Icons.water_drop_outlined, color: _colorAcs, isRoom: false, suffix: 'kWh'));
    if (hasGridMeter) gridItems.add(_buildTadoTile(title: 'Rete', subtitle: 'ShinePhone', controller: widget.energyFromGridController, icon: Icons.electrical_services_outlined, color: _colorRete, isRoom: false, suffix: 'kWh'));
    if (hasPv) gridItems.add(_buildTadoTile(title: 'Fotovoltaico', subtitle: 'ShinePhone', controller: widget.pvProductionController, icon: Icons.wb_sunny_outlined, color: _colorFotovoltaico, isRoom: false, suffix: 'kWh'));
    gridItems.add(_buildHeatpumpModeTile());
    gridItems.add(_buildBoilerModeTile());
    // Tile Nota: sempre visibile, si apre in una bottom sheet.
    gridItems.add(_buildNotaTile());
    for (final room in widget.rooms) {
      final ctrl = widget.internalTempControllers[room] ?? (widget.internalTempControllers[room] = TextEditingController());
      gridItems.add(_buildTadoTile(title: room, subtitle: widget.isCooling ? 'Raffrescamento' : 'Riscaldamento', controller: ctrl, icon: null, color: widget.isCooling ? const Color(0xFF4DB6AC) : const Color(0xFFFFB74D), isRoom: true, suffix: '\u00b0'));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isPhone = screenWidth < 600;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAddRecord,
        backgroundColor: cs.primary,
        icon: Icon(widget.isEditing ? Icons.save_as : Icons.check, color: cs.onPrimary),
        label: Text(widget.isEditing ? 'AGGIORNA' : 'SALVA TUTTO', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimary)),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Home', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (widget.records.isNotEmpty)
                    Tooltip(
                      message: "Copia dall'ultima registrazione",
                      child: IconButton(icon: Icon(Icons.copy_all_outlined, color: cs.onSurface), onPressed: widget.onDuplicateFromYesterday),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: isPhone
                  ? const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.35)
                  : const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.1),
              delegate: SliverChildBuilderDelegate((context, index) => gridItems[index], childCount: gridItems.length),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildNotaTile() {
    return ListenableBuilder(
      listenable: widget.noteController,
      builder: (context, _) {
        final hasNote = widget.noteController.text.trim().isNotEmpty;
        final effectiveColor = _cardColor(context, _colorNota);
        return GestureDetector(
          onTap: _openNotaSheet,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: effectiveColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: effectiveColor.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      hasNote ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
                      size: 30,
                      color: Colors.white,
                    ),
                    if (hasNote)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Annotazione',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hasNote ? widget.noteController.text.trim() : 'Nota',
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

  void _openNotaSheet() {
    final tempController = TextEditingController(text: widget.noteController.text);

    // _commitNote sincronizza sempre tempController → noteController.
    // Viene chiamato dal bottone ✓ E da onClosing (swipe dismiss incluso).
    void commitNote() {
      widget.noteController.text = tempController.text;
      if (mounted) setState(() {});
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // FIX #1: onClosing garantisce il salvataggio anche su swipe-dismiss.
      // Viene invocato PRIMA che il bottom sheet venga rimosso dall'albero,
      // quindi noteController è ancora accessibile.
      onClosing: commitNote,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Nota del giorno',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tempController,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Es: finestra aperta, ospiti, anomalia caldaia…',
                  filled: true,
                  fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Cancella nota'),
                  onPressed: () {
                    tempController.clear();
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeatpumpModeTile() {
    return ValueListenableBuilder<String>(
      valueListenable: widget.heatpumpModeNotifier,
      builder: (context, mode, _) {
        Color baseColor;
        IconData icon;
        String label;
        switch (mode) {
          case 'riscaldamento': baseColor = const Color(0xFFFF9800); icon = Icons.local_fire_department_outlined; label = 'Riscaldamento'; break;
          case 'raffrescamento': baseColor = const Color(0xFF29B6F6); icon = Icons.ac_unit; label = 'Raffrescamento'; break;
          default: baseColor = const Color(0xFF90A4AE); icon = Icons.power_settings_new; label = 'Spenta';
        }
        return _buildDropdownTile(
          color: _cardColor(context, baseColor),
          icon: icon,
          emoji: label == 'Raffrescamento' ? '\u2744\uFE0F' : label == 'Riscaldamento' ? '\uD83D\uDD25' : '\u26D4',
          subtitle: 'Comfort Home',
          notifier: widget.heatpumpModeNotifier,
          items: const [
            DropdownMenuItem(value: 'riscaldamento', child: Text('\uD83D\uDD25 Riscaldamento')),
            DropdownMenuItem(value: 'raffrescamento', child: Text('\u2744\uFE0F Raffrescamento')),
            DropdownMenuItem(value: 'spenta', child: Text('\u26D4 Spenta')),
          ],
        );
      },
    );
  }

  Widget _buildBoilerModeTile() {
    return ValueListenableBuilder<String>(
      valueListenable: widget.boilerModeNotifier,
      builder: (context, mode, _) {
        Color baseColor;
        IconData icon;
        String emoji;
        switch (mode) {
          case 'accesa': baseColor = const Color(0xFFE53935); icon = Icons.local_fire_department; emoji = '\uD83D\uDD25'; break;
          case 'standby': baseColor = const Color(0xFFFFB300); icon = Icons.pause_circle_outline; emoji = '\u23F8'; break;
          default: baseColor = const Color(0xFF78909C); icon = Icons.power_settings_new; emoji = '\u26D4';
        }
        return _buildDropdownTile(
          color: _cardColor(context, baseColor),
          icon: icon,
          emoji: emoji,
          subtitle: 'Cozytouch',
          notifier: widget.boilerModeNotifier,
          items: const [
            DropdownMenuItem(value: 'accesa', child: Text('\uD83D\uDD25 Accesa')),
            DropdownMenuItem(value: 'standby', child: Text('\u23F8 Standby')),
            DropdownMenuItem(value: 'spenta', child: Text('\u26D4 Spenta')),
          ],
        );
      },
    );
  }

  Widget _buildDropdownTile({
    required Color color,
    required IconData icon,
    required String emoji,
    required String subtitle,
    required ValueNotifier<String> notifier,
    required List<DropdownMenuItem<String>> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 30, color: Colors.white),
              Text(emoji, style: const TextStyle(fontSize: 22)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 9, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: notifier.value,
                  isExpanded: true,
                  dropdownColor: color,
                  iconEnabledColor: Colors.white,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  items: items,
                  onChanged: (value) { if (value != null) notifier.value = value; },
                ),
              ),
            ],
          ),
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
        final double? val = double.tryParse(controller.text.replaceAll(',', '.'));
        final String displayVal = val != null ? val.toStringAsFixed(1) : '--';
        final Color effectiveColor = _cardColor(context, color);
        return GestureDetector(
          onTap: () => _openControlPage(title, controller, suffix == 'kWh', isRoom, color),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: effectiveColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: effectiveColor.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
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
                          Text(displayVal, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, height: 1.0)),
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 2),
                            child: Text(suffix, style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
                          ),
                        ],
                      )
                    else
                      const SizedBox(),
                    if (isWeatherTile)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isLoadingWeather ? null : () => _fetchWeather(silent: false),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: _isLoadingWeather
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Icon(Icons.cloud_sync, size: 28, color: Colors.white.withValues(alpha: 0.8)),
                          ),
                        ),
                      )
                    else if (!isRoom && val == null)
                      Align(
                        alignment: Alignment.topRight,
                        child: Icon(icon ?? Icons.help_outline, size: 36, color: Colors.white.withValues(alpha: 0.3)),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 9, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 1),
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openControlPage(String title, TextEditingController controller, bool isConsumption, bool isRoom, Color cardColor) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isTablet = shortestSide >= 550;
    final roomPage = RoomControlPage(
      title: title,
      controller: controller,
      isConsumption: isConsumption,
      isRoom: isRoom,
      comfortRatings: widget.comfortRatings,
      onSave: () => setState(() {}),
      isCooling: widget.isCooling,
      cardColor: cardColor,
    );
    if (isTablet) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(width: 450, height: MediaQuery.of(context).size.height * 0.98, child: roomPage),
          ),
        ),
      );
    } else if (_isDesktop) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => roomPage));
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => roomPage,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeOutQuint));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        ),
      );
    }
  }
}
