import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/openai_service.dart';
import '../../models/log_entry.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'macro_pill.dart';
import 'meal_edit_parts.dart';

/// Opens the edit/resend sheet for an already-logged [entry].
///
/// Returns `true` when the entry was saved back (updated in place, same id and
/// timestamp). The caller decides what to tell the user after the sheet
/// closes.
Future<bool?> showEntryEditor(
  BuildContext context, {
  required LogEntry entry,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EntryEditorSheet(
      original: entry,
      parsed: ParsedLog.fromEntry(entry),
      transcript: entry.rawTranscript,
    ),
  );
}

/// Fix an already-saved meal or workout without re-dictating it from scratch.
///
/// Two ways to put things right, matching the two ways entries go wrong:
///
/// 1. **Resend** — the transcript is editable, and “Re-parse with AI” runs it
///    back through the same GPT pipeline (with the user's latest weigh-in so
///    burns stay deterministic). Forgot the plantain? Add it to the words and
///    re-parse. The AI priced the chicken wrong? Edit the words and re-parse.
/// 2. **Edit by hand** — tweak quantities (calories/macros scale with the
///    number, like the confirm sheet), add or remove items, pick the meal
///    type. Works even without an API key.
///
/// Saving keeps the row's original id and timestamp, so the timeline keeps its
/// position and the day's maintenance snapshot stays intact.
class EntryEditorSheet extends ConsumerStatefulWidget {
  const EntryEditorSheet({
    super.key,
    required this.original,
    required this.parsed,
    required this.transcript,
  });

  /// The saved row being fixed.
  final LogEntry original;

  /// The entry's parsed shape, seeded via [ParsedLog.fromEntry].
  final ParsedLog parsed;

  /// The transcript to start the editor with (the row's `rawTranscript`).
  final String transcript;

  @override
  ConsumerState<EntryEditorSheet> createState() => _EntryEditorSheetState();
}

class _EntryEditorSheetState extends ConsumerState<EntryEditorSheet> {
  late EntryType _type = widget.parsed.type;
  late String _summary = widget.parsed.summary;
  late List<MealItem> _items = List.of(widget.parsed.items);
  late List<ParsedExercise> _exercises = List.of(widget.parsed.exerciseList);
  late MealType _mealType = widget.parsed.mealType;
  late final TextEditingController _transcriptController =
      TextEditingController(text: widget.transcript);
  late List<MealQuantityController> _qtyControllers = [
    for (final item in _items) MealQuantityController(item),
  ];
  bool _addingItem = false;
  bool _reparsing = false;
  bool _saving = false;
  String? _reparseError;
  String? _saveError;

  @override
  void dispose() {
    _transcriptController.dispose();
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isMeal => _type == EntryType.meal;
  double get _calories => _items.fold(0, (s, i) => s + i.calories);
  double get _protein => _items.fold(0, (s, i) => s + i.proteinG);
  double get _carbs => _items.fold(0, (s, i) => s + i.carbsG);
  double get _fat => _items.fold(0, (s, i) => s + i.fatG);

  void _onQtyChanged(int index, String raw) {
    final scaled = _qtyControllers[index].scaledTo(raw);
    if (scaled == null) return;
    setState(() => _items[index] = scaled);
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items.removeAt(index);
      _qtyControllers[index].dispose();
      _qtyControllers.removeAt(index);
    });
  }

  void _addItem(MealItem item) {
    setState(() {
      _items.add(item);
      _qtyControllers.add(MealQuantityController(item));
      _addingItem = false;
    });
  }

  void _removeExercise(int index) {
    if (_exercises.length <= 1) return;
    setState(() => _exercises.removeAt(index));
  }

  /// “Resend”: runs the (possibly amended) transcript back through the AI
  /// parse pipeline and swaps in the result. Weight is the latest weigh-in so
  /// exercise burns stay deterministic, exactly like the record sheet.
  Future<void> _reparse() async {
    final service = ref.read(openaiServiceProvider);
    final text = _transcriptController.text.trim();
    if (service == null) {
      setState(() {
        _reparseError =
            'Save your OpenAI key in Settings to re-parse with AI — or fix '
            'the quantities by hand below.';
      });
      return;
    }
    if (text.isEmpty) {
      setState(() {
        _reparseError = 'Type what you ate or how you moved first.';
      });
      return;
    }
    setState(() {
      _reparsing = true;
      _reparseError = null;
      _saveError = null;
    });
    try {
      final weighIns = ref.read(weighInsProvider).value ?? const [];
      final weightKg = weighIns.isEmpty ? null : weighIns.first.weightKg;
      final parsed = await service.parseTranscript(text, weightKg: weightKg);
      if (!mounted) return;
      for (final c in _qtyControllers) {
        c.dispose();
      }
      setState(() {
        _type = parsed.type;
        _summary = parsed.summary;
        _items = List.of(parsed.items);
        _exercises = List.of(parsed.exerciseList);
        _mealType = parsed.mealType;
        _qtyControllers = [
          for (final item in _items) MealQuantityController(item),
        ];
        _reparsing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reparsing = false;
        _reparseError = '$e';
      });
    }
  }

  ParsedLog _buildParsed() {
    if (_isMeal) {
      return ParsedLog(
        type: EntryType.meal,
        summary: _summary,
        items: _items,
        calories: _calories,
        proteinG: _protein,
        carbsG: _carbs,
        fatG: _fat,
        mealType: _mealType,
      );
    }
    return ParsedLog(
      type: EntryType.exercise,
      summary: _summary,
      exercises: _exercises,
      calories: _exercises.fold(0.0, (s, e) => s + e.caloriesBurned),
      mealType: _mealType,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final original = widget.original;
    try {
      final updated = _buildParsed()
          .toEntries(
            timestamp: original.timestamp,
            rawTranscript: _transcriptController.text.trim(),
          )
          .first
          .copyWith(id: original.id);
      await ref.read(dayLogsProvider.notifier).edit(updated);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '$e';
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final accent = _isMeal ? AppColors.jollof : AppColors.ugu;
    final icon =
        _isMeal ? Icons.restaurant_rounded : Icons.directions_run_rounded;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isMeal ? 'EDIT MEAL' : 'EDIT WORKOUT',
                      style: AppText.label(color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.timeOfDay(widget.original.timestamp),
                      style: AppText.label(color: AppColors.smoke),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(_summary, style: AppText.headline()),
          const SizedBox(height: 4),
          Text(
            'Fix the words and re-parse, or tweak the quantities below — the '
            'edit keeps this entry’s place in the day.',
            style: AppText.bodyMuted(fontSize: 13),
          ),
          const SizedBox(height: 18),

          Text('WHAT YOU SAID', style: AppText.label(color: AppColors.smoke)),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('entry-editor-transcript'),
            controller: _transcriptController,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: AppText.body(),
            decoration: const InputDecoration(
              hintText: 'Add the bit you forgot, or correct what the AI misread',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('entry-editor-reparse'),
              onPressed: _reparsing ? null : _reparse,
              icon: _reparsing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_reparsing ? 'Re-parsing…' : 'Re-parse with AI'),
            ),
          ),
          if (_reparseError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _reparseError!,
                style:
                    AppText.bodyMuted(fontSize: 13, color: AppColors.chili),
              ),
            ),
          const SizedBox(height: 10),


          if (_isMeal) ...[
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
            const SizedBox(height: 18),
            for (var i = 0; i < _items.length; i++)
              _EditableItemRow(
                index: i,
                item: _items[i],
                controller: _qtyControllers[i],
                onChanged: (raw) => _onQtyChanged(i, raw),
                onRemove: _items.length > 1 ? () => _removeItem(i) : null,
              ),
            if (_addingItem)
              _AddItemForm(
                onAdd: _addItem,
                onCancel: () => setState(() => _addingItem = false),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('entry-editor-add-item'),
                  onPressed: () => setState(() => _addingItem = true),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('Add an item'),
                ),
              ),
            const SizedBox(height: 12),
            MealTotalsRow(
              calories: _calories,
              protein: _protein,
              carbs: _carbs,
              fat: _fat,
            ),
          ] else ...[
            for (var i = 0; i < _exercises.length; i++)
              _EditableExerciseCard(
                exercise: _exercises[i],
                onRemove:
                    _exercises.length > 1 ? () => _removeExercise(i) : null,
              ),
          ],
          const SizedBox(height: 24),
          if (_saveError != null) ...[
            Text(
              _saveError!,
              style: AppText.bodyMuted(fontSize: 13, color: AppColors.chili),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const ValueKey('entry-editor-save'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(_saving ? 'Saving…' : 'Save changes'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// One meal item with an editable quantity and a remove button.
class _EditableItemRow extends StatelessWidget {
  const _EditableItemRow({
    required this.index,
    required this.item,
    required this.controller,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final MealItem item;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Null when the last item must stay (a meal needs at least one item).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
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
                key: ValueKey('entry-editor-qty-$index'),
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
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove item',
              icon: const Icon(
                Icons.remove_circle_outline_rounded,
                color: AppColors.smoke,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The inline “Add an item” form: name + quantity + kcal, macros optional.
class _AddItemForm extends StatefulWidget {
  const _AddItemForm({required this.onAdd, required this.onCancel});

  final ValueChanged<MealItem> onAdd;
  final VoidCallback onCancel;

  @override
  State<_AddItemForm> createState() => _AddItemFormState();
}

class _AddItemFormState extends State<_AddItemForm> {
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _quantity, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.onAdd(MealItem(
      name: name,
      quantity: _quantity.text.trim().isEmpty ? '1' : _quantity.text.trim(),
      calories: double.tryParse(_kcal.text.trim()) ?? 0,
      proteinG: double.tryParse(_protein.text.trim()) ?? 0,
      carbsG: double.tryParse(_carbs.text.trim()) ?? 0,
      fatG: double.tryParse(_fat.text.trim()) ?? 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.barkRaised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('entry-editor-add-name'),
              controller: _name,
              autofocus: true,
              style: AppText.body(),
              decoration: const InputDecoration(
                hintText: 'e.g. Plantain chips',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    style: AppText.body(),
                    decoration: const InputDecoration(
                      hintText: 'Quantity (e.g. 1 bowl)',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('entry-editor-add-kcal'),
                    controller: _kcal,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AppText.body(),
                    decoration: const InputDecoration(
                      hintText: 'kcal',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (controller, label) in [
                  (_protein, 'Protein (g)'),
                  (_carbs, 'Carbs (g)'),
                  (_fat, 'Fat (g)'),
                ]) ...[
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: AppText.body(),
                      decoration: InputDecoration(
                        hintText: label,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (controller != _fat) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: const ValueKey('entry-editor-add-save'),
                    onPressed: _submit,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add to meal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// One exercise in a workout being edited, removable (re-parse covers adding
/// exercises back).
class _EditableExerciseCard extends StatelessWidget {
  const _EditableExerciseCard({
    required this.exercise,
    required this.onRemove,
  });

  final ParsedExercise exercise;

  /// Null when the last exercise must stay.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
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
            const SizedBox(width: 12),
            Text(
              '${Formatters.kcal(exercise.caloriesBurned)} kcal',
              style: AppText.dataS(color: AppColors.smoke),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove exercise',
              icon: const Icon(
                Icons.remove_circle_outline_rounded,
                color: AppColors.smoke,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


