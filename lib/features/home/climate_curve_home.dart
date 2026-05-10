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

class _ClimateCurveHomeView extends StatelessWidget {
  const _ClimateCurveHomeView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<HomeNotifier>(
      builder: (context, notifier, _) {
        final DateTime? lastAppliedDate =
            notifier.currentMode == SystemMode.heating
                ? notifier.lastAiApplyHeating
                : notifier.lastAiApplyCooling;

        final suggestion = computeOptimalCurveSuggestion(
          notifier.records,
          notifier.slope,
          notifier.offset,
          notifier.currentMode,
          lastAppliedDate,
        );

        final windowRecords =
            notifier.recordsSinceLastApply(notifier.currentMode);
        final stats = computeCurveStats(windowRecords);

        final bool isCooling = notifier.currentMode == SystemMode.cooling;

        final List<Widget> pages = [
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
            onResetCalibration: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset Calibrazione?'),
                  content: const Text(
                    'Questo canceller\u00e0 le preferenze di pendenza/offset. I dati storici rimarranno.',
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

              if (confirm == true) {
                await AppStorage.resetCalibration();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (ctx) => const InitialSettingsHome()),
                    (route) => false,
                  );
                }
              }
            },
            onBackup: () => notifier.doBackup(context),
            onRestore: () => notifier.doRestore(context),
            onExportCsv: () => notifier.exportCsv(context),
            onExportPdf: () => notifier.exportPdf(context),
          ),
        ];

        return Scaffold(
          bottomNavigationBar: Container(
            color: cs.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TabItem(index: 0, icon: Icons.edit_calendar_outlined, label: 'Registra', currentPage: notifier.currentPage, onTap: notifier.onNavDestinationSelected),
                _TabItem(index: 1, icon: Icons.auto_awesome_outlined, label: 'AI Storico', currentPage: notifier.currentPage, onTap: notifier.onNavDestinationSelected),
                _TabItem(index: 2, icon: Icons.show_chart_rounded, label: 'Grafico', currentPage: notifier.currentPage, onTap: notifier.onNavDestinationSelected),
                _TabItem(index: 3, icon: Icons.bolt_outlined, label: 'Energia', currentPage: notifier.currentPage, onTap: notifier.onNavDestinationSelected),
                _TabItem(index: 4, icon: Icons.help_outline_rounded, label: 'Guida', currentPage: notifier.currentPage, onTap: notifier.onNavDestinationSelected),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8, left: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            notifier.currentMode == SystemMode.heating
                                ? 'Riscaldamento'
                                : 'Raffrescamento',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Cambia modalit\u00e0',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: notifier.currentMode == SystemMode.cooling,
                        onChanged: notifier.toggleMode,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        splashRadius: 18,
                        activeThumbColor: const Color(0xFF4DB6AC),
                        activeTrackColor: const Color(0xFF4DB6AC),
                        inactiveThumbColor: const Color(0xFFFFB74D),
                        inactiveTrackColor: const Color(0xFFFFB74D),
                        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () => notifier.setNotificationTime(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: notifier.pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: notifier.onPageChanged,
                    children: pages,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
    final bool isSelected = currentPage == index;
    final cs = Theme.of(context).colorScheme;
    final Color active = cs.primary;
    final Color inactive = cs.onSurfaceVariant;

    return InkWell(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? active.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? active : inactive, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? active : inactive,
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
