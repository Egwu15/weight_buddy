import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/weigh_in.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// The scale card: latest weight, the delta over the last 30 days, and a
/// hairline trend drawn the same quiet way as the Day's Wave.
class WeightCard extends ConsumerWidget {
  const WeightCard({super.key, required this.onOpenHistory});

  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weighInsAsync = ref.watch(weighInsProvider);
    final unit = ref.watch(appSettingsProvider).value?.weightUnit ?? 'kg';
    final weighIns = weighInsAsync.value ?? const <WeighIn>[];

    if (weighIns.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            children: [
              const Icon(Icons.monitor_weight_outlined,
                  color: AppColors.plantain, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weight', style: AppText.title()),
                    const SizedBox(height: 2),
                    Text(
                      'No weigh-ins yet. Step on the scale and log it.',
                      style: AppText.bodyMuted(fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onOpenHistory,
                tooltip: 'Weigh-ins',
                icon: const Icon(Icons.add_rounded,
                    color: AppColors.plantain, size: 22),
              ),
            ],
          ),
        ),
      );
    }

    final latest = weighIns.first;
    final baseline = _baselineWeight(weighIns, latest);
    final delta = baseline == null ? null : latest.weightKg - baseline;
    final trend = _trendPoints(weighIns);

    return Card(
      child: InkWell(
        onTap: onOpenHistory,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Weight', style: AppText.title()),
                  const Spacer(),
                  Text(
                    baseline == null
                        ? 'first reading'
                        : (delta == null || delta <= 0
                            ? '−${Formatters.weight(delta?.abs() ?? 0, unit)} $unit'
                            : '+${Formatters.weight(delta, unit)} $unit'),
                    style: AppText.label(
                      color: baseline == null || delta == null || delta <= 0
                          ? AppColors.ugu
                          : AppColors.jollof,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.weight(latest.weightKg, unit),
                    style: AppText.dataL(color: AppColors.plantain),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child:
                        Text(unit, style: AppText.label(color: AppColors.smoke)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WeightSparkPainter(points: trend),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The weight at or before 30 days before [latest] (or the earliest).
  static double? _baselineWeight(List<WeighIn> sortedDesc, WeighIn latest) {
    final cutoff = latest.date.subtract(const Duration(days: 30));
    WeighIn? before;
    for (final w in sortedDesc) {
      if (!w.date.isAfter(cutoff) && w.id != latest.id) {
        before = w;
        break;
      }
    }
    return before?.weightKg;
  }

  static List<WeighIn> _trendPoints(List<WeighIn> sortedDesc,
      {int maxPoints = 30}) {
    return sortedDesc.reversed.take(maxPoints).toList();
  }
}

class _WeightSparkPainter extends CustomPainter {
  _WeightSparkPainter({required this.points});

  final List<WeighIn> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        2.5,
        Paint()..color = AppColors.jollof,
      );
      return;
    }
    final weights = points.map((w) => w.weightKg).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final span = (maxW - minW).abs() < 0.5 ? 1.0 : (maxW - minW);
    final dx = size.width / (points.length - 1);
    const bottomPad = 3.0, topPad = 5.0;
    final usableH = size.height - bottomPad - topPad;

    Offset pointAt(int i) => Offset(
          i * dx,
          topPad + usableH * (1 - (weights[i] - minW) / span),
        );

    final line = Path();
    line.moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < points.length; i++) {
      final p = pointAt(i);
      line.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.plantain.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    final dotPaint = Paint()..color = AppColors.jollof;
    for (var i = 0; i < points.length; i++) {
      final p = pointAt(i);
      canvas.drawCircle(p, i == points.length - 1 ? 3 : 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WeightSparkPainter oldDelegate) =>
      oldDelegate.points != points;
}
