import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// The day as a plate: one segmented bar where each macro is a portion.
class MacroPlate extends StatelessWidget {
  const MacroPlate({super.key, required this.totals});

  final LogTotals totals;

  static const proteinColor = AppColors.plantain;
  static const carbsColor = AppColors.jollof;
  static const fatColor = Color(0xFFC08A5A); // suya tan

  @override
  Widget build(BuildContext context) {
    final p = totals.proteinG;
    final c = totals.carbsG;
    final f = totals.fatG;
    final hasMacros = (p + c + f) > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Macros', style: AppText.title()),
                const Spacer(),
                Text('grams', style: AppText.label(color: AppColors.smoke)),
              ],
            ),
            const SizedBox(height: 14),
            if (!hasMacros)
              SizedBox(
                height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.barkRaised,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              )
            else
              Row(
                children: [
                  _Segment(
                    flex: p == 0 ? 0 : p.toInt(),
                    color: proteinColor,
                  ),
                  _Segment(flex: c == 0 ? 0 : c.toInt(), color: carbsColor),
                  _Segment(flex: f == 0 ? 0 : f.toInt(), color: fatColor),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                _MacroCell(color: proteinColor, label: 'Protein', grams: p),
                _MacroCell(color: carbsColor, label: 'Carbs', grams: c),
                _MacroCell(color: fatColor, label: 'Fat', grams: f),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.flex, required this.color});

  final int flex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    );
  }
}

class _MacroCell extends StatelessWidget {
  const _MacroCell({
    required this.color,
    required this.label,
    required this.grams,
  });

  final Color color;
  final String label;
  final double grams;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 6),
          Text(
            grams > 0 ? '${Formatters.grams(grams)}g' : '—',
            style: AppText.dataS(),
          ),
          Text(label, style: AppText.label(color: AppColors.smoke)),
        ],
      ),
    );
  }
}
