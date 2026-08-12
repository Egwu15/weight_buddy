import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'ledger_card.dart';

/// A ledger readout for a whole period — a week or a month — with a title and
/// optional prev/next navigation. LEFT is budget − net − carried overspend:
/// for the ongoing period the budget runs from today → period end (untracked
/// earlier days count for nothing), so the number answers "what do I have
/// left from now on" without being inflated by skipped days.
class PeriodLedgerCard extends StatelessWidget {
  const PeriodLedgerCard({
    super.key,
    required this.title,
    required this.period,
    this.onPrevious,
    this.onNext,
    this.previousTooltip = 'Previous',
    this.nextTooltip = 'Next',
  });

  final String title;
  final PeriodTotals? period;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String previousTooltip;
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    final totals = period?.totals ?? const LogTotals();
    final overage = period?.overageKcal ?? 0;
    final fromToday = period?.fromToday ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: fromToday
                        ? 'Budget runs from today to the end of this period. '
                            "Untracked days aren't counted"
                            '${overage > 0 ? '; ${Formatters.kcal(overage)} carries over from earlier this period.' : '.'}'
                        : 'Budget is the whole period at its daily maintenance target.',
                    child: Text(
                      fromToday ? '$title · TODAY →' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(color: AppColors.smoke),
                    ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LedgerCells(
                    totals: totals,
                    left: period?.leftKcal ?? 0,
                  ),
                  if (fromToday)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'budget runs today → period end · untracked days not counted',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyMuted(fontSize: 11),
                      ),
                    ),
                  if (overage > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'carries ${Formatters.kcal(overage)} over from earlier this period',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyMuted(
                            fontSize: 11, color: AppColors.jollof),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}