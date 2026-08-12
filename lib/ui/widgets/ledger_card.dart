import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// The four mono readouts on one line — EATEN, BURNED, NET, LEFT — separated
/// by hairlines. Shared by the daily [LedgerCard] and the weekly/monthly
/// [PeriodLedgerCard].
class LedgerCells extends StatelessWidget {
  const LedgerCells({super.key, required this.totals, required this.left});

  final LogTotals totals;

  /// What's left of this period's budget: green while positive, jollof when
  /// the budget is gone.
  final double left;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LedgerCell(
          label: 'EATEN',
          value: Formatters.kcal(totals.eatenKcal),
          color: AppColors.jollof,
        ),
        const _Hairline(),
        _LedgerCell(
          label: 'BURNED',
          value: Formatters.kcal(totals.burnedKcal),
          color: AppColors.ugu,
        ),
        const _Hairline(),
        _LedgerCell(
          label: 'NET',
          value: Formatters.kcal(totals.netKcal),
          color: AppColors.bone,
        ),
        const _Hairline(),
        _LedgerCell(
          label: 'LEFT',
          value: Formatters.kcal(left),
          color: left >= 0 ? AppColors.ugu : AppColors.jollof,
        ),
      ],
    );
  }
}

/// The kitchen-scale readout: eaten, burned, net — and how much of the
/// daily maintenance budget is left.
class LedgerCard extends StatelessWidget {
  const LedgerCard({
    super.key,
    required this.totals,
    required this.maintenanceKcal,
  });

  final LogTotals totals;

  /// The daily maintenance target; remaining = maintenance - net.
  final double maintenanceKcal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: LedgerCells(
          totals: totals,
          left: maintenanceKcal - totals.netKcal,
        ),
      ),
    );
  }
}

class _LedgerCell extends StatelessWidget {
  const _LedgerCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppText.label(color: AppColors.smoke)),
          const SizedBox(height: 6),
          // Four readouts share one line, so they use the medium mono size
          // (FittedBox only kicks in as a safety net on very narrow screens).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppText.dataM(color: color)),
          ),
          const SizedBox(height: 2),
          Text('kcal', style: AppText.label(color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 44, color: AppColors.ember);
  }
}
