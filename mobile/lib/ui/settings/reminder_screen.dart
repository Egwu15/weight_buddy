import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// The daily log nudge: on/off and the time it fires. The nudge only speaks
/// up when the day still has gaps.
class ReminderScreen extends ConsumerWidget {
  const ReminderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Daily reminder', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Daily reminder', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'A daily nudge to log, at a time you choose. Scheduled on this '
            'device only.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 12),
          const _ReminderTile(),
        ],
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
                    'Only when a meal or workout is missing',
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
    if (!value) {
      await ref.read(rearmDailyReminderProvider)();
      return;
    }
    final reminder = ref.read(reminderServiceProvider);
    final granted = await reminder.requestPermissions();
    if (!granted) {
      await ref.read(appSettingsProvider.notifier).save(current);
      if (context.mounted) {
        AppToast.show(context, 'Notification permission was not granted');
      }
      return;
    }
    // The nudge is armed only when nothing has been logged today.
    await ref.read(rearmDailyReminderProvider)();
  }

  Future<void> _pickTime(
      BuildContext context, WidgetRef ref, TimeOfDay current) async {
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !context.mounted) return;
    await ref.read(appSettingsProvider.notifier).save(
          ref.read(appSettingsProvider).value!.copyWith(reminderTime: picked),
        );
    await ref.read(rearmDailyReminderProvider)();
  }
}
