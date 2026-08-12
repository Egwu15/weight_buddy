import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/log_entry.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/periods.dart';
import '../record/record_sheet.dart';
import '../weigh/weight_card.dart';
import '../weigh/weight_history_screen.dart';
import '../widgets/days_wave.dart';
import '../widgets/ledger_card.dart';
import '../widgets/macro_plate.dart';
import '../widgets/record_dock.dart';
import '../widgets/timeline_tile.dart';

/// The single screen that does the job: today, at a glance, with the mic
/// a thumb away.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({
    super.key,
    required this.onOpenSettings,
    required this.onOpenMonth,
  });

  final VoidCallback onOpenSettings;

  /// Called when the period glance (week / month left) is tapped so the shell
  /// can jump to the Month tab for the full period view.
  final VoidCallback onOpenMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final logsAsync = ref.watch(dayLogsProvider);
    final totals = ref.watch(dayTotalsProvider);
    final maintenance =
        ref.watch(appSettingsProvider).value?.maintenanceKcal ?? 2200;
    final logs = logsAsync.value ?? const <LogEntry>[];
    final weekAsync = ref.watch(weekTotalsProvider(startOfWeek(day)));
    final monthAsync = ref.watch(monthPeriodTotalsProvider(day));

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    Text('weightbuddy',
                        style: AppText.label(color: AppColors.jollof)),
                    const Spacer(),
                    IconButton(
                      onPressed: onOpenSettings,
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_outlined,
                          color: AppColors.smoke, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _DateStrip(
                day: day,
                onPrevious: () => ref
                    .read(selectedDayProvider.notifier)
                    .setDay(day.subtract(const Duration(days: 1))),
                onNext: () => ref
                    .read(selectedDayProvider.notifier)
                    .setDay(day.add(const Duration(days: 1))),
              ),
            ),
            if (logsAsync.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DaysWave(entries: logs, totals: totals),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                    child: LedgerCard(
                  totals: totals,
                  maintenanceKcal: maintenance,
                )),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: _PeriodGlance(
                    week: weekAsync.value,
                    month: monthAsync.value,
                    onTap: onOpenMonth,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverToBoxAdapter(child: MacroPlate(totals: totals)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverToBoxAdapter(
                  child: WeightCard(
                    onOpenHistory: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WeightHistoryScreen(),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Text('Timeline', style: AppText.label()),
                ),
              ),
              if (logs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: _EmptyTimeline(
                      onLog: () => _openRecorder(context, ref),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  sliver: SliverList.separated(
                    itemCount: logs.length,
                    itemBuilder: (context, i) => TimelineTile(
                      entry: logs[i],
                      onDelete: () => _confirmDelete(context, ref, logs[i]),
                    ),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                  ),
                ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: RecordDock(onPressed: () => _openRecorder(context, ref)),
      ),
    );
  }

  Future<void> _openRecorder(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const RecordSheet(),
    );
    if (!context.mounted) return;
    switch (result) {
      case kRecordSheetLogged:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged')),
        );
      case kRecordSheetGoToSettings:
        // The record sheet asked for the key; jump to the Settings tab.
        onOpenSettings();
      case _:
        break;
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, LogEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bark,
        title: const Text('Delete this entry?'),
        content: Text('“${entry.summary}” will be removed from this day.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.chili,
              foregroundColor: AppColors.pot,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(dayLogsProvider.notifier).delete(entry);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleted')),
    );
  }
}

class _DateStrip extends ConsumerWidget {
  const _DateStrip({
    required this.day,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime day;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = day == DateTime.now().dateOnly;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrevious,
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left_rounded,
                color: AppColors.smoke, size: 28),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              Formatters.dayHeader(day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.title(),
            ),
          ),
          const SizedBox(width: 8),
          if (!isToday)
            TextButton(
              onPressed: () => ref
                  .read(selectedDayProvider.notifier)
                  .setDay(DateTime.now()),
              child: const Text('Today'),
            ),
          IconButton(
            onPressed: onNext,
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right_rounded,
                color: AppColors.smoke, size: 28),
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.onLog});

  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.graphic_eq_rounded,
                color: AppColors.smoke, size: 28),
            const SizedBox(height: 10),
            Text('Nothing logged today', style: AppText.title()),
            const SizedBox(height: 4),
            Text(
              'Hold the mic and say what you ate — or type it.',
              textAlign: TextAlign.center,
              style: AppText.bodyMuted(),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onLog,
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: const Text('Log by voice'),
            ),
          ],
        ),
      ),
    );
  }
}

extension on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);
}

/// The week / month glance under the daily ledger: how many calories are left
/// in each period, tappable through to the Month tab for the full view.
class _PeriodGlance extends StatelessWidget {
  const _PeriodGlance({required this.week, required this.month, required this.onTap});

  final PeriodTotals? week;
  final PeriodTotals? month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: _GlanceCell(label: 'WEEK LEFT', left: week?.leftKcal),
              ),
              Container(
                width: 1,
                height: 36,
                color: AppColors.ember,
              ),
              Expanded(
                child: _GlanceCell(label: 'MONTH LEFT', left: month?.leftKcal),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.smoke, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlanceCell extends StatelessWidget {
  const _GlanceCell({required this.label, required this.left});

  final String label;
  final double? left;

  @override
  Widget build(BuildContext context) {
    final value = left;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppText.label(color: AppColors.smoke)),
        const SizedBox(height: 4),
        Text(
          value == null ? '–' : Formatters.kcal(value),
          style: AppText.dataM(
            color: value == null
                ? AppColors.smoke
                : (value >= 0 ? AppColors.ugu : AppColors.jollof),
          ),
        ),
        const SizedBox(height: 2),
        Text('kcal', style: AppText.label(color: AppColors.smoke)),
      ],
    );
  }
}

