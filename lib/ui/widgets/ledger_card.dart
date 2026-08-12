import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// The kitchen-scale readout: eaten, burned, net — three mono numbers
/// on one line, separated by hairlines.
class LedgerCard extends StatelessWidget {
  const LedgerCard({super.key, required this.totals});

  final LogTotals totals;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Row(
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
          ],
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppText.dataL(color: color)),
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
