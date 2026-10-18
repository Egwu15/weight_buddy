import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_update.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/app_version.dart';
import '../utils/external_links.dart';

class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  AppUpdate? _update;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final result = await ref.read(appUpdateServiceProvider).fetch();
      if (!mounted || result == null) return;
      setState(() => _update = result);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(appVersionProvider).value;
    final update = _update;
    if (version != null &&
        update != null &&
        isVersionOlder(version, update.minimumVersion)) {
      return UpdateRequiredScreen(currentVersion: version, update: update);
    }
    return widget.child;
  }
}

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.update,
  });

  final String currentVersion;
  final AppUpdate update;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _openStore() async {
    setState(() {
      _opening = true;
      _failed = false;
    });
    final opened = await openExternalLink(widget.update.storeUrl);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.pot,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _WaveMark(),
                const SizedBox(height: 32),
                Text(
                  'Update to keep going',
                  style: AppText.headline().copyWith(fontSize: 32),
                ),
                const SizedBox(height: 14),
                Text(widget.update.message, style: AppText.body()),
                const SizedBox(height: 14),
                Text(
                  'You are on version ${widget.currentVersion}. '
                  'Weight Buddy now requires ${widget.update.minimumVersion} or newer.',
                  style: AppText.bodyMuted(),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _opening ? null : _openStore,
                    icon: _opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 20),
                    label: Text(
                      _opening ? 'Opening Google Play' : 'Update now',
                    ),
                  ),
                ),
                if (_failed) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Could not open Google Play. Try again.',
                    style: AppText.bodyMuted(color: AppColors.chili),
                  ),
                ],
                const SizedBox(height: 40),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: AppColors.smoke,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your log stays on this phone.',
                        style: AppText.bodyMuted(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveMark extends StatelessWidget {
  const _WaveMark();

  static const _bars = [
    (22.0, AppColors.jollofDeep),
    (40.0, AppColors.jollof),
    (58.0, AppColors.plantain),
    (40.0, AppColors.jollof),
    (22.0, AppColors.jollofDeep),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final bar in _bars) ...[
          Container(
            width: 10,
            height: bar.$1,
            decoration: BoxDecoration(
              color: bar.$2,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          if (bar != _bars.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
