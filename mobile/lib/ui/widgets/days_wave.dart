import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/log_entry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// The signature: the day takes the shape of your voice.
///
/// Today's logs are drawn as a waveform. Each peak is one entry — height
/// follows calories, colour follows type (jollof = meal, ugu = exercise),
/// and position follows the clock. An empty day is a flatline.
class DaysWave extends StatefulWidget {
  const DaysWave({super.key, required this.entries, required this.totals});

  final List<LogEntry> entries;
  final LogTotals totals;

  @override
  State<DaysWave> createState() => _DaysWaveState();
}

class _DaysWaveState extends State<DaysWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal;
  int _selected = -1;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..value = widget.entries.isEmpty ? 0 : 1;
  }

  @override
  void didUpdateWidget(DaysWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    final grew = widget.entries.length > oldWidget.entries.length;
    if (grew && widget.entries.isNotEmpty) {
      if (MediaQuery.of(context).disableAnimations) {
        _reveal.value = 1;
      } else {
        _reveal.forward(from: 0);
      }
    } else {
      _reveal.value = widget.entries.isEmpty ? 0 : 1;
    }
    if (_selected >= widget.entries.length) _selected = -1;
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  String get _caption {
    if (widget.entries.isEmpty) {
      return 'Nothing logged yet — hold the mic and say what you ate.';
    }
    if (_selected >= 0 && _selected < widget.entries.length) {
      final e = widget.entries[_selected];
      return e.type == EntryType.meal
          ? '${Formatters.timeOfDay(e.timestamp)} · ${e.summary} · '
              '${Formatters.kcal(e.calories)} kcal'
          : '${Formatters.timeOfDay(e.timestamp)} · ${e.summary} · '
              'burned ${Formatters.kcal(e.calories)} kcal';
    }
    final meals =
        widget.entries.where((e) => e.type == EntryType.meal).length;
    final workouts = widget.entries.length - meals;
    final parts = <String>[
      if (meals == 1) '1 meal' else if (meals > 1) '$meals meals',
      if (workouts == 1)
        '1 workout'
      else if (workouts > 1)
        '$workouts workouts',
    ];
    return '${parts.join(', ')} · '
        '${Formatters.kcal(widget.totals.eatenKcal)} kcal eaten'
        '${widget.totals.burnedKcal > 0 ? ', ${Formatters.kcal(widget.totals.burnedKcal)} burned' : ''}';
  }

  String get _semanticsLabel {
    final meals =
        widget.entries.where((e) => e.type == EntryType.meal).length;
    final workouts = widget.entries.length - meals;
    return widget.entries.isEmpty
        ? 'The day as a sound wave. Nothing logged yet.'
        : 'The day as a sound wave. $meals meals and $workouts workouts. '
            '${Formatters.kcal(widget.totals.eatenKcal)} kilocalories eaten, '
            '${Formatters.kcal(widget.totals.burnedKcal)} burned.';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    return Semantics(
      label: _semanticsLabel,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 84,
            child: entries.isEmpty
                ? CustomPaint(
                    size: const Size(double.infinity, 84),
                    painter: _WavePainter(
                      entries: const [],
                      selected: -1,
                      reveal: 1,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _reveal,
                              builder: (context, child) => CustomPaint(
                                painter: _WavePainter(
                                  entries: entries,
                                  selected: _selected,
                                  reveal: _reveal.value,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < entries.length; i++)
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(() =>
                                        _selected = _selected == i ? -1 : i),
                                    child: const SizedBox(),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const _LegendDot(color: AppColors.jollof, label: 'Meal'),
              const SizedBox(width: 16),
              const _LegendDot(color: AppColors.ugu, label: 'Exercise'),
              const Spacer(),
              Flexible(
                child: Text(
                  _caption,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyMuted(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
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
        const SizedBox(width: 6),
        Text(label, style: AppText.label(color: AppColors.smoke)),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.entries,
    required this.selected,
    required this.reveal,
  });

  final List<LogEntry> entries;
  final int selected;
  final double reveal;

  static const _barsPerPeak = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    final baseline = Paint()
      ..color = AppColors.ember
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), baseline);

    if (entries.isEmpty) return;

    final maxSqrt =
        entries.map((e) => math.sqrt(math.max(e.calories, 1))).reduce(math.max);
    final slotW = size.width / entries.length;
    final maxBarH = (size.height / 2) - 7;
    final barW = 3.0;
    final gap = 2.5;
    final groupW = _barsPerPeak * barW + (_barsPerPeak - 1) * gap;

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final amplitude =
          0.35 + 0.65 * (math.sqrt(math.max(e.calories, 1)) / maxSqrt);
      final isNewest = i == entries.length - 1;
      final revealScale =
          isNewest ? Curves.easeOutCubic.transform(reveal) : 1.0;
      final color = selected == i
          ? AppColors.plantain
          : e.type == EntryType.meal
              ? AppColors.jollof
              : AppColors.ugu;

      final startX = slotW * i + (slotW - groupW) / 2;
      final paint = Paint()..color = color;
      for (var j = 0; j < _barsPerPeak; j++) {
        final envelope =
            0.35 + 0.65 * math.sin(math.pi * j / (_barsPerPeak - 1));
        final height =
            math.max(3.0, amplitude * envelope * maxBarH * 2) * revealScale;
        final x = startX + j * (barW + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, centerY), width: barW, height: height),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.entries != entries ||
      oldDelegate.selected != selected ||
      oldDelegate.reveal != reveal;
}
