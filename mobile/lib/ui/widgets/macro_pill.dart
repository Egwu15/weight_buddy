import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// A labeled macro readout (colored dot + name + grams), matching the
/// dashboard macro plate. Used on the record confirm card and the timeline.
class MacroPill extends StatelessWidget {
  const MacroPill({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  /// Macro colors, matching the dashboard macro plate (protein / carbs / fat).
  static const proteinColor = AppColors.plantain;
  static const carbsColor = AppColors.jollof;
  static const fatColor = Color(0xFFC08A5A); // suya tan

  final Color color;
  final String label;
  final String value;

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
        Text(label, style: AppText.label(color: color)),
        const SizedBox(width: 4),
        Text(value, style: AppText.dataS(color: AppColors.bone)),
      ],
    );
  }
}
