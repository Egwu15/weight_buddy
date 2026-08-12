import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'data/app_database.dart';
import 'data/reminder_service.dart';
import 'providers/providers.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _armDailyReminder();
  runApp(const ProviderScope(child: WeightBuddyApp()));
}

/// Re-arms the daily log reminder from persisted settings. Android does not
/// keep scheduled notifications across reboots, so this runs on every launch.
Future<void> _armDailyReminder() async {
  try {
    final db = await AppDatabase.open();
    final enabled =
        await db.getSetting(AppSettingsController.kReminderEnabled) == 'true';
    final time = await db.getSetting(AppSettingsController.kReminderTime);
    if (!enabled || time == null) {
      await db.close();
      return;
    }
    final parts = time.split(':');
    if (parts.isEmpty) {
      await db.close();
      return;
    }
    final service = ReminderService();
    String? tzName;
    try {
      tzName = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      // Fall back to the plugin default.
    }
    await service.init(timezoneName: tzName);
    await service.scheduleDaily(
      hour: int.tryParse(parts[0]) ?? 20,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    await db.close();
  } catch (_) {
    // Reminders are best-effort at launch; the app must still open.
  }
}

class WeightBuddyApp extends StatelessWidget {
  const WeightBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weight Buddy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
