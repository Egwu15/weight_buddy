import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup_service.dart';
import '../../data/secure_settings.dart';
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
  /// Set while an export or import is running, so the buttons disable and the
  /// user cannot start a second one over the top of a half-finished restore.
  bool _busy = false;

  /// Writes the whole database to a JSON file and opens the share sheet, so
  /// the backup can leave the device (Drive, email, another phone). Nothing
  /// is uploaded by the app itself — where it goes is the user's choice.
  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final db = await ref.read(databaseProvider.future);
      final backup = await BackupService.export(db);
      // The file is a plaintext copy of the user's health and chat data, so
      // keep at most one on disk. It can't be deleted straight after sharing:
      // the receiving app (Drive, email) may still be reading it.
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/backups');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create();
      final file = File('${dir.path}/${BackupService.filename()}');
      await file.writeAsString(BackupService.encode(backup));
      final count = BackupService.recordCount(backup);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Weight Buddy backup',
          text: '$count records — keep this file somewhere safe.',
        ),
      );
      if (!mounted) return;
      AppToast.show(context, 'Exported $count records');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Restores a backup file, replacing everything currently stored. Parsing
  /// and validation happen before the confirmation prompt, so a wrong file is
  /// rejected without the user having agreed to a wipe first.
  Future<void> _import() async {
    if (_busy) return;
    // Claimed before the picker opens: a double tap would otherwise start a
    // second picker (or a second restore) while the first is still running.
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty || !mounted) return;

      final chosen = picked.files.single;
      final bytes = chosen.bytes;
      final path = chosen.path;
      final String text;
      if (bytes != null) {
        text = utf8.decode(bytes, allowMalformed: true);
      } else if (path != null) {
        text = await File(path).readAsString();
      } else {
        AppToast.show(context, 'Could not read that file');
        return;
      }

      final Map<String, dynamic> backup;
      try {
        backup = BackupService.parse(text);
      } on BackupException catch (e) {
        if (!mounted) return;
        AppToast.show(context, e.message);
        return;
      }
      final count = BackupService.recordCount(backup);
      final exportedAt = backup['exported_at'];

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.bark,
          title: const Text('Restore this backup?'),
          content: Text(
              'This will replace everything currently in the app with the '
              '$count records in this file'
              '${exportedAt is String ? ', exported ${exportedAt.split('T').first}' : ''}. '
              'Your current entries can’t be recovered afterwards. '
              'Your account sign-in is not part of a backup and stays as it is.'),
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
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final db = await ref.read(databaseProvider.future);
      final skipped = await BackupService.import(db, backup);
      await ref.read(refreshAfterDataReplacedProvider)(db: db);
      if (!mounted) return;
      AppToast.show(
        context,
        skipped == 0
            ? 'Restored $count records'
            : 'Restored, but $skipped unreadable rows were skipped',
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bark,
        title: const Text('Reset the app?'),
        content: const Text(
            'Every meal, workout, weigh-in, chat, memory and saved workout '
            'will be removed, and your profile and account sign-in will be cleared. '
            'You’ll go through onboarding again, like a brand-new install. '
            'This can’t be undone.'),
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
            child: const Text('Reset app'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = await ref.read(databaseProvider.future);
    await db.wipeAllData();
    // Clear the platform secrets too, so the coach starts unconfigured.
    // Best-effort: a secure-store failure must never block the reset.
    try {
      await SecureSettings().clear();
    } catch (_) {}
    // The shell watches app settings and flips back to the onboarding
    // questionnaire once the profile flag is gone; the reminder, reset to
    // off, gets cancelled.
    await ref.read(refreshAfterDataReplacedProvider)(db: db);
    if (!mounted) return;
    AppToast.show(context, 'App reset — fresh install, welcome back');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Fills the app with a realistic “busy week” so the screens can be
  /// reviewed without real logging. Wipes the current records first; the
  /// account sign-in and targets are kept. Debug-only affordance.
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
            'saved workouts. Your account sign-in and targets are kept.'),
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
    // The wipe clears settings too now; hold onto the profile/targets and
    // restore them so the demo only replaces records, as promised above.
    final settingsBefore = await ref.read(appSettingsProvider.future);
    await db.wipeAllData();
    await ref.read(appSettingsProvider.notifier).save(settingsBefore);
    await seedDemoData(db, force: true);
    await ref.read(refreshAfterDataReplacedProvider)(db: db);
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
            'you want a clean slate — it resets the app to a fresh install.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 20),
          Text('Backup', style: AppText.label()),
          const SizedBox(height: 8),
          Text(
            'Export writes everything to a file you can keep or move to '
            'another phone. Import replaces what’s in the app with a backup '
            'file. Your account sign-in isn’t included — you’ll be signed in '
            'automatically after a restore.',
            style: AppText.bodyMuted(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _export,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.plantain,
                    side: const BorderSide(color: AppColors.plantain),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  label: const Text('Export'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _import,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.plantain,
                    side: const BorderSide(color: AppColors.plantain),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text('Import'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Danger zone', style: AppText.label()),
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
            onPressed: _busy ? null : _deleteAll,
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
