import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/ai_service.dart';
import '../../models/log_entry.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/app_toast.dart';
import '../widgets/macro_pill.dart';
import '../widgets/meal_edit_parts.dart';

/// Results the record sheet can pop with, so the launcher can react.
const kRecordSheetLogged = 'logged';
const kRecordSheetGoToSettings = 'settings';

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
  bool _retryingConnection = false;

  Uint8List? _audioBytes;
  String _fileName = '';
  String _transcript = '';
  ParsedLog? _parsed;
  bool _typed = false;

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
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
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
    _typed = false;
    try {
      final service = ref.read(aiServiceProvider);
      final vocab = ref.read(settingsProvider).value?.vocabulary ?? '';
      _transcript = await service!.transcribe(
        audioBytes: _audioBytes!,
        filename: _fileName,
        prompt: vocab,
      );
      await _parseTyped(_transcript);
    } on AiServiceException catch (e) {
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
    final service = ref.read(aiServiceProvider);
    if (service == null) {
      setState(() => _stage = _Stage.needsKey);
      return;
    }
    final text = raw.trim();
    if (text.isEmpty) return;
    // The burn engine needs the user's weight to price the exercise; use the
    // latest weigh-in so 20 dips can never log a workout-sized number.
    final weighIns = ref.read(weighInsProvider).value ?? const [];
    final weightKg = weighIns.isEmpty ? null : weighIns.first.weightKg;
    final parsed = await service.parseTranscript(text, weightKg: weightKg);
    if (!mounted) return;
    _transcript = text;
    _typed = true;
    _parsed = parsed;
    setState(() => _stage = _Stage.confirm);
  }

  /// Same parse as [_parseTyped], but with the voice path's error handling so
  /// a typed entry can’t crash the sheet on a failed API call.
  Future<void> _submitTyped(String raw) async {
    _typed = true;
    try {
      await _parseTyped(raw);
    } on AiServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = 'Something went wrong while parsing that. Try again.';
      });
    }
  }

  Future<void> _save(ParsedLog parsed) async {
    ref.read(selectedDayProvider.notifier).setDay(DateTime.now());
    for (final entry in parsed.toEntries(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      rawTranscript: _transcript,
    )) {
      await ref.read(dayLogsProvider.notifier).add(entry);
    }
    if (!mounted) return;
    Navigator.of(context).pop(kRecordSheetLogged);
  }

  String get _elapsed {
    final ms = _stopwatch.elapsedMilliseconds;
    final s = (ms / 1000).floor();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// The "no session yet" state: shown when sign-in failed (usually offline at
  /// first launch) or a stored session was rejected. The likely cause is the
  /// connection, so retrying sign-in is the primary action; Settings is the
  /// fallback for a rejected session.
  Widget _needsKeyView() => _Tight(
        child: _NeedsKeyView(
          retrying: _retryingConnection,
          onRetry: _retryConnection,
          onGoToSettings: () =>
              Navigator.of(context).pop(kRecordSheetGoToSettings),
        ),
      );

  Future<void> _retryConnection() async {
    setState(() => _retryingConnection = true);
    await ref.read(settingsProvider.notifier).refreshSession();
    if (!mounted) return;
    setState(() => _retryingConnection = false);
    if (ref.read(aiServiceProvider) == null) {
      AppToast.show(
        context,
        'Still no connection. Check your network and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(aiServiceProvider);
    final Widget body;
    if (service == null &&
        _stage != _Stage.error &&
        _stage != _Stage.processing) {
      body = _needsKeyView();
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
            initialText: _transcript,
            onBack: () => setState(() => _stage = _Stage.idle),
            onSubmit: _submitTyped,
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
          sourceLabel: _typed ? 'You wrote:' : 'The words I heard:',
          onSave: (edited) => _save(edited),
          onDiscard: () => Navigator.of(context).pop(),
          onEditText: () => setState(() {
            // Back to the keyboard, words intact — fix and re-parse.
            _typed = true;
            _stage = _Stage.type;
          }),
        ),
        _Stage.needsKey => _needsKeyView(),
        _Stage.error => _Tight(
          child: _ErrorView(
            message: _errorMessage,
            onRetry: () {
              // Failed while typing? Send them back to the keyboard, not the mic.
              setState(() => _stage = _typed ? _Stage.type : _Stage.idle);
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
    // viewInsets pushes the sheet clear of the on-screen keyboard when the
    // typing view focuses the text field (it's 0 when no keyboard is open).
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
          child: child,
        ),
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
      child: Center(child: SingleChildScrollView(child: child)),
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
            child: const Icon(
              Icons.mic_rounded,
              color: AppColors.pot,
              size: 52,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('Hold to speak', style: AppText.title()),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            tooShort
                ? 'That was too short. Hold a little longer.'
                : 'Release when you’re done',
            key: ValueKey(tooShort),
            style: AppText.bodyMuted(fontSize: 13),
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: onType,
          icon: const Icon(
            Icons.keyboard_alt_outlined,
            color: AppColors.smoke,
            size: 18,
          ),
          label: const Text('Type instead'),
          style: TextButton.styleFrom(foregroundColor: AppColors.smoke),
        ),
      ],
    );
  }
}

/// Quiet-day fallback: type what you ate or how you moved instead of
/// speaking, and the same GPT pipeline parses it. [initialText] pre-fills the
/// box so “fix the words” round-trips from the confirm stage keep what was
/// already said.
class _TypeView extends StatefulWidget {
  const _TypeView({
    required this.onBack,
    required this.onSubmit,
    this.initialText = '',
  });

  final VoidCallback onBack;
  final ValueChanged<String> onSubmit;
  final String initialText;

  @override
  State<_TypeView> createState() => _TypeViewState();
}

class _TypeViewState extends State<_TypeView> {
  late final _controller = TextEditingController(text: widget.initialText);
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Log by typing', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          'Noisy room or tired voice? Just type what you ate '
          'or how you moved.',
          textAlign: TextAlign.center,
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          style: AppText.body(),
          decoration: const InputDecoration(
            hintText: 'e.g. two plates of jollof rice and fried chicken',
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.smoke,
                  ),
                )
              : const Icon(Icons.auto_awesome_rounded, size: 20),
          label: Text(_submitting ? 'Parsing…' : 'Parse'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onBack,
          child: const Text('Back to voice'),
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
          child: CustomPaint(painter: _LiveWavePainter(levels: levels)),
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
          'The words are on their way back.',
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
    required this.sourceLabel,
    required this.onSave,
    required this.onDiscard,
    required this.onEditText,
  });

  final ParsedLog parsed;
  final String sourceLabel;
  final ValueChanged<ParsedLog> onSave;
  final VoidCallback onDiscard;

  /// Jumps back to the typing view pre-filled with the transcript, so the
  /// user can fix the words and re-parse instead of discarding and starting
  /// over.
  final VoidCallback onEditText;

  @override
  State<_ConfirmView> createState() => _ConfirmViewState();
}

class _ConfirmViewState extends State<_ConfirmView> {
  late final List<MealItem> _items = List.of(widget.parsed.items);
  late MealType _mealType = widget.parsed.mealType;
  late final List<MealQuantityController> _qtyControllers = [
    for (final item in _items) MealQuantityController(item),
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

  void _onQtyChanged(int index, String raw) {
    final scaled = _qtyControllers[index].scaledTo(raw);
    if (scaled == null) return;
    setState(() => _items[index] = scaled);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.parsed;
    final isMeal = parsed.type == EntryType.meal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
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
                  '${widget.sourceLabel} “${widget.parsed.summary}”',
                  style: AppText.bodyMuted(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onEditText,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.smoke,
                      size: 16,
                    ),
                    label: const Text(
                      'The words came out wrong. Fix and re-parse',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.smoke,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                if (isMeal) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in MealType.values)
                        if (type != MealType.meal)
                          ChoiceChip(
                            label: Text(mealTypeLabel(type)),
                            selected: _mealType == type,
                            onSelected: (_) => setState(() => _mealType = type),
                            backgroundColor: AppColors.barkRaised,
                            selectedColor: AppColors.jollof,
                            labelStyle: AppText.bodyMuted(
                              fontSize: 13,
                              color: _mealType == type
                                  ? AppColors.pot
                                  : AppColors.bone,
                            ),
                            side: const BorderSide(color: AppColors.ember),
                          ),
                    ],
                  ),
                ],
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
                  MealTotalsRow(
                    calories: _calories,
                    protein: _protein,
                    carbs: _carbs,
                    fat: _fat,
                  ),
                ] else ...[
                  for (final exercise in parsed.exerciseList)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExerciseCard(exercise: exercise),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
                onPressed: () => widget.onSave(
                  isMeal
                      ? ParsedLog(
                          type: EntryType.meal,
                          summary: parsed.summary,
                          items: _items,
                          calories: _calories,
                          proteinG: _protein,
                          carbsG: _carbs,
                          fatG: _fat,
                          mealType: _mealType,
                        )
                      : parsed,
                ),
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
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
                    '${Formatters.kcal(item.calories)} kcal',
                    style: AppText.dataS(color: AppColors.smoke),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      MacroPill(
                        label: 'PROTEIN',
                        value: '${Formatters.grams(item.proteinG)}g',
                        color: MacroPill.proteinColor,
                      ),
                      MacroPill(
                        label: 'CARBS',
                        value: '${Formatters.grams(item.carbsG)}g',
                        color: MacroPill.carbsColor,
                      ),
                      MacroPill(
                        label: 'FAT',
                        value: '${Formatters.grams(item.fatG)}g',
                        color: MacroPill.fatColor,
                      ),
                    ],
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
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});

  final ParsedExercise exercise;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_run_rounded,
            color: AppColors.ugu,
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: AppText.title()),
                const SizedBox(height: 2),
                Text(
                  exerciseSubtitle(exercise),
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
          child: const Icon(
            Icons.hearing_disabled_rounded,
            color: AppColors.chili,
            size: 30,
          ),
        ),
        const SizedBox(height: 20),
        Text('Didn’t catch that', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: AppText.bodyMuted()),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onDiscard,
                child: const Text('Discard'),
              ),
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
  const _NeedsKeyView({
    required this.onGoToSettings,
    required this.onRetry,
    required this.retrying,
  });

  final VoidCallback onGoToSettings;
  final VoidCallback onRetry;
  final bool retrying;

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
          child: const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.plantain,
            size: 30,
          ),
        ),
        const SizedBox(height: 20),
        Text('Connect to Weight Buddy', style: AppText.headline()),
        const SizedBox(height: 8),
        Text(
          'Logging needs a connection. Check your network and try again. '
          'The app signs you in automatically.',
          textAlign: TextAlign.center,
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: retrying ? null : onRetry,
          icon: retrying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 20),
          label: Text(retrying ? 'Trying again…' : 'Try again'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onGoToSettings,
          child: const Text('Open Settings'),
        ),
      ],
    );
  }
}
