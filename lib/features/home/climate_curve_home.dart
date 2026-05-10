// lib/features/home/climate_curve_home.dart
//
// Refactor #9 — decomposizione ClimateCurveOfflineHome:
//   • ClimateCurveOfflineHome  — solo provider setup (invariato per i consumer)
//   • _ClimateCurveHomeView    — Scaffold orchestratore snello
//   • _HomeAppBar              — switch modalità + icona notifiche
//   • _HomeNavBar              — bottom nav con _TabItem
//   • _HomePageView            — PageView + costruzione lista pagine
//
// Firma pubblica invariata.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../initial_settings/initial_settings_home.dart';
import 'home_notifier.dart';
import 'logic/curve_logic.dart';
import '../../services/hive_storage.dart';

import 'widgets/input_page.dart';
import 'widgets/results_page.dart';
import 'widgets/help_page.dart';
import 'widgets/curve_chart_page.dart';
import 'widgets/energy_page.dart';

// ============================================================================
// Entry point — invariato
// ============================================================================

class ClimateCurveOfflineHome extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeNotifier(
        initialSlope: initialSlope,
        initialOffset: initialOffset,
        initialPage: initialPage,
      ),
      child: const _ClimateCurveHomeView(),
    );
  }
}

// ============================================================================
// Scaffold orchestratore
// ============================================================================

class _ClimateCurveHomeView extends StatelessWidget {
  const _ClimateCurveHomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const _HomeNavBar(),
      body: SafeArea(
        child: Column(
          children: const [
            _HomeAppBar(),
            Expanded(child: _HomePageView()),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// App bar: switch riscaldamento/raffrescamento + notifiche
// ============================================================================

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notifier = context.watch<HomeNotifier>();
    final isCooling = notifier.currentMode == SystemMode.cooling;

    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8, left: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isCooling ? 'Raffrescamento' : 'Riscaldamento',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Cambia modalità',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Switch(
            value: isCooling,
            onChanged: notifier.toggleMode,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            splashRadius: 18,
            activeThumbColor: const Color(0xFF4DB6AC),
            activeTrackColor: const Color(0xFF4DB6AC),
            inactiveThumbColor: const Color(0xFFFFB74D),
            inactiveTrackColor: const Color(0xFFFFB74D),
            trackOutlineColor:
                WidgetStateProperty.all(Colors.transparent),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => notifier.setNotificationTime(context),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PageView + costruzione lista pagine
// ============================================================================

class _HomePageView extends StatelessWidget {
  const _HomePageView();

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<HomeNotifier>();
    final windowRecords =
        notifier.recordsSinceLastApply(notifier.currentMode);
    final suggestion = computeOptimalCurveSuggestion(
      windowRecords,
      notifier.slope,
      notifier.offset,
      notifier.currentMode,
    );
    final stats = computeCurveStats(windowRecords);
    final isCooling = notifier.currentMode == SystemMode.cooling;

    final pages = <Widget>[
      InputPage(
        externalTempController: notifier.externalTempController,
        consumptionController: notifier.consumptionController,
        consumptionAcsController: notifier.consumptionAcsController,
        energyFromGridController: notifier.energyFromGridController,
        pvProductionController: notifier.pvProductionController,
        noteController: notifier.noteController,
        heatpumpModeNotifier: notifier.heatpumpModeNotifier,
        boilerModeNotifier: notifier.boilerModeNotifier,
        internalTempControllers: notifier.internalTempControllers,
        comfortRatings: notifier.comfortRatings,
        records: notifier.records,
        rooms: notifier.rooms,
        onAddRecord: () => notifier.addRecord(context),
        isEditing: notifier.editingIndex != null,
        isCooling: isCooling,
        onDuplicateFromYesterday: () =>
            notifier.duplicateFromYesterday(context),
        onExportCsv: () => notifier.exportCsv(context),
        onExportPdf: () => notifier.exportPdf(context),
        onDeleteToday: () => notifier.deleteToday(context),
      ),
      ResultsPage(
        records: notifier.records,
        slope: notifier.slope,
        offset: notifier.offset,
        suggestion: suggestion,
        stats: stats,
        onApplyAiCurve: () => notifier.onApplyAiCurve(context),
        onEditRecordByDateIso: notifier.startEditRecordByDateIso,
        onDeleteRecordByDateIso: notifier.deleteRecordByDateIso,
        aiHistory: notifier.aiHistory,
        onUndoAiApply: notifier.undoLastAiApply,
      ),
      CurveChartPage(
        slope: notifier.slope,
        offset: notifier.offset,
        mode: notifier.currentMode,
        windowRecords: windowRecords,
        allRecords: notifier.allRecords,
        chartKey: notifier.chartKey,
      ),
      EnergyPage(records: notifier.records),
      HelpPage(
        onManageRooms: () => notifier.manageRooms(context),
        onResetCalibration: () => _confirmReset(context),
        onBackup: () => notifier.doBackup(context),
        onRestore: () => notifier.doRestore(context),
        onExportCsv: () => notifier.exportCsv(context),
        onExportPdf: () => notifier.exportPdf(context),
      ),
    ];

    return PageView(
      controller: notifier.pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: notifier.onPageChanged,
      children: pages,
    );
  }

  // --------------------------------------------------------------------------
  // Dialog reset calibrazione — estratto dal builder inline
  // --------------------------------------------------------------------------

  Future<void> _confirmReset(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Calibrazione?'),
        content: const Text(
          'Questo cancellerà le preferenze di pendenza/offset. '
          'I dati storici rimarranno.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESET',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;
    await AppStorage.resetCalibration();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (ctx) => const InitialSettingsHome()),
        (route) => false,
      );
    }
  }
}

// ============================================================================
// Bottom navigation bar
// ============================================================================

class _HomeNavBar extends StatelessWidget {
  const _HomeNavBar();

  static const _items = [
    (index: 0, icon: Icons.edit_calendar_outlined,  label: 'Registra'),
    (index: 1, icon: Icons.auto_awesome_outlined,   label: 'AI Storico'),
    (index: 2, icon: Icons.show_chart_rounded,      label: 'Grafico'),
    (index: 3, icon: Icons.bolt_outlined,           label: 'Energia'),
    (index: 4, icon: Icons.help_outline_rounded,    label: 'Guida'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notifier = context.watch<HomeNotifier>();

    return Container(
      color: cs.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in _items)
            _TabItem(
              index: item.index,
              icon: item.icon,
              label: item.label,
              currentPage: notifier.currentPage,
              onTap: notifier.onNavDestinationSelected,
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Tab item
// ============================================================================

class _TabItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final int currentPage;
  final void Function(int) onTap;

  const _TabItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.currentPage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = currentPage == index;
    final color = isSelected ? cs.primary : cs.onSurfaceVariant;

    return InkWell(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected
              ? cs.primary.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
