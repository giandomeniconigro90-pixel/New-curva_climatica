import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/daily_record_dto.dart';
import '../../services/hive_storage.dart'; // Usa la nuova versione completa
import 'widgets/input_page.dart';
import 'widgets/results_page.dart';
import 'new_thermostat_home.dart';
import 'widgets/help_page.dart';
import 'utils/export_utils.dart'; // Usa la nuova versione completa

class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  int _selectedIndex = 0;
  List<DailyRecordDTO> _records = [];

  // Controllers InputPage
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
    final data = AppStorage.getRecords(); // Metodo statico ora esiste
    setState(() {
      _records = data;
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
      // NON sovrascrivere i controller! Mantieni i dati importati
    } catch (e) {
      _isEditingToday = false;
      _todayDateIso = null;
      // NON chiamare _clearControllers()! Mantieni i dati importati
    }
  }


  void _populateForEdit(DailyRecordDTO record) {
    _externalTempController.text = record.externalTemp.toString();
    _consumptionController.text = record.consumption.toString();
    _noteController.text = record.note ?? "";
    record.internalTemps.forEach((room, temp) {
      if (_internalTempControllers.containsKey(room)) {
        _internalTempControllers[room]!.text = temp.toString();
      }
    });
    _comfortRatings.clear();
    _comfortRatings.addAll(Map.from(record.comfortRatings));

    _isEditingToday = true;
    _todayDateIso = record.dateIso;
    setState(() {});
  }


  void _populateControllers(DailyRecordDTO record) {
    _externalTempController.text = record.externalTemp.toString();
    _consumptionController.text = record.consumption.toString();
    _noteController.text = record.note ?? "";
    record.internalTemps.forEach((room, temp) {
      if (_internalTempControllers.containsKey(room)) {
        _internalTempControllers[room]!.text = temp.toString();
      }
    });
    _comfortRatings.clear();
    _comfortRatings.addAll(Map.from(record.comfortRatings));
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

  Future _saveRecord() async {
    // 1. Validazione Esterna e Consumo
    if (_externalTempController.text.isEmpty || _consumptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Errore: Temperatura esterna e Consumo sono obbligatori!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Validazione Stanze Interne (Tutte devono essere piene)
    for (var entry in _internalTempControllers.entries) {
      if (entry.value.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Errore: Manca la temperatura per ${entry.key}!"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // 3. Determinare la data da usare
    late String dateIsoToUse;

    // Se stai modificando il record di oggi, usa la sua data originale (_todayDateIso)
    if (_isEditingToday && _todayDateIso != null) {
      dateIsoToUse = _todayDateIso!;
    } else {
      // Controlla se esiste già un record per OGGI
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final existingToday = _records.cast<DailyRecordDTO?>().firstWhere(
            (r) => r != null && r.dateIso.startsWith(todayStr),
        orElse: () => null,
      );

      if (existingToday != null) {
        // Se c'è già un record per oggi, riusa la sua data (non crearne un'altra)
        dateIsoToUse = existingToday.dateIso;
      } else {
        // Altrimenti crea un nuovo timestamp per oggi
        dateIsoToUse = DateFormat('yyyy-MM-dd HH:mm').format(now);
      }
    }

    // 4. Creazione oggetto
    final newRecord = DailyRecordDTO(
      dateIso: dateIsoToUse,
      externalTemp: double.tryParse(_externalTempController.text.replaceAll(',', '.')) ?? 0.0,
      consumption: double.tryParse(_consumptionController.text.replaceAll(',', '.')) ?? 0.0,
      internalTemps: _internalTempControllers.map(
            (key, value) => MapEntry(key, double.tryParse(value.text.replaceAll(',', '.')) ?? 0.0),
      ),
      comfortRatings: Map.from(_comfortRatings),
      note: _noteController.text,
    );

    // 5. Salvataggio
    await AppStorage.saveRecord(newRecord);
    await _loadData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isEditingToday ? "Dati aggiornati!" : "Dati salvati!")),
    );
  }

  Future<void> _duplicateYesterday() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Funzione da implementare")));
  }

  Future<void> _deleteRecord(int index) async {
    await AppStorage.deleteRecord(_records[index].dateIso); // Metodo statico esiste
    await _loadData();
  }

  Future<void> _exportCsv() async {
    await ExportUtils.exportSimpleCsv(_records); // Metodo statico esiste
  }

  Future<void> _exportPdf() async {
    await ExportUtils.exportSimplePdf(_records); // Metodo statico esiste
  }

  @override
  Widget build(BuildContext context) {
    // Definizione Pagine
    final List<Widget> pages = [
      // 1. INPUT
      InputPage(
        externalTempController: _externalTempController,
        consumptionController: _consumptionController,
        noteController: _noteController,
        internalTempControllers: _internalTempControllers,
        comfortRatings: _comfortRatings,
        records: _records,
        onAddRecord: _saveRecord,
        onDeleteRecord: (index) => _deleteRecord(index),
        onEditRecord: (index) {
          _populateForEdit(_records[index]);
          setState(() {}); // Aggiorna il flag isEditing
        },
        isEditing: _isEditingToday,
        onDuplicateFromYesterday: _duplicateYesterday,
        onExportCsv: _exportCsv,
        onExportPdf: _exportPdf,
        onDeleteToday: () async {
          if (_todayDateIso != null) {
            await AppStorage.deleteRecord(_todayDateIso!);
            await _loadData();
          }
        },
      ),

      // 2. RESULTS (GRAFICO/TABELLA)
      // Assicurati che ResultsPage accetti solo 'records' nel costruttore
      ResultsPage(records: _records),

      // 3. AI / CONFIG
      const NewThermostatHome(),

      // 4. HELP
      const HelpPage(),
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
              icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.edit_calendar_outlined, size: 24)),
              activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.edit_calendar, size: 24)),
              label: 'Registra',
            ),
            BottomNavigationBarItem(
              icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.show_chart_rounded, size: 24)), // Scambiato icona per logica
              activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.show_chart_rounded, size: 24)),
              label: 'Storico',
            ),
            BottomNavigationBarItem(
              icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.auto_awesome_outlined, size: 24)), // Scambiato icona per AI
              activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.auto_awesome, size: 24)),
              label: 'AI & Curve',
            ),
            BottomNavigationBarItem(
              icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.help_outline_rounded, size: 24)),
              activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.help_rounded, size: 24)),
              label: 'Guida',
            ),
          ],
        ),
      ),
    );
  }
}
