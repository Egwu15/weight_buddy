import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/weigh_in.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'weigh_in_sheet.dart';

/// Full weigh-in history, newest first, with delete and add.
class WeightHistoryScreen extends ConsumerWidget {
  const WeightHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weighInsAsync = ref.watch(weighInsProvider);
    final unit = ref.watch(appSettingsProvider).value?.weightUnit ?? 'kg';
    final weighIns = weighInsAsync.value ?? const <WeighIn>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.pot,
        title: Text('Weigh-ins', style: AppText.title()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.plantain,
        foregroundColor: AppColors.pot,
        onPressed: () => showWeighInSheet(context),
        icon: const Icon(Icons.monitor_weight_outlined),
        label: const Text('Weigh in'),
      ),
      body: weighIns.isEmpty
          ? const _EmptyHistory()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              itemCount: weighIns.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _WeighInTile(weighIn: weighIns[index], unit: unit),
            ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monitor_weight_outlined,
              color: AppColors.smoke, size: 28),
          const SizedBox(height: 10),
          Text('No weigh-ins yet', style: AppText.title()),
          const SizedBox(height: 4),
          Text(
            'Log one and the trend starts to show.',
            style: AppText.bodyMuted(),
          ),
        ],
      ),
    );
  }
}

class _WeighInTile extends ConsumerWidget {
  const _WeighInTile({required this.weighIn, required this.unit});

  final WeighIn weighIn;
  final String unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Formatters.fullDate(weighIn.date),
                    style: AppText.label(color: AppColors.smoke),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Formatters.weight(weighIn.weightKg, unit),
                        style: AppText.dataL(color: AppColors.plantain),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          unit,
                          style: AppText.label(color: AppColors.smoke),
                        ),
                      ),
                    ],
                  ),
                  if (weighIn.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(weighIn.note, style: AppText.bodyMuted()),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: () => _confirmDelete(context, ref),
              tooltip: 'Delete weigh-in',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.chili, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bark,
        title: const Text('Delete this weigh-in?'),
        content: const Text('This reading will be removed.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(weighInsProvider.notifier).delete(weighIn);
  }
}
