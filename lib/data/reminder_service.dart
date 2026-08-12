import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily local notifications that nudge the user to log.
///
/// Scheduling is inexact (no exact-alarm permission needed on Android) and
/// re-armed on every app launch, because Android does not persist scheduled
/// notifications across reboots on its own.
class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'daily_log_reminder';
  static const _notificationId = 1001;
  static const _title = 'weightbuddy';

  bool _initialized = false;

  /// Loads timezone data and the plugin. [timezoneName] is the IANA name of
  /// the device's local zone (from flutter_timezone), so reminders fire in
  /// local wall-clock time.
  Future<void> init({String? timezoneName}) async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    if (timezoneName != null && timezoneName.isNotEmpty) {
      try {
        tz.setLocalLocation(tz.getLocation(timezoneName));
      } catch (_) {
        // Fall back to UTC if the name is unknown.
      }
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  /// Asks for notification permission. Returns true when granted.
  Future<bool> requestPermissions() async {
    await _ensureInit();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final androidOk = await android?.requestNotificationsPermission() ?? true;
    final iosOk =
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
            true;
    return androidOk && iosOk;
  }

  /// Schedules a daily reminder at [hour]:[minute] in the device's local
  /// time. Calling again replaces the existing schedule.
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    String message = 'Time to log — what did you eat today?',
  }) async {
    await _ensureInit();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      _notificationId,
      _title,
      message,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Daily log reminder',
          channelDescription: 'Reminds you to log your meals and workouts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel() async {
    await _ensureInit();
    await _plugin.cancel(_notificationId);
  }

  void dispose() {
    // No-op: the plugin is a thin wrapper over platform channels.
  }
}
