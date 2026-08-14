import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import 'widgets/app_toast.dart';
import 'onboarding/onboarding_screen.dart';
import 'coach/coach_screen.dart';
import 'month/month_screen.dart';
import 'settings/settings_screen.dart';
import 'today/today_screen.dart';

/// Four destinations: Today, Month, Coach and Settings. The recorder lives
/// in Today's dock. On a brand-new install the first-run onboarding screen is
/// shown instead of the tabs until the profile has been completed.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  /// When the user last pressed back on the Today tab, used to arm the
  /// two-tap "press back again to exit" grace period. Null when not armed.
  DateTime? _lastBackAt;

  /// How long the "press back again to exit" toast stays armed.
  static const _exitGrace = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check the nudge whenever the app comes back: today's logs may
      // have changed or the calendar may have rolled over while backgrounded.
      ref.read(nowProvider.notifier).refresh();
      ref.read(rearmDailyReminderProvider)();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) {
      // First frame of a cold start — settings are still loading.
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!settings.profileCompleted) {
      // Brand-new install: collect the profile before showing the tabs.
      return const OnboardingScreen();
    }
    return _tabs();
  }

  /// Switches tab and resets the back-to-exit grace period — a deliberate
  /// navigation should never count as part of a double-back.
  void _selectTab(int index) {
    _lastBackAt = null;
    setState(() => _index = index);
  }

  /// The shell is the app's root route, so without interception the Android
  /// back button would close the app from any tab. Intercept it: back first
  /// returns to the Today tab; a second back on Today inside the grace window
  /// exits for real. Detail screens and bottom sheets sit on routes above this
  /// one, so their own back handling still runs first.
  void _onBackInvoked(bool didPop) {
    if (didPop) return;
    if (_index != 0) {
      _selectTab(0);
      return;
    }
    final now = clock.now();
    final last = _lastBackAt;
    if (last != null && now.difference(last) < _exitGrace) {
      // Second press inside the grace window: leave the app for real.
      _lastBackAt = null;
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    AppToast.show(context, 'Press back again to exit');
  }

  Widget _tabs() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBackInvoked(didPop),
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            TodayScreen(
              onOpenSettings: () => _selectTab(3),
              onOpenMonth: () => _selectTab(1),
            ),
            MonthScreen(
              onSelectDay: (day) {
                ref.read(selectedDayProvider.notifier).setDay(day);
                _selectTab(0);
              },
            ),
            const CoachScreen(),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: AppColors.bark,
          indicatorColor: AppColors.jollof.withValues(alpha: 0.16),
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: [
            _destination(0, Icons.bolt_outlined, Icons.bolt_rounded, 'Today'),
            _destination(
                1, Icons.calendar_month_outlined, Icons.calendar_month, 'Month'),
            _destination(2, Icons.auto_awesome_outlined,
                Icons.auto_awesome_rounded, 'Coach'),
            _destination(
                3, Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
          ],
        ),
      ),
    );
  }

  NavigationDestination _destination(
      int index, IconData icon, IconData selectedIcon, String label) {
    return NavigationDestination(
      icon: Icon(icon, color: _index == index ? AppColors.jollof : AppColors.smoke),
      selectedIcon: Icon(selectedIcon, color: AppColors.jollof),
      label: label,
    );
  }
}
