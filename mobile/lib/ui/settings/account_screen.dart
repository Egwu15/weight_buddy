import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai_service.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// Account & voice settings: the signed-in session, today's remaining AI
/// allowance, and the vocabulary the transcription should recognize. There is
/// no API key here — the AI provider key lives on the backend.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _vocabController = TextEditingController();
  bool _hydrated = false;
  bool _saving = false;

  @override
  void dispose() {
    _vocabController.dispose();
    super.dispose();
  }

  void _hydrate(AppSettings settings) {
    if (_hydrated) return;
    _hydrated = true;
    _vocabController.text = settings.vocabulary;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(settingsProvider.notifier)
        .save(vocabulary: _vocabController.text.trim());
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(context, 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    settings.whenOrNull(data: _hydrate);
    final signedIn = settings.value?.isConfigured ?? false;
    final account = ref.watch(accountProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Account & voice', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Your account', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Weight Buddy signs your device in automatically — no key to '
            'paste. Your AI allowance is managed by the service.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 16),
          _StatusCard(signedIn: signedIn),
          if (!signedIn) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(settingsProvider.notifier).refreshSession(),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Try connecting again'),
            ),
          ],
          const SizedBox(height: 20),
          Text('Today', style: AppText.label()),
          const SizedBox(height: 8),
          account.when(
            data: (info) => info == null
                ? Text('Connect to see your allowance.', style: AppText.bodyMuted())
                : _UsageCard(info: info),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => Text(
              'Couldn\'t load your allowance right now.',
              style: AppText.bodyMuted(color: AppColors.chili),
            ),
          ),
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
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final color = signedIn ? AppColors.jollof : AppColors.plantain;
    final icon = signedIn ? Icons.cloud_done_rounded : Icons.cloud_off_rounded;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              signedIn ? 'Connected' : 'Not connected yet',
              style: AppText.dataS(),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.info});

  final AccountInfo info;

  static const _labels = {
    'transcribe': 'Voice logging',
    'parse': 'Meal & workout parsing',
    'parse_meal': 'Meal parsing',
    'parse_exercise': 'Workout parsing',
    'chat': 'Coach',
    'distill_memories': 'Memory',
    'extract_exercises': 'Workouts',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                info.tier == 'paid' ? 'Premium' : 'Free',
                style: AppText.title(color: AppColors.jollof),
              ),
              const Spacer(),
              Text('left today', style: AppText.bodyMuted(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          for (final usage in info.limits)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _labels[usage.kind] ?? usage.kind,
                      style: AppText.bodyMuted(fontSize: 13),
                    ),
                  ),
                  Text(
                    '${usage.remaining}/${usage.limit}',
                    style: AppText.dataS(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
