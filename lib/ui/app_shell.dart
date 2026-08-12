import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import 'coach/coach_screen.dart';
import 'month/month_screen.dart';
import 'settings/settings_screen.dart';
import 'today/today_screen.dart';

/// Four destinations: Today, Month, Coach and Settings. The recorder lives
/// in Today's dock.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TodayScreen(
            onOpenSettings: () => setState(() => _index = 3),
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
