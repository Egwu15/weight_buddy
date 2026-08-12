import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/openai_service.dart';
import '../../models/log_entry.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

enum _Stage { idle, recording, processing, confirm, needsKey, error, type }

/// The voice flow: hold to speak, watch your words become a meal
/// (or a workout), confirm, done.
class RecordSheet extends ConsumerStatefulWidget {
  const RecordSheet({super.key});

  @override
  ConsumerState<RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends ConsumerState<RecordSheet> {
  _Stage _stage = _Stage.idle;
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  final List<double> _levels = [];
  String _errorMessage = '';
  bool _tooShort = false;

  Uint8List? _audioBytes;
  String _fileName = '';
  String _transcript = '';
  ParsedLog? _parsed;

  @override
  void dispose() {
    _ampSub?.cancel();
    _ticker?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/wb_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      setState(() {
        _stage = _Stage.error;
        _errorMessage =
            'Microphone access is off. Allow the microphone in system Settings, then come back.';
      });
      return;
    }
    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    _recorder = recorder;
    _levels.clear();
    _tooShort = false;
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    _ampSub = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
      final norm = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      setState(() {
        _levels.add(norm);
        if (_levels.length > 48) _levels.removeAt(0);
      });
    });
    setState(() => _stage = _Stage.recording);
  }

  Future<void> _stopRecording() async {
    await _ampSub?.cancel();
    _ampSub = null;
    _ticker?.cancel();
    _ticker = null;
    _stopwatch.stop();
    final path = await _recorder?.stop();
    _recorder = null;
    if (path == null) {
      setState(() => _stage = _Stage.idle);
      return;
    }
    if (_stopwatch.elapsedMilliseconds < 800) {
      setState(() {
        _tooShort = true;
        _stage = _Stage.idle;
      });
      return;
    }
    final bytes = await File(path).readAsBytes();
    _audioBytes = bytes;
    _fileName = path.split('/').last;
    setState(() => _stage = _Stage.processing);
    await _process();
  }

  Future<void> _process() async {
    try {
      final service = ref.read(openaiServiceProvider);
      final vocab = ref.read(settingsProvider).value?.vocabulary ?? '';
      _transcript = await service!.transcribe(
        audioBytes: _audioBytes!,
        filename: _fileName,
        prompt: vocab,
      );
      await _parseTyped(_transcript);
    } on OpenAIServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage =
            'Something went wrong while reading your recording. Try again.';
      });
    }
  }

  /// Shared second stage of the pipeline: a transcript (spoken or typed) is
  /// turned into a structured meal/exercise, then shown for confirmation.
  Future<void> _parseTyped(String raw) async {
    final service = ref.read(openaiServiceProvider);
    if (service == null) {
      setState(() => _stage = _Stage.needsKey);
      return;
    }
    final text = raw.trim();
    if (text.isEmpty) return;
    final parsed = await service.parseTranscript(text);
    if (!mounted) return;
    _transcript = text;
    _parsed = parsed;
    setState(() => _stage = _Stage.confirm);
  }

  Future<void> _save(ParsedLog parsed) async {
    final entry = parsed.toEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      rawTranscript: _transcript,
    );
    await ref.read(dayLogsProvider.notifier).add(entry);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String get _elapsed {
    final ms = _stopwatch.elapsedMilliseconds;
    final s = (ms / 1000).floor();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(openaiServiceProvider);
    final Widget body;
    if (service == null && _stage != _Stage.error && _stage != _Stage.processing) {
      body = const _Tight(child: _NeedsKeyView());
    } else {
      body = switch (_stage) {
        _Stage.idle => _Tight(
            child: _IdleView(
              tooShort: _tooShort,
              onStart: _startRecording,
              onStop: _stopRecording,
              onType: () => setState(() => _stage = _Stage.type),
            ),
          ),
        _Stage.type => _Tight(
            child: _TypeView(
              onBack: () => setState(() => _stage = _Stage.idle),
              onSubmit: _parseTyped,
            ),
          ),
        _Stage.recording => _Tight(
            child: _RecordingView(
              elapsed: _elapsed,
              levels: List.unmodifiable(_levels),
              onStop: _stopRecording,
            ),
          ),
        _Stage.processing => const _Tight(child: _ProcessingView()),
        _Stage.confirm => _ConfirmView(
            parsed: _parsed!,
            onSave: (edited) => _save(edited),
            onDiscard: () => Navigator.of(context).pop(),
          ),
        _Stage.needsKey => const _Tight(child: _NeedsKeyView()),
        _Stage.error => _Tight(
            child: _ErrorView(
              message: _errorMessage,
              onRetry: () {
                setState(() => _stage = _Stage.idle);
              },
              onDiscard: () => Navigator.of(context).pop(),
            ),
          ),
      };
    }

    return _SheetFrame(child: body);
  }
}

/// The padded, height-capped frame every sheet state sits in.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
        child: child,
      ),
    );
  }
}

/// Gives short status views a comfortable fixed height and centers their
/// content, so buttons never hug the bottom edge of the sheet.
class _Tight extends StatelessWidget {
  const _Tight({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      child: Center(
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.tooShort,
    required this.onStart,
    required this.onStop,
    required this.onType,
  });

  final bool tooShort;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Log by voice', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          'Meals and workouts both work. Say “two plates of jollof rice” '
          'or “ran for 30 minutes”.',
          textAlign: TextAlign.center,
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 28),
        GestureDetector(
          onTapDown: (_) => onStart(),
          onTapUp: (_) => onStop(),
          onTapCancel: onStop,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.jollof,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.jollof.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.mic_rounded, color: AppColors.pot, size: 52),
          ),
        ),
        const SizedBox(height: 18),
        Text('Hold to speak', style: AppText.title()),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            tooShort
                ? 'That was too short — hold a little longer.'
                : 'Release when you’re done',
            key: ValueKey(tooShort),
            style: AppText.bodyMuted(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _RecordingView extends StatelessWidget {
  const _RecordingView({
    required this.elapsed,
    required this.levels,
    required this.onStop,
  });

  final String elapsed;
  final List<double> levels;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.chili,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text('Listening…', style: AppText.title(color: AppColors.bone)),
            const SizedBox(width: 12),
            Text(elapsed, style: AppText.dataM(color: AppColors.smoke)),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(
            painter: _LiveWavePainter(levels: levels),
          ),
        ),
        const SizedBox(height: 24),
        Text('Release when you’re done', style: AppText.bodyMuted()),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded, size: 22),
          label: const Text('Done'),
        ),
      ],
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
        const SizedBox(height: 24),
        Text('Reading your meal…', style: AppText.title()),
        const SizedBox(height: 8),
        Text(
          'The words are on their way back from OpenAI.',
          style: AppText.bodyMuted(fontSize: 13),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _LiveWavePainter extends CustomPainter {
  _LiveWavePainter({required this.levels});

  final List<double> levels;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final baseline = Paint()
      ..color = AppColors.ember
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), baseline);

    if (levels.isEmpty) return;
    final barW = size.width / 48;
    final paint = Paint()..color = AppColors.jollof;
    for (var i = 0; i < levels.length; i++) {
      final h = math.max(2.0, levels[i] * (size.height / 2 - 4));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(barW * i + barW / 2, centerY),
            width: barW * 0.62,
            height: h * 2,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveWavePainter oldDelegate) =>
      oldDelegate.levels != levels;
}

class _ConfirmView extends StatefulWidget {
  const _ConfirmView({
    required this.parsed,
    required this.onSave,
    required this.onDiscard,
  });

  final ParsedLog parsed;
  final ValueChanged<ParsedLog> onSave;
  final VoidCallback onDiscard;

  @override
  State<_ConfirmView> createState() => _ConfirmViewState();
}

class _ConfirmViewState extends State<_ConfirmView> {
  late final List<MealItem> _items = List.of(widget.parsed.items);
  late final List<TextEditingController> _qtyControllers = [
    for (final item in _items) TextEditingController(text: item.quantity),
  ];

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  double get _calories => _items.fold(0, (s, i) => s + i.calories);
  double get _protein => _items.fold(0, (s, i) => s + i.proteinG);
  double get _carbs => _items.fold(0, (s, i) => s + i.carbsG);
  double get _fat => _items.fold(0, (s, i) => s + i.fatG);

  double _factor(String raw, MealItem item) {
    final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(raw);
    if (m == null) return 1;
    final oldM = RegExp(r'\d+(?:\.\d+)?').firstMatch(item.quantity);
    final oldV = oldM == null ? 1.0 : double.tryParse(oldM.group(0)!) ?? 1.0;
    final newV = double.tryParse(m.group(0)!) ?? oldV;
    if (oldV <= 0) return 1;
    return newV / oldV;
  }

  void _onQtyChanged(int index, String raw) {
    final factor = _factor(raw, _items[index]);
    if (factor <= 0) return;
    final old = _items[index];
    setState(() {
      _items[index] = MealItem(
        name: old.name,
        quantity: raw,
        calories: old.calories * factor,
        proteinG: old.proteinG * factor,
        carbsG: old.carbsG * factor,
        fatG: old.fatG * factor,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.parsed;
    final isMeal = parsed.type == EntryType.meal;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isMeal ? 'Does this look right?' : 'Check the workout',
            style: AppText.headline(),
          ),
          const SizedBox(height: 6),
          Text(
            'The words I heard: “${widget.parsed.summary}”',
            style: AppText.bodyMuted(fontSize: 13),
          ),
          const SizedBox(height: 18),
          if (isMeal) ...[
            for (var i = 0; i < _items.length; i++)
              _ItemRow(
                index: i,
                item: _items[i],
                controller: _qtyControllers[i],
                onChanged: (raw) => _onQtyChanged(i, raw),
              ),
            const SizedBox(height: 16),
            _TotalsRow(
              calories: _calories,
              protein: _protein,
              carbs: _carbs,
              fat: _fat,
            ),
          ] else
            _ExerciseCard(parsed: parsed),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onDiscard,
                  child: const Text('Discard'),
                ),
              ),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => widget.onSave(isMeal
                      ? ParsedLog(
                          type: EntryType.meal,
                          summary: parsed.summary,
                          items: _items,
                          calories: _calories,
                          proteinG: _protein,
                          carbsG: _carbs,
                          fatG: _fat,
                        )
                      : parsed),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.item,
    required this.controller,
    required this.onChanged,
  });

  final int index;
  final MealItem item;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.barkRaised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: AppText.title(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    '${Formatters.kcal(item.calories)} kcal · '
                    'P ${Formatters.grams(item.proteinG)} · '
                    'C ${Formatters.grams(item.carbsG)} · '
                    'F ${Formatters.grams(item.fatG)}',
                    style: AppText.dataS(color: AppColors.smoke),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: AppText.dataS(),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ember),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL', style: AppText.label()),
              const SizedBox(height: 2),
              Text('${Formatters.kcal(calories)} kcal',
                  style: AppText.dataL(color: AppColors.jollof)),
            ],
          ),
          const Spacer(),
          Text('P ${Formatters.grams(protein)}',
              style: AppText.dataS(color: AppColors.smoke)),
          const SizedBox(width: 12),
          Text('C ${Formatters.grams(carbs)}',
              style: AppText.dataS(color: AppColors.smoke)),
          const SizedBox(width: 12),
          Text('F ${Formatters.grams(fat)}',
              style: AppText.dataS(color: AppColors.smoke)),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.parsed});

  final ParsedLog parsed;

  @override
  Widget build(BuildContext context) {
    final duration = parsed.durationMinutes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_run_rounded,
              color: AppColors.ugu, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(parsed.activity ?? parsed.summary, style: AppText.title()),
                const SizedBox(height: 2),
                Text(
                  '${duration != null ? '${Formatters.grams(duration)} min · ' : ''}'
                  '${Formatters.kcal(parsed.calories)} kcal burned',
                  style: AppText.dataS(color: AppColors.smoke),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onDiscard,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0x33E0563E),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.hearing_disabled_rounded,
              color: AppColors.chili, size: 30),
        ),
        const SizedBox(height: 20),
        Text('Didn’t catch that', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                  onPressed: onDiscard, child: const Text('Discard')),
            ),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.replay_rounded, size: 20),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NeedsKeyView extends StatelessWidget {
  const _NeedsKeyView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0x33F2B53C),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.key_rounded,
              color: AppColors.plantain, size: 30),
        ),
        const SizedBox(height: 20),
        Text('Your key goes here first', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          'Weight Buddy works with your own OpenAI API key. '
          'Add it in Settings and you’re ready to talk.',
          textAlign: TextAlign.center,
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.settings_rounded, size: 20),
          label: const Text('Go to Settings'),
        ),
      ],
    );
  }
}




