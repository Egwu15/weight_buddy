import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/log_entry.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/period_ledger_card.dart';

/// The month at a glance: every day tinted by its balance against
/// maintenance, with logging and on-plan streaks up top.
class MonthScreen extends ConsumerWidget {
  const MonthScreen({super.key, required this.onSelectDay});

  /// Called with the tapped day so the shell can jump Today to it.
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final totalsAsync = ref.watch(monthTotalsProvider(month));
    final streaksAsync = ref.watch(streakProvider);
    final currentMaintenance =
        ref.watch(appSettingsProvider).value?.maintenanceKcal ?? 2200;
    final dayMaintenanceAsync = ref.watch(monthMaintenanceProvider(month));
    final dayMaintenance = dayMaintenanceAsync.value ?? const <String, double>{};
    final totals = totalsAsync.value ?? const <String, LogTotals>{};
    final weekStart = ref.watch(selectedWeekProvider);
    final weekAsync = ref.watch(weekTotalsProvider(weekStart));
    final monthPeriodAsync = ref.watch(monthPeriodTotalsProvider(month));

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('weightbuddy', style: AppText.label(color: AppColors.jollof)),
            const SizedBox(height: 16),
            _MonthHeader(
              month: month,
              onShift: (n) =>
                  ref.read(selectedMonthProvider.notifier).shift(n),
            ),
            const SizedBox(height: 12),
            PeriodLedgerCard(
              title: 'MONTH · ${DateFormat('MMMM yyyy').format(month)}',
              period: monthPeriodAsync.value,
            ),
            const SizedBox(height: 12),
            PeriodLedgerCard(
              title:
                  'WEEK · ${Formatters.range(weekStart, weekStart.add(const Duration(days: 7)))}',
              period: weekAsync.value,
              previousTooltip: 'Previous week',
              nextTooltip: 'Next week',
              onPrevious: () =>
                  ref.read(selectedWeekProvider.notifier).shift(-1),
              onNext: () => ref.read(selectedWeekProvider.notifier).shift(1),
            ),
            const SizedBox(height: 12),
            _StreakRow(
              logging: streaksAsync.value?.logging ?? 0,
              onPlan: streaksAsync.value?.onPlan ?? 0,
            ),
            const SizedBox(height: 20),
            _WeekdayHeader(),
            const SizedBox(height: 6),
            _CalendarGrid(
              month: month,
              totals: totals,
              dayMaintenance: dayMaintenance,
              currentMaintenance: currentMaintenance,
              onSelectDay: onSelectDay,
            ),
            const SizedBox(height: 16),
            const _Legend(),
          ],
        ),
      ),
    );
  }
}

enum _DayStatus { none, onPlan, over }

_DayStatus _statusFor(LogTotals? totals, double maintenance) {
  if (totals == null) return _DayStatus.none;
  return totals.netKcal > maintenance ? _DayStatus.over : _DayStatus.onPlan;
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.onShift});

  final DateTime month;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        now.year == month.year && now.month == month.month;
    return Row(
      children: [
        IconButton(
          onPressed: () => onShift(-1),
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left_rounded,
              color: AppColors.smoke, size: 28),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                DateFormat('MMMM yyyy').format(month),
                style: AppText.headline(),
              ),
              if (isCurrentMonth)
                Text('this month',
                    style: AppText.label(color: AppColors.smoke)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => onShift(1),
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right_rounded,
              color: AppColors.smoke, size: 28),
        ),
      ],
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.logging, required this.onPlan});

  final int logging;
  final int onPlan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StreakChip(
            icon: Icons.local_fire_department_rounded,
            iconColor: AppColors.jollof,
            label: 'LOG STREAK',
            value: '$logging d',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StreakChip(
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.ugu,
            label: 'ON-PLAN',
            value: '$onPlan d',
          ),
        ),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppText.dataM()),
                Text(label, style: AppText.label(color: AppColors.smoke)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final l in _labels)
          Expanded(
            child: Center(
              child: Text(l, style: AppText.label(color: AppColors.smoke)),
            ),
          ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.totals,
    required this.dayMaintenance,
    required this.currentMaintenance,
    required this.onSelectDay,
  });

  final DateTime month;
  final Map<String, LogTotals> totals;
  final Map<String, double> dayMaintenance;
  final double currentMaintenance;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1; // Monday-first
    final cells = ((offset + daysInMonth) / 7).ceil() * 7;
    final now = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.86,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: cells,
      itemBuilder: (context, i) {
        final dayNumber = i - offset + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox.shrink();
        }
        final date = DateTime(month.year, month.month, dayNumber);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}'
            '-${date.day.toString().padLeft(2, '0')}';
        final isToday = date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
        // Each day is judged by the target in effect when it was logged.
        final m = dayMaintenance[key] ?? currentMaintenance;
        final status = _statusFor(totals[key], m);
        return _DayCell(
          dayNumber: dayNumber,
          status: status,
          isToday: isToday,
          onTap: () => onSelectDay(date),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayNumber,
    required this.status,
    required this.isToday,
    required this.onTap,
  });

  final int dayNumber;
  final _DayStatus status;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (status) {
      case _DayStatus.onPlan:
        bg = AppColors.ugu.withValues(alpha: 0.22);
        fg = AppColors.ugu;
      case _DayStatus.over:
        bg = AppColors.jollof.withValues(alpha: 0.22);
        fg = AppColors.jollof;
      case _DayStatus.none:
        bg = AppColors.barkRaised;
        fg = AppColors.smoke;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: AppColors.bone, width: 1.4)
              : Border.all(color: AppColors.ember, width: 0.6),
        ),
        child: Center(
          child: Text(
            '$dayNumber',
            style: AppText.dataS(color: fg),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        _LegendDot(color: AppColors.ugu, label: 'at / below'),
        SizedBox(width: 16),
        _LegendDot(color: AppColors.jollof, label: 'above'),
        SizedBox(width: 16),
        _LegendDot(color: AppColors.smoke, label: 'not logged'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.bodyMuted(fontSize: 12)),
      ],
    );
  }
}
