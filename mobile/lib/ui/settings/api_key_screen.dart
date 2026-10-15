import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// BYOK settings: the user's own OpenAI key (secure vault) and the
/// vocabulary of dish names the transcription should recognize — related
/// voice/AI inputs on one page.
class ApiKeyScreen extends ConsumerStatefulWidget {
  const ApiKeyScreen({super.key});

  @override
  ConsumerState<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends ConsumerState<ApiKeyScreen> {
  final _keyController = TextEditingController();
  final _vocabController = TextEditingController();
  String? _savedKey;
  bool _hydrated = false;
  String? _keyError;
  bool _saving = false;

  @override
  void dispose() {
    _keyController.dispose();
    _vocabController.dispose();
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

  void _replaceKey() {
    setState(() {
      _savedKey = null;
      _keyController.clear();
      _keyError = null;
    });
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
    setState(() {
      _keyError = null;
      _saving = true;
    });
    await ref
        .read(settingsProvider.notifier)
        .save(apiKey: apiKey, vocabulary: vocab);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedKey = apiKey.isEmpty ? null : apiKey;
      _keyController.clear();
    });
    AppToast.show(context, 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    settings.whenOrNull(data: _hydrate);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('OpenAI & voice', style: AppText.headline()),
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
                    child: Text(_maskKey(_savedKey!), style: AppText.dataS()),
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
