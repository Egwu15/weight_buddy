import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/memory.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// The coach's memory: what it remembers about you, fully editable, with a
/// master switch that stops all writes and injection.
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoriesAsync = ref.watch(memoriesProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final memories = memoriesAsync.value ?? const <Memory>[];
    final memoryEnabled = settingsAsync.value?.memoryEnabled ?? true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.pot,
        title: Text('Memory', style: AppText.title()),
      ),
      floatingActionButton: memoryEnabled
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.plantain,
              foregroundColor: AppColors.pot,
              onPressed: () => _addMemory(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Remember'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.ember),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Let the coach remember', style: AppText.title()),
                      const SizedBox(height: 4),
                      Text(
                        memoryEnabled
                            ? 'New facts are distilled from conversations and used '
                                'as context. Stored only on this device.'
                            : 'Memory is off — nothing is distilled or injected.',
                        style: AppText.bodyMuted(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: memoryEnabled,
                  activeThumbColor: AppColors.plantain,
                  onChanged: (v) => ref
                      .read(appSettingsProvider.notifier)
                      .patch((s) => s.copyWith(memoryEnabled: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (memories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  const Icon(Icons.psychology_outlined,
                      color: AppColors.smoke, size: 28),
                  const SizedBox(height: 10),
                  Text('Nothing remembered yet', style: AppText.title()),
                  const SizedBox(height: 4),
                  Text(
                    'After a few chats the coach distils what matters. '
                    'You can also add a memory yourself.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyMuted(),
                  ),
                ],
              ),
            )
          else
            for (final memory in memories) ...[
              _MemoryTile(memory: memory),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Future<void> _addMemory(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_MemoryFormResult>(
      context: context,
      builder: (context) => const _MemoryFormDialog(),
    );
    if (result == null || !context.mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(memoriesProvider.notifier).upsert(Memory(
          topic: result.topic,
          content: result.content,
          category: result.category,
          source: MemorySource.user,
          createdAt: now,
          updatedAt: now,
        ));
  }
}

class _MemoryTile extends ConsumerWidget {
  const _MemoryTile({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.barkRaised,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          memory.category.apiName.toUpperCase(),
                          style: AppText.label(color: AppColors.plantain),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        memory.source == MemorySource.user
                            ? 'you said'
                            : 'coach learned',
                        style: AppText.label(color: AppColors.smoke),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(memory.content, style: AppText.body()),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _edit(context, ref),
              tooltip: 'Edit memory',
              icon: const Icon(Icons.edit_outlined,
                  color: AppColors.smoke, size: 20),
            ),
            IconButton(
              onPressed: () => ref.read(memoriesProvider.notifier).remove(memory),
              tooltip: 'Forget',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.chili, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_MemoryFormResult>(
      context: context,
      builder: (context) => _MemoryFormDialog(
        initialTopic: memory.topic,
        initialContent: memory.content,
        initialCategory: memory.category,
      ),
    );
    if (result == null || !context.mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(memoriesProvider.notifier).upsert(Memory(
          topic: result.topic,
          content: result.content,
          category: result.category,
          source: memory.source,
          createdAt: memory.createdAt,
          updatedAt: now,
        ));
  }
}


class _MemoryFormResult {
  const _MemoryFormResult({
    required this.topic,
    required this.content,
    required this.category,
  });

  final String topic;
  final String content;
  final MemoryCategory category;
}

class _MemoryFormDialog extends StatefulWidget {
  const _MemoryFormDialog({
    this.initialTopic = '',
    this.initialContent = '',
    this.initialCategory = MemoryCategory.note,
  });

  final String initialTopic;
  final String initialContent;
  final MemoryCategory initialCategory;

  @override
  State<_MemoryFormDialog> createState() => _MemoryFormDialogState();
}

class _MemoryFormDialogState extends State<_MemoryFormDialog> {
  late final _topic = TextEditingController(text: widget.initialTopic);
  late final _content = TextEditingController(text: widget.initialContent);
  late MemoryCategory _category = widget.initialCategory;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bark,
      title: Text(
          widget.initialTopic.isEmpty ? 'Add a memory' : 'Edit memory',
          style: AppText.title()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _topic,
            style: AppText.dataS(),
            decoration: InputDecoration(
              labelText: 'Topic',
              hintText: 'training_goal',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            style: AppText.body(),
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What to remember',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final c in MemoryCategory.values)
                ChoiceChip(
                  label: Text(c.apiName),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_topic.text.trim().isEmpty || _content.text.trim().isEmpty) {
              setState(() => _error = 'Topic and content are both needed.');
              return;
            }
            Navigator.of(context).pop(_MemoryFormResult(
              topic: _topic.text.trim(),
              content: _content.text.trim(),
              category: _category,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

