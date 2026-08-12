import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'macro_pill.dart';

/// One row in the day's timeline.
class TimelineTile extends StatelessWidget {
  const TimelineTile({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  final LogEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isMeal = entry.type == EntryType.meal;
    final accent = isMeal ? AppColors.jollof : AppColors.ugu;
    final icon = isMeal ? Icons.restaurant_rounded : Icons.directions_run_rounded;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        Formatters.timeOfDay(entry.timestamp),
                        style: AppText.label(color: AppColors.smoke),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.summary,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (isMeal)
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${Formatters.kcal(entry.calories)} kcal',
                          style: AppText.dataS(color: AppColors.smoke),
                        ),
                        MacroPill(
                          label: 'PROTEIN',
                          value: '${Formatters.grams(entry.proteinG)}g',
                          color: MacroPill.proteinColor,
                        ),
                        MacroPill(
                          label: 'CARBS',
                          value: '${Formatters.grams(entry.carbsG)}g',
                          color: MacroPill.carbsColor,
                        ),
                        MacroPill(
                          label: 'FAT',
                          value: '${Formatters.grams(entry.fatG)}g',
                          color: MacroPill.fatColor,
                        ),
                      ],
                    )
                  else
                    Text(
                      '${Formatters.kcal(entry.calories)} kcal burned',
                      style: AppText.dataS(color: AppColors.smoke),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete entry',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.smoke, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
