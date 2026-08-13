import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/weigh_in.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/app_toast.dart';

/// Bottom sheet to log a weigh-in: date, weight in kg or lb, optional note.
Future<void> showWeighInSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const WeighInSheet(),
  );
}

class WeighInSheet extends ConsumerStatefulWidget {
  const WeighInSheet({super.key});

  @override
  ConsumerState<WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends ConsumerState<WeighInSheet> {
  final _weightController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _date = DateTime.now();
  // Unit is a per-entry input choice; weight is always stored in kg.
  String _unit = 'kg';
  String? _error;

  @override
  void dispose() {
    _weightController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? _parseWeight() {
    final text = _weightController.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    // Store kilograms regardless of display unit.
    return _unit == 'lb' ? value / 2.2046226218 : value;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.jollof,
                onPrimary: AppColors.pot,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final kg = _parseWeight();
    if (kg == null) {
      setState(() => _error = 'Enter a weight above zero.');
      return;
    }
    final day = DateTime(_date.year, _date.month, _date.day);
    await ref.read(weighInsProvider.notifier).add(
          WeighIn(
            date: day,
            weightKg: kg,
            note: _noteController.text.trim(),
          ),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, 'Weigh-in saved');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text('Weigh in', style: AppText.title())),
          const SizedBox(height: 20),
          Text('Date', style: AppText.label()),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.barkRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.ember),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: AppColors.smoke, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    Formatters.fullDate(_date),
                    style: AppText.body(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Weight', style: AppText.label()),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  style: AppText.dataL(),
                  decoration: InputDecoration(
                    labelText: _unit == 'lb' ? 'pounds' : 'kilograms',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _UnitToggle(
                unit: _unit,
                onChanged: (u) => setState(() => _unit = u),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Note (optional)', style: AppText.label()),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            style: AppText.body(),
            decoration: const InputDecoration(
              hintText: 'Morning, fasted…',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.monitor_weight_outlined, size: 20),
              label: const Text('Save weigh-in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});

  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UnitButton(
            label: 'kg',
            selected: unit == 'kg',
            onTap: () => onChanged('kg'),
          ),
          _UnitButton(
            label: 'lb',
            selected: unit == 'lb',
            onTap: () => onChanged('lb'),
          ),
        ],
      ),
    );
  }
}

class _UnitButton extends StatelessWidget {
  const _UnitButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.plantain : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: AppText.label(
            color: selected ? AppColors.pot : AppColors.smoke,
          ),
        ),
      ),
    );
  }
}
