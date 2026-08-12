import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'api_key_screen.dart';
import 'data_screen.dart';
import 'reminder_screen.dart';
import 'targets_screen.dart';

/// Settings hub: a short menu that fans out to focused pages — OpenAI & voice,
/// targets & profile, the daily reminder, and data. Each concern gets its own
/// screen so the top level stays scannable.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings', style: AppText.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _SectionLabel('OPENAI & VOICE'),
          _SettingsTile(
            icon: Icons.key_rounded,
            title: 'OpenAI API key',
            subtitle: 'Your key and the foods it should recognize',
            onTap: () => _open(context, const ApiKeyScreen()),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('YOUR PLAN'),
          _SettingsTile(
            icon: Icons.insights_rounded,
            title: 'Targets & profile',
            subtitle: 'Maintenance, units, height, age, sex, activity',
            onTap: () => _open(context, const TargetsScreen()),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.notifications_none_rounded,
            title: 'Daily reminder',
            subtitle: 'A nudge to log when the day has gaps',
            onTap: () => _open(context, const ReminderScreen()),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('YOUR DATA'),
          _SettingsTile(
            icon: Icons.folder_open_rounded,
            title: 'Data',
            subtitle: 'Everything lives on this device — delete or demo',
            onTap: () => _open(context, const DataScreen()),
          ),
          const _VersionFooter(),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(label, style: AppText.label()),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.ember),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.barkRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.plantain, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.body()),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.bodyMuted(fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.smoke, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// The installed app version, shown as a quiet footer under the menu.
class _VersionFooter extends StatefulWidget {
  const _VersionFooter();

  @override
  State<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<_VersionFooter> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? label;
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version;
      final build = info.buildNumber;
      label = build.isEmpty ? version : '$version ($build)';
    } catch (_) {
      // No platform info (e.g. widget tests) — just show the app name.
      label = null;
    }
    if (!mounted) return;
    setState(() => _label = label);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Text(
        _label == null ? 'Weight Buddy' : 'Weight Buddy v$_label',
        textAlign: TextAlign.center,
        style: AppText.bodyMuted(fontSize: 12),
      ),
    );
  }
}
