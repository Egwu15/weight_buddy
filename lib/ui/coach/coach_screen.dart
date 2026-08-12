import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/coach_context.dart';
import '../../data/openai_service.dart';
import '../../models/chat_message.dart';
import '../../models/exercise_recommendation.dart';
import '../../models/log_entry.dart';
import '../../models/memory.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../memory/memory_screen.dart';
import '../workouts/workouts_screen.dart';

/// The coach: a persisted conversation with the user's own key, fed a
/// digest of their live data plus the distilled memory + exercise layers.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _error;
  int _turnsSinceDistill = 0;

  static const _exerciseKeywords = [
    'exercise',
    'workout',
    'routine',
    'train',
    'strength',
    'cardio',
    'reps',
    'sets',
    'gym',
    'muscle',
    'plan',
    'squat',
    'lift',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    final service = ref.read(openaiServiceProvider);
    if (service == null) {
      setState(() => _error =
          'Save your OpenAI key in Settings first, then come back and chat.');
      return;
    }

    final chatController = ref.read(chatMessagesProvider.notifier);
    await chatController.addUser(text);
    _input.clear();
    setState(() {
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final db = await ref.read(databaseProvider.future);
      final appSettings = await ref.read(appSettingsProvider.future);
      final now = DateTime.now();

      final last7 = <(DateTime, LogTotals)>[];
      for (var i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final logs = await db.logsForDay(day);
        last7.add((
          DateTime(day.year, day.month, day.day),
          LogTotals.fromEntries(logs),
        ));
      }
      final todayLogs = await db.logsForDay(now);
      final weighIns = await db.weighIns(limit: 30);
      final memoryEnabled = appSettings.memoryEnabled;
      final memories = memoryEnabled ? await db.memories() : const <Memory>[];
      final exercises = await db.exercises();
      final streaks = await ref.read(streakProvider.future);
      final context = CoachContext.build(
        today: LogTotals.fromEntries(todayLogs),
        last7Days: last7,
        maintenanceKcal: appSettings.maintenanceKcal,
        weighIns: weighIns,
        streaks: streaks,
        memories: memories,
        exercises: exercises,
      );

      final history = await db.chatMessages(limit: 30);
      final turns = history
          .map((m) => ChatTurn(role: m.role, content: m.content))
          .toList();
      final reply = await service.chat(
        systemPrompt: '${CoachContext.persona}\n\n$context',
        history: turns,
      );
      await chatController.addAssistant(reply);
      _turnsSinceDistill++;

      if (memoryEnabled) {
        await _maybeDistill(db);
      }
      await _maybeExtractExercises(db, text, reply);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  /// Every four exchanges, review the recent conversation and fold new
  /// facts into the memory store (latest-wins per topic).
  Future<void> _maybeDistill(AppDatabase db) async {
    if (_turnsSinceDistill < 4) return;
    _turnsSinceDistill = 0;
    final service = ref.read(openaiServiceProvider);
    if (service == null) return;
    final recent = await db.chatMessages(limit: 8);
    if (recent.length < 4) return;
    final drafts = await service.distillMemories(
      exchange:
          recent.map((m) => ChatTurn(role: m.role, content: m.content)).toList(),
    );
    final controller = ref.read(memoriesProvider.notifier);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final d in drafts) {
      if (d.action == 'remove') {
        final existing = await db.memories();
        for (final m in existing.where((m) => m.topic == d.topic)) {
          await controller.remove(m);
        }
        continue;
      }
      await controller.upsert(Memory(
        topic: d.topic,
        content: d.content,
        category: d.category,
        source: MemorySource.auto,
        createdAt: now,
        updatedAt: now,
      ));
    }
  }

  /// When the exchange is about exercises, run the strict-schema extraction
  /// and auto-save anything concrete it finds.
  Future<void> _maybeExtractExercises(
      AppDatabase db, String userText, String reply) async {
    final haystack = '${userText.toLowerCase()} ${reply.toLowerCase()}';
    if (!_exerciseKeywords.any(haystack.contains)) return;
    final service = ref.read(openaiServiceProvider);
    if (service == null) return;
    final extraction = await service.extractExercises(exchange: [
      ChatTurn(role: 'user', content: userText),
      ChatTurn(role: 'assistant', content: reply),
    ]);
    if (!extraction.hasAdvice || extraction.drafts.isEmpty) return;

    final controller = ref.read(exercisesProvider.notifier);
    var saved = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final d in extraction.drafts) {
      final ok = await controller.add(ExerciseRecommendation(
        name: d.name,
        description: d.description,
        muscleGroups: d.muscleGroups,
        sets: d.sets,
        reps: d.reps,
        restSeconds: d.restSeconds,
        durationMinutes: d.durationMinutes,
        difficulty: d.difficulty,
        planName: d.planName,
        createdAt: now,
      ));
      if (ok) saved++;
    }
    if (saved > 0 && mounted) {
      final label = saved == 1
          ? 'Saved “${extraction.drafts.first.name}” to your workouts'
          : 'Saved $saved exercises to your workouts';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          action: SnackBarAction(
            label: 'View',
            textColor: AppColors.plantain,
            onPressed: _openWorkouts,
          ),
        ),
      );
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bark,
        title: const Text('Start a fresh conversation?'),
        content: const Text(
            'The chat thread is cleared. Saved exercises and memories stay.'),
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
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(chatMessagesProvider.notifier).clear();
    _turnsSinceDistill = 0;
  }

  void _openMemory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MemoryScreen()),
    );
  }

  void _openWorkouts() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkoutsScreen()),
    );
  }


  @override
  Widget build(BuildContext context) {
    ref.listen(coachDraftProvider, (prev, next) {
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(coachDraftProvider.notifier).consume();
          _send(next);
        });
      }
    });

    final messagesAsync = ref.watch(chatMessagesProvider);
    final messages = messagesAsync.value ?? const <ChatMessage>[];
    final hasKey = ref.watch(openaiServiceProvider) != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Text('coach', style: AppText.label(color: AppColors.jollof)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'sees today + 7 days + weight',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(color: AppColors.smoke),
                    ),
                  ),
                  IconButton(
                    onPressed: _openMemory,
                    tooltip: 'Memory',
                    icon: const Icon(Icons.psychology_outlined,
                        color: AppColors.smoke, size: 20),
                  ),
                  IconButton(
                    onPressed: _openWorkouts,
                    tooltip: 'Saved workouts',
                    icon: const Icon(Icons.fitness_center_outlined,
                        color: AppColors.smoke, size: 20),
                  ),
                  IconButton(
                    onPressed: _confirmClear,
                    tooltip: 'New conversation',
                    icon: const Icon(Icons.restart_alt_rounded,
                        color: AppColors.smoke, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: messages.isEmpty && !_sending
                  ? _WelcomeCard(
                      hasKey: hasKey,
                      onOpenMemory: _openMemory,
                      onOpenWorkouts: _openWorkouts,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= messages.length) {
                          return const _ThinkingBubble();
                        }
                        final message = messages[i];
                        return _MessageBubble(message: message);
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: AppText.bodyMuted(color: AppColors.chili),
                ),
              ),
            _Composer(
              controller: _input,
              enabled: hasKey && !_sending,
              hint: hasKey ? 'Ask the coach…' : 'Add your OpenAI key first',
              onSend: () => _send(_input.text),
            ),
          ],
        ),
      ),
    );
  }
}


class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.hasKey,
    required this.onOpenMemory,
    required this.onOpenWorkouts,
  });

  final bool hasKey;
  final VoidCallback onOpenMemory;
  final VoidCallback onOpenWorkouts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      children: [
        const Icon(Icons.auto_awesome_rounded,
            color: AppColors.plantain, size: 30),
        const SizedBox(height: 12),
        Text('Your coach, with your numbers',
            style: AppText.title(), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Ask about your calories, macros, weight trend, streaks — or for '
          'exercise plans. Anything the coach recommends is auto-saved to '
          'your workouts, and it remembers what matters about you.',
          textAlign: TextAlign.center,
          style: AppText.bodyMuted(),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.psychology_outlined,
                  color: AppColors.plantain, size: 16),
              label: const Text('Memory'),
              onPressed: onOpenMemory,
            ),
            ActionChip(
              avatar: const Icon(Icons.fitness_center_outlined,
                  color: AppColors.plantain, size: 16),
              label: const Text('Workouts'),
              onPressed: onOpenWorkouts,
            ),
          ],
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final bg = isUser ? AppColors.jollof : AppColors.barkRaised;
    final fg = isUser ? AppColors.pot : AppColors.bone;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Text(
            message.content,
            style: AppText.body(color: fg),
          ),
        ),
      ),
    );
  }
}


class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('coach is thinking…'),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: AppText.body(),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppText.bodyMuted(),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: enabled ? AppColors.jollof : AppColors.ember,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: enabled ? onSend : null,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.arrow_upward_rounded,
                    color: AppColors.pot, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

