import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings_data.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// BYOK settings: the user's own OpenAI key (secure vault) and the
/// vocabulary of dish names the transcription should recognize.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _keyController = TextEditingController();
  final _vocabController = TextEditingController();
  final _maintenanceController = TextEditingController();
  String? _savedKey;
  bool _hydrated = false;
  bool _targetsHydrated = false;
  String? _keyError;
  bool _saving = false;
  String _weightUnit = 'kg';
  String? _targetError;

  @override
  void dispose() {
    _keyController.dispose();
    _vocabController.dispose();
    _maintenanceController.dispose();
    super.dispose();
  }

  /// Shows only the last few characters of a saved key — the full value
  /// is never placed into the UI.
  static String _maskKey(String key) {
    final tail = key.length <= 4 ? key : key.substring(key.length - 4);
    final prefix = key.startsWith('sk-') ? 'sk-' : '';
    return '$prefix••••••••$tail';
  }

  void _hydrate(AppSettings settings) {
    if (_hydrated) return;
    _hydrated = true;
    _savedKey = settings.apiKey.trim().isEmpty ? null : settings.apiKey.trim();
    _vocabController.text = settings.vocabulary;
  }

  void _hydrateTargets(AppSettingsData data) {
    if (_targetsHydrated) return;
    _targetsHydrated = true;
    _maintenanceController.text =
        data.maintenanceKcal.round().toString();
    _weightUnit = data.weightUnit;
  }

  Future<void> _save() async {
    final newKey = _keyController.text.trim();
    // Keep the existing key unless the user typed a replacement.
    final apiKey = newKey.isNotEmpty ? newKey : (_savedKey ?? '');
    final vocab = _vocabController.text.trim();
    if (apiKey.isNotEmpty && !apiKey.startsWith('sk-')) {
      setState(() => _keyError =
          'Keys start with “sk-”. Check the whole key was pasted.');
      return;
    }
    final maintenance =
        double.tryParse(_maintenanceController.text.trim().replaceAll(',', '.'));
    if (maintenance == null || maintenance <= 0) {
      setState(() => _targetError = 'Enter maintenance calories above zero.');
      return;
    }
    setState(() {
      _keyError = null;
      _targetError = null;
      _saving = true;
    });
    await ref
        .read(settingsProvider.notifier)
        .save(apiKey: apiKey, vocabulary: vocab);
    final appSettings = await ref.read(appSettingsProvider.future);
    await ref.read(appSettingsProvider.notifier).save(
          appSettings.copyWith(
            maintenanceKcal: maintenance,
            weightUnit: _weightUnit,
          ),
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedKey = apiKey.isEmpty ? null : apiKey;
      _keyController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  void _replaceKey() {
    setState(() {
      _savedKey = null;
      _keyController.clear();
      _keyError = null;
    });
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bark,
        title: const Text('Delete all entries?'),
        content: const Text(
            'Every meal and workout on this device will be removed. This can’t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.chili,
              foregroundColor: AppColors.pot,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = await ref.read(databaseProvider.future);
    await db.wipeAllData();
    ref.invalidate(dayLogsProvider);
    ref.invalidate(weighInsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All entries deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    settings.whenOrNull(data: _hydrate);
    final appSettings = ref.watch(appSettingsProvider);
    appSettings.whenOrNull(data: _hydrateTargets);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Your OpenAI key', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Weight Buddy sends your recordings to OpenAI and stores the key '
            'in your device’s secure vault. Only the last few characters are '
            'ever shown again — the full key never appears in this app.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 16),
          if (_savedKey == null) ...[
            TextField(
              controller: _keyController,
              autocorrect: false,
              enableSuggestions: false,
              style: AppText.dataS(),
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: 'sk-…',
                errorText: _keyError,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.barkRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.ember),
              ),
              child: Row(
                children: [
                  const Icon(Icons.key_rounded,
                      color: AppColors.plantain, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _maskKey(_savedKey!),
                      style: AppText.dataS(),
                    ),
                  ),
                  const Icon(Icons.lock_rounded,
                      color: AppColors.ugu, size: 16),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _replaceKey,
                child: const Text('Replace key'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Foods it should recognize', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'A comma-separated list of local dish names. Spoken names listed '
            'here are passed to the transcription model so it hears them right.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _vocabController,
            style: AppText.body(),
            decoration: const InputDecoration(
              labelText: 'Custom vocabulary',
              hintText: 'Jollof, Egusi, Amala, Suya, Akara, Dodo',
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Targets', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Maintenance calories is the line the calendar and the coach '
            'measure you against. Days at or under it count as on-plan.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _maintenanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppText.dataM(),
            decoration: InputDecoration(
              labelText: 'Maintenance calories / day',
              hintText: '2200',
              suffixText: 'kcal',
              errorText: _targetError,
            ),
          ),
          const SizedBox(height: 16),
          Text('Weight unit', style: AppText.label()),
          const SizedBox(height: 8),
          _WeightUnitToggle(
            unit: _weightUnit,
            onChanged: (u) => setState(() => _weightUnit = u),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Reminder', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'A daily nudge to log, at a time you choose. Scheduled on this '
            'device only.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 12),
          const _ReminderTile(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: Text(_saving ? 'Saving…' : 'Save changes'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Your data', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Everything is stored on this device. Delete the lot whenever '
            'you want a clean slate.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _deleteAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.chili,
              side: const BorderSide(color: AppColors.chili),
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
            label: const Text('Delete all entries'),
          ),
        ],
      ),
    );
  }
}

class _WeightUnitToggle extends StatelessWidget {
  const _WeightUnitToggle({required this.unit, required this.onChanged});

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
          _UnitChoice(
            label: 'kg',
            selected: unit == 'kg',
            onTap: () => onChanged('kg'),
          ),
          _UnitChoice(
            label: 'lb',
            selected: unit == 'lb',
            onTap: () => onChanged('lb'),
          ),
        ],
      ),
    );
  }
}

class _UnitChoice extends StatelessWidget {
  const _UnitChoice({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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


class _ReminderTile extends ConsumerWidget {
  const _ReminderTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    final enabled = settings.reminderEnabled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_outlined,
                color: AppColors.plantain, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enabled
                        ? 'Daily at ${_formatTime(settings.reminderTime)}'
                        : 'Reminder off',
                    style: AppText.title(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Nudge me to log',
                    style: AppText.bodyMuted(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (enabled)
              TextButton(
                onPressed: () => _pickTime(context, ref, settings.reminderTime),
                child: const Text('Change'),
              ),
            Switch(
              value: enabled,
              activeThumbColor: AppColors.plantain,
              onChanged: (v) => _setEnabled(context, ref, v),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(TimeOfDay time) {
    final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final suffix = time.period == DayPeriod.am ? 'am' : 'pm';
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m $suffix';
  }

  Future<void> _setEnabled(
      BuildContext context, WidgetRef ref, bool value) async {
    final current = ref.read(appSettingsProvider).value;
    if (current == null) return;
    final next = current.copyWith(reminderEnabled: value);
    await ref.read(appSettingsProvider.notifier).save(next);
    final reminder = ref.read(reminderServiceProvider);
    if (!value) {
      await reminder.cancel();
      return;
    }
    final granted = await reminder.requestPermissions();
    if (!granted) {
      await ref.read(appSettingsProvider.notifier).save(current);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Notification permission was not granted')),
        );
      }
      return;
    }
    await reminder.scheduleDaily(
      hour: next.reminderTime.hour,
      minute: next.reminderTime.minute,
    );
  }

  Future<void> _pickTime(
      BuildContext context, WidgetRef ref, TimeOfDay current) async {
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !context.mounted) return;
    await ref.read(appSettingsProvider.notifier).save(
          ref.read(appSettingsProvider).value!.copyWith(reminderTime: picked),
        );
    final reminder = ref.read(reminderServiceProvider);
    await reminder.scheduleDaily(hour: picked.hour, minute: picked.minute);
  }
}

