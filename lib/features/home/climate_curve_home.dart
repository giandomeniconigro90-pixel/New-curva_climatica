// lib/features/home/climate_curve_home.dart

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';

// Modelli e Servizi
import '../../models/daily_record_dto.dart';
import '../../services/hive_storage.dart';
import '../../services/notification_service.dart';
import '../initial_settings/initial_settings_home.dart';

// Logica e Utils
import 'logic/curve_logic.dart';
import 'utils/export_utils.dart';

// Widget
import 'widgets/input_page.dart';
import 'widgets/results_page.dart';
import 'widgets/help_page.dart';

class ClimateCurveOfflineHome extends StatefulWidget {
  final double initialSlope;
  final double initialOffset;
  final int initialPage;

  const ClimateCurveOfflineHome({
    super.key,
    required this.initialSlope,
    required this.initialOffset,
    this.initialPage = 0,
  });

  @override
  State<ClimateCurveOfflineHome> createState() => _ClimateCurveOfflineHomeState();
}

class _ClimateCurveOfflineHomeState extends State<ClimateCurveOfflineHome> {
  late PageController _pageController;

  // Controllers
  final TextEditingController _externalTempController = TextEditingController();
  final TextEditingController _consumptionController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final Map<String, TextEditingController> _internalTempControllers = {};

  // State Data
  final Map<String, String> _comfortRatings = {};
  List<DailyRecordDTO> _records = [];
  late double slope;
  late double offset;
  SystemMode _currentMode = SystemMode.heating;

  double _cachedHeatingSlope = 1.2;
  double _cachedHeatingOffset = 0.0;
  double _cachedCoolingSlope = 0.5;
  double _cachedCoolingOffset = 0.0;

  DateTime? _lastAiApplyHeating;
  DateTime? _lastAiApplyCooling;

  int _currentPage = 0;
  int? _editingIndex;
  final GlobalKey _chartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: _currentPage);
    slope = widget.initialSlope;
    offset = widget.initialOffset;

    // Inizializza controller stanze
    for (final room in [
      'Soggiorno/Cucina', 'Bagno PT', 'Cameretta Stefano',
      'Camera Giochi', 'Camera Mamma e Papà', 'Bagno 1P'
    ]) {
      _internalTempControllers[room] = TextEditingController();
      _comfortRatings[room] = 'ok';
    }

    _loadFromHive();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _externalTempController.dispose();
    _consumptionController.dispose();
    _noteController.dispose();
    for (final c in _internalTempControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFromHive() async {
    final results = await Future.wait([
      AppStorage.loadRecords(),
      AppStorage.getSystemMode(),
      AppStorage.getSlope(),
      AppStorage.getOffset(),
      AppStorage.getCoolingSlope(),
      AppStorage.getCoolingOffset(),
      AppStorage.getLastAiApplyHeatingIso(),
      AppStorage.getLastAiApplyCoolingIso(),
    ]);

    final storedRecords = results[0] as List<DailyRecordDTO>;
    final modeStr = results[1] as String;
    _cachedHeatingSlope = results[2] as double;
    _cachedHeatingOffset = results[3] as double;
    _cachedCoolingSlope = results[4] as double;
    _cachedCoolingOffset = results[5] as double;

    final heatIso = results[6] as String?;
    final coolIso = results[7] as String?;

    _lastAiApplyHeating = heatIso != null ? DateTime.tryParse(heatIso) : null;
    _lastAiApplyCooling = coolIso != null ? DateTime.tryParse(coolIso) : null;

    // Fix legacy
    if (_cachedCoolingOffset >= 15.0) {
      _cachedCoolingOffset = 0.0;
      await AppStorage.saveCoolingOffset(0.0);
    }

    final loadedMode = modeStr == 'cooling' ? SystemMode.cooling : SystemMode.heating;

    if (mounted) {
      setState(() {
        _records = storedRecords;
        _currentMode = loadedMode;
        if (_currentMode == SystemMode.heating) {
          slope = _cachedHeatingSlope;
          offset = _cachedHeatingOffset;
        } else {
          slope = _cachedCoolingSlope;
          offset = _cachedCoolingOffset;
        }
      });
    }
    _updateSystemOverlay();
  }

  Future<void> _saveToHive() async {
    await AppStorage.saveRecords(_records);
  }

  void _updateSystemOverlay() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  void _toggleMode(bool value) {
    final newMode = value ? SystemMode.cooling : SystemMode.heating;

    // Salva i valori correnti nella cache prima di cambiare
    if (_currentMode == SystemMode.heating) {
      _cachedHeatingSlope = slope;
      _cachedHeatingOffset = offset;
    } else {
      _cachedCoolingSlope = slope;
      _cachedCoolingOffset = offset;
    }

    setState(() {
      _currentMode = newMode;
      if (newMode == SystemMode.heating) {
        slope = _cachedHeatingSlope;
        offset = _cachedHeatingOffset;
      } else {
        slope = _cachedCoolingSlope;
        offset = _cachedCoolingOffset;
      }
    });

    _updateSystemOverlay();

    Future.microtask(() async {
      await AppStorage.saveSystemMode(newMode == SystemMode.cooling ? 'cooling' : 'heating');
      if (newMode == SystemMode.heating) {
        await AppStorage.saveCoolingSlope(_cachedCoolingSlope);
        await AppStorage.saveCoolingOffset(_cachedCoolingOffset);
      } else {
        await AppStorage.saveSlope(_cachedHeatingSlope);
        await AppStorage.saveOffset(_cachedHeatingOffset);
      }
    });
  }

  // === HELPER DATE E FILTRI ===
  DateTime? _parseItalianDateSafe(String s) {
    final parts = s.split('/');
    if (parts.length != 3) return null;
    return DateTime(int.tryParse(parts[2])!, int.tryParse(parts[1])!, int.tryParse(parts[0])!);
  }

  List<DailyRecordDTO> _recordsSinceLastApply(SystemMode mode) {
    final last = mode == SystemMode.heating ? _lastAiApplyHeating : _lastAiApplyCooling;
    if (last == null) return List.from(_records);

    final lastDay = DateTime(last.year, last.month, last.day);
    return _records.where((r) {
      final d = _parseItalianDateSafe(r.dateIso);
      return d != null && d.isAfter(lastDay);
    }).toList();
  }

  String _formatItalianDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  // === GESTIONE INPUT (CRUD) ===
  void _clearFields({bool preFillFromLast = false}) {
    _editingIndex = null;
    _externalTempController.clear();
    _consumptionController.clear();
    _noteController.clear();
    _internalTempControllers.forEach((_, c) => c.clear());

    if (preFillFromLast && _records.isNotEmpty) {
      final last = _records.last;
      _comfortRatings..clear()..addAll(last.comfortRatings);
    } else {
      _comfortRatings.updateAll((k, v) => 'ok');
    }
  }

  void _startEditRecord(int index) {
    if (index < 0 || index >= _records.length) return;
    final r = _records[index];
    _editingIndex = index;

    _externalTempController.text = r.externalTemp.toString();
    _consumptionController.text = r.consumption.toString();
    _noteController.text = r.note;

    r.internalTemps.forEach((room, value) {
      if (_internalTempControllers.containsKey(room)) {
        _internalTempControllers[room]!.text = value.toStringAsFixed(1);
      }
    });

    _comfortRatings..clear()..addAll(r.comfortRatings);

    setState(() => _currentPage = 0);
    _pageController.jumpToPage(0);
  }

  Future<void> _addRecord() async {
    // Validazione base
    if (_externalTempController.text.isEmpty || _consumptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci almeno Temperatura Esterna e Consumo')),
      );
      return;
    }

    final double? extTemp = double.tryParse(_externalTempController.text.replaceAll(',', '.'));
    final double? cons = double.tryParse(_consumptionController.text.replaceAll(',', '.'));

    if (extTemp == null || cons == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valori numerici non validi')),
      );
      return;
    }

    // Costruzione mappa temperature interne
    final Map<String, double> internalTemps = {};
    _internalTempControllers.forEach((room, controller) {
      if (controller.text.isNotEmpty) {
        final val = double.tryParse(controller.text.replaceAll(',', '.'));
        if (val != null) internalTemps[room] = val;
      }
    });

    final now = DateTime.now();
    final dateIso = _formatItalianDate(now);

    // Se stiamo modificando
    if (_editingIndex != null) {
      final originalDate = _records[_editingIndex!].dateIso;
      final updatedRecord = DailyRecordDTO(
        dateIso: originalDate,
        externalTemp: extTemp,
        internalTemps: internalTemps,
        consumption: cons,
        comfortRatings: Map.from(_comfortRatings),
        note: _noteController.text,
      );

      setState(() {
        _records[_editingIndex!] = updatedRecord;
        _editingIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrazione aggiornata!')),
      );
    } else {
      // NUOVO RECORD
      final exists = _records.any((r) => r.dateIso == dateIso);
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esiste già una registrazione per oggi. Modifica quella esistente.')),
        );
        return;
      }

      final newRecord = DailyRecordDTO(
        dateIso: dateIso,
        externalTemp: extTemp,
        internalTemps: internalTemps,
        consumption: cons,
        comfortRatings: Map.from(_comfortRatings),
        note: _noteController.text,
      );

      setState(() {
        _records.add(newRecord);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrazione salvata!')),
      );
    }

    await _saveToHive();
    _clearFields();
    FocusScope.of(context).unfocus();
  }

  Future<void> _deleteRecord(int index) async {
    setState(() {
      _records.removeAt(index);
      if (_editingIndex == index) _editingIndex = null;
    });
    await _saveToHive();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrazione eliminata')),
      );
    }
  }

  Future<void> _deleteToday() async {
    final today = _formatItalianDate(DateTime.now());
    final index = _records.indexWhere((r) => r.dateIso == today);
    if (index != -1) {
      await _deleteRecord(index);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna registrazione trovata per oggi')),
      );
    }
  }

  void _duplicateFromYesterday() {
    if (_records.isEmpty) return;

    final sorted = List<DailyRecordDTO>.from(_records);
    sorted.sort((a, b) {
      final dA = _parseItalianDateSafe(a.dateIso) ?? DateTime(2000);
      final dB = _parseItalianDateSafe(b.dateIso) ?? DateTime(2000);
      return dB.compareTo(dA);
    });

    if (sorted.isEmpty) return;
    final last = sorted.first;

    last.internalTemps.forEach((room, val) {
      if (_internalTempControllers.containsKey(room)) {
        _internalTempControllers[room]!.text = val.toStringAsFixed(1);
      }
    });

    setState(() {
      _comfortRatings.clear();
      _comfortRatings.addAll(last.comfortRatings);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dati copiati dall\'ultima registrazione')),
    );
  }

  // Navigazione Tab
  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  void _onNavDestinationSelected(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // === EXPORT, BACKUP E NOTIFICHE ===
  Future<void> _exportCsv() async {
    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nessun dato da esportare!")));
      return;
    }

    try {
      final csv = ExportUtils.generateCsv(
        _records,
        slope: slope,
        offset: offset,
        mode: _currentMode,
      );
      await ExportUtils.shareCsv(
        csv,
        'ClimaSense_${DateTime.now().toIso8601String().split('T')[0]}.csv',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore export: $e")));
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nessun dato da esportare!")));
      return;
    }

    final int originalPage = _currentPage;
    // Forza renderizzazione grafico
    if (_currentPage != 2) {
      setState(() => _currentPage = 2);
      _pageController.jumpToPage(2);
      await Future.delayed(const Duration(milliseconds: 800));
    }

    try {
      final chartImage = await _captureChart();
      final finalImage = chartImage ?? await _captureChart(); // Retry

      final windowRecords = _recordsSinceLastApply(_currentMode);
      final suggestion = computeOptimalCurveSuggestion(windowRecords, slope, offset, _currentMode);
      final stats = computeCurveStats(windowRecords);

      await ExportUtils.generateAndSavePdf(
        records: _records,
        slope: slope,
        offset: offset,
        suggestion: suggestion,
        stats: stats,
        chartImage: finalImage,
        currentMode: _currentMode,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore export PDF: $e")));
      }
    } finally {
      if (mounted && originalPage != 2) {
        setState(() => _currentPage = originalPage);
        _pageController.jumpToPage(originalPage);
      }
    }
  }

  Future<Uint8List?> _captureChart() async {
    try {
      final RenderRepaintBoundary? boundary = _chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _doBackup() async {
    try {
      final backupJson = ExportUtils.generateBackupJson(
        records: _records,
        mode: _currentMode,
        heatingSlope: _cachedHeatingSlope,
        heatingOffset: _cachedHeatingOffset,
        coolingSlope: _cachedCoolingSlope,
        coolingOffset: _cachedCoolingOffset,
      );
      final date = DateTime.now().toIso8601String().split('T').first;
      await ExportUtils.shareBackupJson(backupJson, 'ClimaSense_Backup_$date');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore backup: $e')));
      }
    }
  }

  Future<void> _doRestore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final backupData = jsonDecode(jsonString);

      if (backupData['metadata'] == null || backupData['settings'] == null || backupData['records'] == null) {
        throw Exception("File di backup non valido.");
      }

      final bool? confirmed = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Conferma Ripristino"),
          content: const Text("Sovrascriverà tutti i dati attuali. Continuare?"),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Annulla")),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("CONFERMA", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      final settings = backupData['settings'];
      final recordsData = backupData['records'] as List;
      final newRecords = recordsData.map((j) => DailyRecordDTO.fromJson(j)).toList();

      await AppStorage.saveRecords(newRecords);
      await AppStorage.saveSystemMode(settings['systemMode']);
      await AppStorage.saveSlope((settings['heatingSlope'] as num).toDouble());
      await AppStorage.saveOffset((settings['heatingOffset'] as num).toDouble());
      await AppStorage.saveCoolingSlope((settings['coolingSlope'] as num).toDouble());
      await AppStorage.saveCoolingOffset((settings['coolingOffset'] as num).toDouble());

      await _loadFromHive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ripristino completato!')));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore ripristino: $e')));
      }
    }
  }

  Future<void> _setNotificationTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      await AppStorage.saveNotificationTime('$hh:$mm');
      await NotificationService.cancelAll();
      await NotificationService.scheduleDailyReminder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notifica impostata alle $hh:$mm')));
      }
    }
  }

  // === GRAFICO ===
  Widget _buildCurvePage(BuildContext context) {
    final windowRecords = _recordsSinceLastApply(_currentMode);
    final suggestion = computeOptimalCurveSuggestion(windowRecords, slope, offset, _currentMode);
    final isHeating = _currentMode == SystemMode.heating;

    double minExt = isHeating ? -10 : 20;
    double maxExt = isHeating ? 20 : 40;
    double minY = isHeating ? 25.0 : 5.0;
    double maxY = isHeating ? 65.0 : 25.0;
    final double unsafeZoneLimit = isHeating ? 35.0 : 15.0;

    final List<FlSpot> currentSpots = buildCurveSpots(
      slope: slope,
      offset: offset,
      mode: _currentMode,
      minExternalTemp: minExt,
      maxExternalTemp: maxExt,
      step: 1,
    );

    List<FlSpot>? suggestedSpots;
    if (!suggestion.isLearning) {
      suggestedSpots = buildCurveSpots(
        slope: suggestion.suggestedSlope,
        offset: suggestion.suggestedOffset,
        mode: _currentMode,
        minExternalTemp: minExt,
        maxExternalTemp: maxExt,
        step: 1,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              const SizedBox(height: 16),
              RepaintBoundary(
                key: _chartKey,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Curva Climatica', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                              Text(isHeating ? 'Inverno (Riscaldamento)' : 'Estate (Raffrescamento)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            ],
                          ),
                          Row(
                            children: [
                              _buildLegendItem('Attuale', Colors.blue.shade700, false),
                              if (suggestedSpots != null) ...[
                                const SizedBox(width: 16),
                                _buildLegendItem('AI Consigliata', Colors.green, true),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AspectRatio(
                        aspectRatio: 1.4,
                        child: LineChart(
                          LineChartData(
                            minX: minExt, maxX: maxExt, minY: minY, maxY: maxY,
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (touchedSpot) => Colors.blueGrey.shade800,
                                getTooltipItems: (touchedBarSpots) {
                                  return touchedBarSpots.map((barSpot) {
                                    return LineTooltipItem(
                                      'Est: ${barSpot.x.toInt()}°C \nMandata: ${barSpot.y.toStringAsFixed(1)}°C',
                                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            rangeAnnotations: RangeAnnotations(
                              horizontalRangeAnnotations: [
                                HorizontalRangeAnnotation(y1: minY, y2: unsafeZoneLimit, color: Colors.red.withOpacity(0.10)),
                              ],
                            ),
                            gridData: FlGridData(
                              show: true, drawVerticalLine: true, horizontalInterval: 5, verticalInterval: 5,
                              getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
                              getDrawingVerticalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                axisNameWidget: const Text("Temp. Mandata Acqua (°C)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                axisNameSize: 20,
                                sideTitles: SideTitles(showTitles: true, reservedSize: 35, interval: 5, getTitlesWidget: (val, _) => Text('${val.toInt()}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
                              ),
                              bottomTitles: AxisTitles(
                                axisNameWidget: const Text("Temp. Esterna (°C)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                axisNameSize: 20,
                                sideTitles: SideTitles(showTitles: true, interval: 5, getTitlesWidget: (val, _) => Padding(padding: const EdgeInsets.only(top: 6), child: Text('${val.toInt()}', style: const TextStyle(fontSize: 11, color: Colors.grey)))),
                              ),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                            lineBarsData: [
                              LineChartBarData(
                                spots: currentSpots, isCurved: true, color: Colors.blue.shade700, barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.05)),
                              ),
                              if (suggestedSpots != null)
                                LineChartBarData(
                                  spots: suggestedSpots, isCurved: true, color: Colors.green, barWidth: 3, dashArray: [6, 6], dotData: const FlDotData(show: false),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(width: 12, height: 12, color: Colors.red.withOpacity(0.1)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(isHeating ? "Zona Rossa (<35°C): Efficienza ridotta per Ventilconvettori." : "Zona Rossa (<15°C): Alto rischio condensa.", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String text, Color color, bool isDashed) {
    return Row(
      children: [
        if (isDashed)
          Row(children: [Container(width: 6, height: 3, color: color), const SizedBox(width: 2), Container(width: 6, height: 3, color: color)])
        else
          Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final windowRecords = _recordsSinceLastApply(_currentMode);
    final suggestion = computeOptimalCurveSuggestion(windowRecords, slope, offset, _currentMode);
    final stats = computeCurveStats(windowRecords);

    final bool isCooling = _currentMode == SystemMode.cooling;
    final double opacity = 0.5;
    final Color targetColor = isCooling ? Colors.lightBlue.shade800.withOpacity(opacity) : Colors.orange.shade900.withOpacity(opacity);
    final Color appBarColor = isCooling ? targetColor : Colors.orange.shade700.withOpacity(0.95);

    final List<Widget> pages = [
      InputPage(
        externalTempController: _externalTempController,
        consumptionController: _consumptionController,
        noteController: _noteController,
        internalTempControllers: _internalTempControllers,
        comfortRatings: _comfortRatings,
        records: _records,
        onAddRecord: _addRecord,
        onDeleteRecord: _deleteRecord,
        onEditRecord: _startEditRecord,
        isEditing: _editingIndex != null,
        onDuplicateFromYesterday: _duplicateFromYesterday,
        onExportCsv: _exportCsv,
        onExportPdf: _exportPdf,
        onDeleteToday: _deleteToday,
      ),
      ResultsPage(
        records: _records,
        slope: slope,
        offset: offset,
        suggestion: suggestion,
        stats: stats,
        onApplyAiCurve: () {
          setState(() {
            slope = suggestion.suggestedSlope;
            offset = suggestion.suggestedOffset;

            final now = DateTime.now();
            final nowIso = now.toIso8601String();

            if (_currentMode == SystemMode.heating) {
              _lastAiApplyHeating = now;
              AppStorage.saveLastAiApplyHeatingIso(nowIso);
              _cachedHeatingSlope = slope;
              _cachedHeatingOffset = offset;
            } else {
              _lastAiApplyCooling = now;
              AppStorage.saveLastAiApplyCoolingIso(nowIso);
              _cachedCoolingSlope = slope;
              _cachedCoolingOffset = offset;
            }
          });

          Future.microtask(() async {
            if (_currentMode == SystemMode.heating) {
              await AppStorage.saveSlope(slope);
              await AppStorage.saveOffset(offset);
            } else {
              await AppStorage.saveCoolingSlope(slope);
              await AppStorage.saveCoolingOffset(offset);
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nuova curva applicata!")));
        },
        onDeleteRecord: _deleteRecord,
        onEditRecord: _startEditRecord,
      ),
      _buildCurvePage(context),
      HelpPage(
        onResetCalibration: () async {
          final confirm = await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Reset Calibrazione?'),
              content: const Text("Questo cancellerà le preferenze di pendenza/offset. I dati storici rimarranno."),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('RESET', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await AppStorage.resetCalibration();
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (ctx) => const InitialSettingsHome()),
                    (route) => false,
              );
            }
          }
        },
        onBackup: _doBackup,
        onRestore: _doRestore,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClimaSense'),
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
        actions: [
          Switch(
            value: _currentMode == SystemMode.cooling,
            onChanged: _toggleMode,
            activeColor: Colors.blue.shade100,
            activeTrackColor: Colors.blue.shade900,
            inactiveThumbColor: Colors.orange.shade100,
            inactiveTrackColor: Colors.orange.shade900,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _setNotificationTime,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTabItem(0, Icons.edit_calendar_outlined, "Registra"),
                _buildTabItem(1, Icons.auto_awesome_outlined, "AI & Storico"),
                _buildTabItem(2, Icons.show_chart_rounded, "Grafico"),
                _buildTabItem(3, Icons.help_outline_rounded, "Guida"),
              ],
            ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: _onPageChanged,
        children: pages,
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final bool isSelected = _currentPage == index;
    return InkWell(
      onTap: () => _onNavDestinationSelected(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: isSelected ? Border(bottom: BorderSide(color: Colors.blue.shade900, width: 3)) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.blue.shade900 : Colors.grey.shade400, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSelected ? Colors.blue.shade900 : Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
