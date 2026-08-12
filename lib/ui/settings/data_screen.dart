import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed_demo.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// Data: everything is stored on this device. Demo seeding (debug builds)
/// and a full wipe live here, away from the day-to-day settings.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bark,
        title: const Text('Delete all entries?'),
        content: const Text(
            'Every meal, workout, weigh-in, chat, memory and saved workout '
            'on this device will be removed. This can’t be undone.'),
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
    ref.invalidate(chatMessagesProvider);
    ref.invalidate(memoriesProvider);
    ref.invalidate(exercisesProvider);
    await ref.read(rearmDailyReminderProvider)(db: db);
    if (!mounted) return;
    AppToast.show(context, 'All entries deleted');
  }

  /// Fills the app with a realistic “busy week” so the screens can be
  /// reviewed without real logging. Wipes the current records first; the
  /// OpenAI key and targets are kept. Debug-only affordance.
  Future<void> _loadDemo() async {
    if (!kDebugMode) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bark,
        title: const Text('Load demo data?'),
        content: const Text(
            'Replaces your entries with a realistic “busy week” demo — '
            'meals, workouts, weigh-ins, a coach conversation, memories and '
            'saved workouts. Your OpenAI key and targets are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.plantain,
              foregroundColor: AppColors.pot,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Load demo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = await ref.read(databaseProvider.future);
    await db.wipeAllData();
    await seedDemoData(db, force: true);
    ref.invalidate(dayLogsProvider);
    ref.invalidate(weighInsProvider);
    ref.invalidate(chatMessagesProvider);
    ref.invalidate(memoriesProvider);
    ref.invalidate(exercisesProvider);
    ref.invalidate(appSettingsProvider);
    // The demo logs today, so the nudge has nothing to say.
    await ref.read(rearmDailyReminderProvider)(db: db);
    if (!mounted) return;
    AppToast.show(context, 'Demo data loaded');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Data', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Your data', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Everything is stored on this device. Delete the lot whenever '
            'you want a clean slate.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 12),
          if (kDebugMode) ...[
            OutlinedButton.icon(
              onPressed: _loadDemo,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.plantain,
                side: const BorderSide(color: AppColors.plantain),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: const Text('Load demo data'),
            ),
            const SizedBox(height: 12),
          ],
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
