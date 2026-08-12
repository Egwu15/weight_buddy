import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
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

  Widget _tabs() {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TodayScreen(
            onOpenSettings: () => setState(() => _index = 3),
            onOpenMonth: () => setState(() => _index = 1),
          ),
          MonthScreen(
            onSelectDay: (day) {
              ref.read(selectedDayProvider.notifier).setDay(day);
              setState(() => _index = 0);
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
        onDestinationSelected: (i) => setState(() => _index = i),
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
