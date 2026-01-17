// lib/features/home/dashboard_home.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/daily_record_dto.dart';
import '../../services/hive_storage.dart';
import '../initial_settings/initial_settings_home.dart';
import 'logic/curve_logic.dart';
import 'widgets/input_page.dart';
import 'widgets/results_page.dart';
import 'new_thermostat_home.dart';
import 'widgets/help_page.dart';
import 'utils/export_utils.dart';

class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  int _selectedIndex = 0;

  List<DailyRecordDTO> _records = [];
  double _currentSlope = 1.2;
  double _currentOffset = 0.0;
  SystemMode _currentMode = SystemMode.heating;

  final TextEditingController _externalTempController = TextEditingController();
  final TextEditingController _consumptionController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  final Map<String, TextEditingController> _internalTempControllers = {
    'Soggiorno/Cucina': TextEditingController(),
    'Bagno PT': TextEditingController(),
    'Cameretta Stefano': TextEditingController(),
    'Camera Giochi': TextEditingController(),
    'Camera Mamma e Papà': TextEditingController(),
    'Bagno 1P': TextEditingController(),
  };

  final Map<String, String> _comfortRatings = {};

  bool _isEditingToday = false;
  String? _todayDateIso;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await AppStorage.loadRecords();
    final slope = await AppStorage.getSlope();
    final offset = await AppStorage.getOffset();
    final modeStr = await AppStorage.getSystemMode();

    setState(() {
      _records = data;
      _currentSlope = slope;
      _currentOffset = offset;
      _currentMode = modeStr == 'cooling' ? SystemMode.cooling : SystemMode.heating;
    });

    _checkTodayRecord();
  }

  void _checkTodayRecord() {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    try {
      final todayRecord = _records.firstWhere((r) => r.dateIso.startsWith(todayStr));
      _isEditingToday = true;
      _todayDateIso = todayRecord.dateIso;
      _populateControllers(todayRecord);
    } catch (e) {
      _isEditingToday = false;
      _todayDateIso = null;
      _clearControllers();
    }
  }

  void _populateControllers(DailyRecordDTO record) {
    _externalTempController.text = record.externalTemp.toString();
    _consumptionController.text = record.consumption.toString();
    _noteController.text = record.note;

    record.internalTemps.forEach((room, temp) {
      if (_internalTempControllers.containsKey(room)) {
        _internalTempControllers[room]!.text = temp.toString();
      }
    });

    _comfortRatings.clear();
    _comfortRatings.addAll(Map<String, String>.from(record.comfortRatings));
  }

  void _clearControllers() {
    _externalTempController.clear();
    _consumptionController.clear();
    _noteController.clear();
    for (var c in _internalTempControllers.values) {
      c.clear();
    }
    _comfortRatings.clear();
  }

  Future<void> _saveRecord() async {
    if (_externalTempController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Inserisci almeno la temperatura esterna")),
      );
      return;
    }

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(now);

    final newRecord = DailyRecordDTO(
      dateIso: _isEditingToday && _todayDateIso != null ? _todayDateIso! : dateStr,
      externalTemp: double.tryParse(_externalTempController.text.replaceAll(',', '.')) ?? 0.0,
      consumption: double.tryParse(_consumptionController.text.replaceAll(',', '.')) ?? 0.0,
      internalTemps: _internalTempControllers.map((key, value) => MapEntry(key, double.tryParse(value.text.replaceAll(',', '.')) ?? 0.0)),
      comfortRatings: Map.from(_comfortRatings),
      note: _noteController.text,
    );

    List<DailyRecordDTO> updatedRecords = List.from(_records);
    if (_isEditingToday) {
      final idx = updatedRecords.indexWhere((r) => r.dateIso == _todayDateIso);
      if(idx != -1) updatedRecords[idx] = newRecord;
    } else {
      updatedRecords.add(newRecord);
    }

    await AppStorage.saveRecords(updatedRecords);
    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditingToday ? "Dati aggiornati!" : "Dati salvati!")),
      );
    }

    // Chiudi Modal
    if (Navigator.canPop(context)) {
      // Controllo generico per chiudere sempre se è un dialog
      Navigator.pop(context);
    }
  }

  Future<void> _duplicateYesterday() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Funzione da implementare")));
  }

  Future<void> _deleteRecord(int index) async {
    List<DailyRecordDTO> updatedRecords = List.from(_records);
    updatedRecords.removeAt(index);
    await AppStorage.saveRecords(updatedRecords);
    await _loadData();
  }

  Future<void> _exportCsv() async {
    final csvData = ExportUtils.generateCsv(
        _records,
        slope: _currentSlope,
        offset: _currentOffset,
        mode: _currentMode
    );
    await ExportUtils.shareCsv(csvData, "climasense_export.csv");
  }

  Future<void> _exportPdf() async {
    await ExportUtils.generateAndSavePdf(
        slope: _currentSlope,
        offset: _currentOffset,
        records: _records,
        chartImage: null,
        currentMode: _currentMode,
        stats: null,
        suggestion: null
    );
  }

  // --- HELPER: FORM ---
  Widget _buildInputForm() {
    return InputPage(
      externalTempController: _externalTempController,
      consumptionController: _consumptionController,
      noteController: _noteController,
      internalTempControllers: _internalTempControllers,
      comfortRatings: _comfortRatings,
      records: _records,
      onAddRecord: _saveRecord,
      onDeleteRecord: (index) => _deleteRecord(index),
      onEditRecord: (index) {},
      isEditing: _isEditingToday,
      onDuplicateFromYesterday: _duplicateYesterday,
      onExportCsv: _exportCsv,
      onExportPdf: _exportPdf,
      onDeleteToday: () async {
        if (_todayDateIso != null) {
          final idx = _records.indexWhere((r) => r.dateIso == _todayDateIso);
          if(idx != -1) await _deleteRecord(idx);
        }
      },
    );
  }

  // --- MODALE POP-UP ---
  // --- MODALE POP-UP ---
  void _openTabletInputModal(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24), // Margine esterno dal bordo schermo
        child: Container(
          width: 500, // Larghezza fissa
          // Vincoliamo l'altezza ma lasciamo che si adatti
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.95, // Più spazio verticale (95%)
          ),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Inserimento Dati",
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 28, color: Colors.black54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Body scrollabile
              // Usiamo Expanded per forzare il child a occupare lo spazio rimanente
              // e assicuriamoci che InputPage gestisca il suo scroll internamente
              Expanded(
                child: _buildInputForm(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- DASHBOARD TABLET ---
  Widget _buildTabletPlaceholder() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle
              ),
              child: Icon(Icons.edit_calendar_rounded, size: 56, color: Colors.blue.shade800),
            ),
            const SizedBox(height: 32),
            const Text(
              "Dashboard Clima",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Text(
              _isEditingToday
                  ? "Dati odierni registrati correttamente."
                  : "Nessun dato inserito per oggi.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_isEditingToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  "Esterna: ${_externalTempController.text}°C  •  Consumo: ${_consumptionController.text} kWh",
                  style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold),
                ),
              ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                icon: Icon(_isEditingToday ? Icons.edit_rounded : Icons.add_circle_outline_rounded),
                label: Text(
                  _isEditingToday ? "MODIFICA DATI" : "INSERISCI DATI",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _openTabletInputModal(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- LOGICA DI RILEVAMENTO TABLET AGGRESSIVA ---
    final size = MediaQuery.of(context).size;

    // Se il lato più corto dello schermo è >= 550 pixel logici, è un tablet.
    // Funziona per Tab S6 sia in verticale che in orizzontale.
    // Gli smartphone raramente superano i 430-450 di larghezza in portrait.
    final bool isTablet = size.shortestSide >= 550;

    final suggestion = computeOptimalCurveSuggestion(_records, _currentSlope, _currentOffset, _currentMode);
    final stats = computeCurveStats(_records);

    final List<Widget> pages = [
      // 1. INPUT PAGE
      isTablet
          ? _buildTabletPlaceholder()
          : _buildInputForm(),

      // 2. RESULTS PAGE
      ResultsPage(
        records: _records,
        slope: _currentSlope,
        offset: _currentOffset,
        suggestion: suggestion,
        stats: stats,
        onApplyAiCurve: () async {
          await AppStorage.saveSlope(suggestion.suggestedSlope);
          await AppStorage.saveOffset(suggestion.suggestedOffset);
          _loadData();
        },
        onDeleteRecord: (index) => _deleteRecord(index),
        onEditRecord: (index) {
          setState(() => _selectedIndex = 0);
          if (isTablet) {
            Future.delayed(const Duration(milliseconds: 150), () => _openTabletInputModal(context));
          }
        },
      ),

      const NewThermostatHome(),

      HelpPage(
        onBackup: () async {
          final json = ExportUtils.generateBackupJson(
              records: _records,
              mode: _currentMode,
              heatingSlope: _currentSlope,
              heatingOffset: _currentOffset,
              coolingSlope: 0.5,
              coolingOffset: 0.0
          );
          await ExportUtils.shareBackupJson(json, "climasense_backup");
        },
        onResetCalibration: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const InitialSettingsHome()));
        },
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: Colors.black87,
          unselectedItemColor: Colors.grey.shade400,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.2),
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.edit_calendar_outlined, size: 24),
              ),
              activeIcon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.edit_calendar, size: 24),
              ),
              label: 'Registra',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.auto_awesome_outlined, size: 24),
              ),
              activeIcon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.auto_awesome, size: 24),
              ),
              label: 'AI & Storico',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.show_chart_rounded, size: 24),
              ),
              activeIcon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.show_chart_rounded, size: 24),
              ),
              label: 'Grafico',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.help_outline_rounded, size: 24),
              ),
              activeIcon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.help_rounded, size: 24),
              ),
              label: 'Guida',
            ),
          ],
        ),
      ),
    );
  }
}
