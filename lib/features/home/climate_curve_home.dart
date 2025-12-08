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
import '../../models/daily_record_dto.dart';
import '../../services/hive_storage.dart';
import '../../services/notification_service.dart'; // IMPORT FONDAMENTALE PER NOTIFICHE
import 'logic/curve_logic.dart';
import 'utils/export_utils.dart';
import 'widgets/input_page.dart';
import 'widgets/results_page.dart';
import 'widgets/help_page.dart';
import '../../services/notification_service.dart';


class ClimateCurveOfflineHome extends StatefulWidget {
  final double initialSlope;
  final double initialOffset;

  const ClimateCurveOfflineHome({
    super.key,
    required this.initialSlope,
    required this.initialOffset,
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
  final Map<String, String> _comfortRatings = {};

  List<DailyRecordDTO> _records = [];
  late double slope;
  late double offset;
  SystemMode _currentMode = SystemMode.heating;

  // Cache per switch rapido
  double _cachedHeatingSlope = 1.2;
  double _cachedHeatingOffset = 0.0;
  double _cachedCoolingSlope = 0.5;
  double _cachedCoolingOffset = 0.0;

  int _currentPage = 0;
  int? _editingIndex;
  final GlobalKey _chartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPage);
    slope = widget.initialSlope;
    offset = widget.initialOffset;

    for (final room in ['Soggiorno/Cucina', 'Bagno PT', 'Cameretta Stefano', 'Camera Giochi', 'Camera Mamma e Papà', 'Bagno 1P']) {
      _internalTempControllers[room] = TextEditingController();
      _comfortRatings[room] = 'ok';
    }

    _loadFromHive();
  }

  Future<void> _setNotificationTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
    );
    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      final timeString = '$hh:$mm';

      await AppStorage.saveNotificationTime(timeString);
      await NotificationService.cancelAll();
      await NotificationService.scheduleDailyReminder();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Notifica impostata alle $timeString'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    ]);

    final storedRecords = results[0] as List<DailyRecordDTO>;
    final modeStr = results[1] as String;
    _cachedHeatingSlope = results[2] as double;
    _cachedHeatingOffset = results[3] as double;
    _cachedCoolingSlope = results[4] as double;
    _cachedCoolingOffset = results[5] as double;

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
      _updateSystemOverlay();
    }
  }

  Future<void> _saveToHive() async {
    await AppStorage.saveRecords(_records);
  }

  void _updateSystemOverlay() {
    final double opacity = 0.5;
    final Color color = _currentMode == SystemMode.heating
        ? Colors.orange.shade900.withOpacity(opacity)
        : Colors.lightBlue.shade800.withOpacity(opacity);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: color,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  void _toggleMode(bool value) {
    final newMode = value ? SystemMode.cooling : SystemMode.heating;
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

  String _formatItalianDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  void _clearFields({bool preFillFromLast = false}) {
    _editingIndex = null;
    _externalTempController.clear();
    _consumptionController.clear();
    _noteController.clear();
    _internalTempControllers.forEach((_, c) => c.clear());

    if (preFillFromLast && _records.isNotEmpty) {
      final DailyRecordDTO last = _records.last;
      _comfortRatings..clear()..addAll(last.comfortRatings.cast<String, String>());
    } else {
      _comfortRatings.updateAll((key, value) => 'ok');
    }
  }

  void _startEditRecord(int index) {
    if (index < 0 || index >= _records.length) return;

    final DailyRecordDTO r = _records[index];
    _editingIndex = index;
    _externalTempController.text = r.externalTemp.toString();
    _consumptionController.text = r.consumption.toString();
    _noteController.text = r.note;

    r.internalTemps.forEach((room, value) {
      if (_internalTempControllers.containsKey(room)) {
        _internalTempControllers[room]!.text = (value as num).toStringAsFixed(1);
      }
    });

    _comfortRatings..clear()..addAll(r.comfortRatings.cast<String, String>());

    setState(() {
      _currentPage = 0;
    });
    _pageController.jumpToPage(0);
  }

  void _addRecord() {
    final String dateText = _formatItalianDate(DateTime.now());

    if (_editingIndex == null) {
      final bool alreadyExists = _records.any((r) => r.dateIso == dateText);
      if (alreadyExists) {
        showDialog(context: context, builder: (ctx) {
          return AlertDialog(
              title: const Text('Dati già presenti'),
              content: Text('Hai già inserito dei dati per oggi ($dateText).\nModifica quelli esistenti nello storico.'),
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))]
          );
        });
        return;
      }
    }

    final Map<String, double> internalTemps = _internalTempControllers.map((key, controller) {
      return MapEntry(key, double.tryParse(controller.text) ?? 0);
    });

    final DailyRecordDTO record = DailyRecordDTO(
      dateIso: _editingIndex != null ? _records[_editingIndex!].dateIso : dateText,
      externalTemp: double.tryParse(_externalTempController.text) ?? 0,
      internalTemps: internalTemps,
      consumption: double.tryParse(_consumptionController.text) ?? 0,
      comfortRatings: Map<String, String>.from(_comfortRatings),
      note: _noteController.text.trim(),
    );

    setState(() {
      if (_editingIndex != null) {
        _records[_editingIndex!] = record;
      } else {
        _records.add(record);
      }
      _clearFields(preFillFromLast: true);
    });

    _saveToHive();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dati salvati con successo!'), behavior: SnackBarBehavior.floating));
  }

  void _deleteRecord(int index) {
    if (index < 0 || index >= _records.length) return;
    setState(() {
      _records.removeAt(index);
      if (_editingIndex == index) _clearFields();
    });
    _saveToHive();
  }

  void _duplicateFromYesterday() {
    if (_records.isEmpty) return;
    final DailyRecordDTO last = _records.last;
    _externalTempController.text = last.externalTemp.toStringAsFixed(1);
    _consumptionController.text = last.consumption.toStringAsFixed(1);
    _noteController.text = last.note;

    last.internalTemps.forEach((room, value) {
      if (_internalTempControllers.containsKey(room)) {
        _internalTempControllers[room]!.text = (value as num).toStringAsFixed(1);
      }
    });

    _comfortRatings..clear()..addAll(last.comfortRatings.cast<String, String>());
    setState(() {
      _editingIndex = null;
      _currentPage = 0;
    });
    _pageController.jumpToPage(0);
  }

  void _deleteToday() {
    final String today = _formatItalianDate(DateTime.now());
    final int index = _records.indexWhere((r) => r.dateIso == today);
    if (index != -1) _deleteRecord(index);
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  void _onNavDestinationSelected(int index) {
    setState(() {
      _currentPage = index;
    });
    _pageController.jumpToPage(index);
  }

  // === EXPORT CSV ===
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
      // Salva dove vuoi via Share
      await ExportUtils.shareCsv(csv, 'ClimaSense_${DateTime.now().toString().split(' ')[0]}.csv');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore export: $e")));
      }
    }
  }

  // === EXPORT PDF ===
  Future<void> _exportPdf() async {
    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nessun dato da esportare!")));
      return;
    }

    final int originalPage = _currentPage;
    if (_currentPage != 2) {
      setState(() => _currentPage = 2);
      _pageController.jumpToPage(2);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Preparazione Grafico..."), duration: Duration(milliseconds: 800))
      );
      await Future.delayed(const Duration(milliseconds: 800));
    }

    try {
      final chartImage = await _captureChart();
      final finalImage = chartImage ?? await _captureChart();
      final suggestion = computeOptimalCurveSuggestion(_records, slope, offset, _currentMode);
      final stats = computeCurveStats(_records);

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

  // === BACKUP ===
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
      // Salva dove vuoi via Share
      await ExportUtils.shareBackupJson(backupJson, 'ClimaSense_Backup_$date');

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante il backup: $e')));
      }
    }
  }

  Future<void> _doRestore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nessun file selezionato.')));
        return;
      }

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final backupData = jsonDecode(jsonString);

      if (backupData['metadata'] == null ||
          backupData['metadata']['appName'] != 'ClimaSense' ||
          backupData['settings'] == null ||
          backupData['records'] == null) {
        throw Exception("File di backup non valido o corrotto.");
      }

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Conferma Ripristino"),
          content: const Text("Sei sicuro di voler ripristinare i dati? L'operazione è irreversibile e sovrascriverà tutti i dati attuali."),
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
      final newRecords = recordsData.map((jsonData) => DailyRecordDTO.fromJson(jsonData)).toList();

      await AppStorage.saveRecords(newRecords);
      await AppStorage.saveSystemMode(settings['systemMode']);
      await AppStorage.saveSlope((settings['heatingSlope'] as num).toDouble());
      await AppStorage.saveOffset((settings['heatingOffset'] as num).toDouble());
      await AppStorage.saveCoolingSlope((settings['coolingSlope'] as num).toDouble());
      await AppStorage.saveCoolingOffset((settings['coolingOffset'] as num).toDouble());

      await _loadFromHive();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dati ripristinati con successo!')));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante il ripristino: $e')));
      }
    }
  }

  Widget _buildCurvePage(BuildContext context) {
    final suggestion = computeOptimalCurveSuggestion(_records, slope, offset, _currentMode);
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
        step: 1
    );

    List<FlSpot>? suggestedSpots;
    if (!suggestion.isLearning) {
      suggestedSpots = buildCurveSpots(
          slope: suggestion.suggestedSlope,
          offset: suggestion.suggestedOffset,
          mode: _currentMode,
          minExternalTemp: minExt,
          maxExternalTemp: maxExt,
          step: 1
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                              handleBuiltInTouches: true,
                              touchTooltipData: LineTouchTooltipData(
                                tooltipBgColor: Colors.blueGrey.shade800,
                                getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                                  return touchedBarSpots.map((barSpot) {
                                    return LineTooltipItem('Est: ${barSpot.x.toInt()}°C \nMandata: ${barSpot.y.toStringAsFixed(1)}°C', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12));
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
                              getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
                              getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                axisNameWidget: const Text("Temp. Mandata Acqua (°C)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                axisNameSize: 20,
                                sideTitles: SideTitles(showTitles: true, reservedSize: 35, interval: 5, getTitlesWidget: (value, meta) => Text('${value.toInt()}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
                              ),
                              bottomTitles: AxisTitles(
                                axisNameWidget: const Text("Temp. Esterna (°C)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                axisNameSize: 20,
                                sideTitles: SideTitles(showTitles: true, interval: 5, getTitlesWidget: (value, meta) => Padding(padding: const EdgeInsets.only(top: 6.0), child: Text('${value.toInt()}', style: const TextStyle(fontSize: 11, color: Colors.grey)))),
                              ),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                            lineBarsData: [
                              LineChartBarData(
                                spots: currentSpots, isCurved: true, color: Colors.blue.shade700, barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.05)),
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
                          Expanded(
                            child: Text(isHeating ? "Zona Rossa (<35°C): Efficienza ridotta per Ventilconvettori." : "Zona Rossa (<15°C): Alto rischio condensa sui pavimenti.", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                          ),
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
        if (isDashed) Row(children: [Container(width: 6, height: 3, color: color), const SizedBox(width: 2), Container(width: 6, height: 3, color: color)]) else Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = computeOptimalCurveSuggestion(_records, slope, offset, _currentMode);
    final stats = computeCurveStats(_records);
    final bool isCooling = _currentMode == SystemMode.cooling;
    final double opacity = 0.5;
    final Color targetColor = isCooling ? Colors.lightBlue.shade800.withOpacity(opacity) : Colors.orange.shade900.withOpacity(opacity);

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
            if (_currentMode == SystemMode.heating) {
              _cachedHeatingSlope = slope;
              _cachedHeatingOffset = offset;
              AppStorage.saveSlope(slope);
              AppStorage.saveOffset(offset);
            } else {
              _cachedCoolingSlope = slope;
              _cachedCoolingOffset = offset;
              AppStorage.saveCoolingSlope(slope);
              AppStorage.saveCoolingOffset(offset);
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nuova curva applicata e salvata!')));
        },
        onEditRecord: _startEditRecord,
        onDeleteRecord: _deleteRecord,
      ),
      _buildCurvePage(context),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: targetColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: Container(color: Colors.transparent))),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34, height: 34, margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))]),
              padding: const EdgeInsets.all(2),
              child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Icon(Icons.thermostat_rounded, color: targetColor, size: 20))),
            ),
            Text(isCooling ? 'ClimaSense Estate' : 'ClimaSense Inverno', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
        actions: [
          Row(children: [
            Icon(isCooling ? Icons.ac_unit : Icons.local_fire_department, size: 18, color: Colors.white70),
            Switch(value: isCooling, activeColor: Colors.white, activeTrackColor: Colors.white24, inactiveThumbColor: Colors.white70, inactiveTrackColor: Colors.white10, trackOutlineColor: MaterialStateProperty.all(Colors.transparent), onChanged: (val) => _toggleMode(val)),
          ]),

          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Opzioni',
            onSelected: (value) async {
              if (value == 'csv') {
                _exportCsv();
              } else if (value == 'pdf') {
                _exportPdf();
              } else if (value == 'help') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HelpPage()),
                );
              } else if (value == 'backup') {
                _doBackup();
              } else if (value == 'restore') {
                _doRestore();
              } else if (value == 'notif_time') {
                await _setNotificationTime();
              }
            },

            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[

              const PopupMenuItem(
                value: 'notif_time',
                child: Row(
                  children: [
                    Icon(Icons.alarm, size: 20, color: Colors.deepOrange),
                    SizedBox(width: 12),
                    Text('Orario Notifica'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'help', child: Row(children: [Icon(Icons.help_outline_rounded, size: 20, color: Colors.blueGrey), SizedBox(width: 12), Text('Guida Utente')])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf_rounded, size: 20, color: Colors.red), SizedBox(width: 12), Text('Report PDF')])),
              const PopupMenuItem(value: 'csv', child: Row(children: [Icon(Icons.table_chart_rounded, size: 20, color: Colors.green), SizedBox(width: 12), Text('Esporta CSV')])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'backup', child: Row(children: [Icon(Icons.backup_rounded, size: 20, color: Colors.blueAccent), SizedBox(width: 12), Text('Esegui Backup')])),
              const PopupMenuItem(value: 'restore', child: Row(children: [Icon(Icons.restore_page_rounded, size: 20, color: Colors.orangeAccent), SizedBox(width: 12), Text('Ripristina da Backup')])),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: isCooling ? [Colors.lightBlue.shade50, Colors.white] : [const Color(0xFFFFF3E0), Colors.white])),
        child: SafeArea(child: PageView(controller: _pageController, onPageChanged: _onPageChanged, children: pages)),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentPage,
        onDestinationSelected: _onNavDestinationSelected,
        backgroundColor: Colors.white.withOpacity(0.9),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.edit_calendar_rounded), label: 'Registra'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_rounded), label: 'AI & Storico'),
          NavigationDestination(icon: Icon(Icons.show_chart_rounded), label: 'Grafico'),
        ],
      ),
    );
  }
}
