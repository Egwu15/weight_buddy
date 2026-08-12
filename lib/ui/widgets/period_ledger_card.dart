import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'ledger_card.dart';

/// A ledger readout for a whole period — a week or a month — with a title and
/// optional prev/next navigation. LEFT here is budget − net, where the budget
/// is every day in the period at its maintenance target.
class PeriodLedgerCard extends StatelessWidget {
  const PeriodLedgerCard({
    super.key,
    required this.title,
    required this.totals,
    required this.budgetKcal,
    this.onPrevious,
    this.onNext,
    this.previousTooltip = 'Previous',
    this.nextTooltip = 'Next',
  });

  final String title;
  final LogTotals totals;
  final double budgetKcal;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String previousTooltip;
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(color: AppColors.smoke),
                  ),
                ),
                if (onPrevious != null)
                  IconButton(
                    onPressed: onPrevious,
                    tooltip: previousTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: AppColors.smoke, size: 24),
                  ),
                if (onNext != null)
                  IconButton(
                    onPressed: onNext,
                    tooltip: nextTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.smoke, size: 24),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 8, 14),
              child: LedgerCells(
                totals: totals,
                left: budgetKcal - totals.netKcal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}