import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// A brief, top-anchored toast — the app's replacement for bottom snackbars.
///
/// Rendered into the root overlay so it works from any screen, dialog or
/// bottom sheet, and stays out of the way of the record dock. Only one toast
/// is visible at a time; showing a new one replaces the current.
class AppToast {
  AppToast._();

  static const _hold = Duration(milliseconds: 2200);
  static const _holdWithAction = Duration(milliseconds: 3600);

  static OverlayEntry? _current;

  /// Shows [message] pinned to the top of the screen for a moment. An optional
  /// [actionLabel] / [onAction] pair adds a tappable action next to the text.
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    hide();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _ToastBanner(
              message: message,
              actionLabel: actionLabel,
              onAction: onAction,
              hold: actionLabel != null ? _holdWithAction : _hold,
              onDismissed: () {
                if (entry.mounted) entry.remove();
                if (identical(_current, entry)) _current = null;
              },
            ),
          ),
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Removes the current toast, if any.
  static void hide() {
    final current = _current;
    _current = null;
    if (current != null && current.mounted) current.remove();
  }
}

class _ToastBanner extends StatefulWidget {
  const _ToastBanner({
    required this.message,
    required this.hold,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final Duration hold;
  final VoidCallback onDismissed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastBanner> createState() => _ToastBannerState();
}

class _ToastBannerState extends State<_ToastBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _slide = Tween(begin: const Offset(0, -0.6), end: Offset.zero)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_controller);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _holdTimer = Timer(widget.hold, _dismiss);
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: AppColors.barkRaised,
          elevation: 8,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.ember),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.plantain, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.message,
                    style: AppText.bodyMuted(color: AppColors.bone, fontSize: 13),
                  ),
                ),
                if (widget.actionLabel != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      widget.onAction?.call();
                      _dismiss();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.plantain,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      widget.actionLabel!,
                      style: AppText.label(color: AppColors.plantain),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
