import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backend_auth.dart';
import '../../data/google_signin.dart';
import '../../providers/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'app_toast.dart';

/// The "Continue with Google" prompt, shared by settings and the paywall.
///
/// Signed out, it offers Google sign-in; signed in with Google, it shows the
/// linked state and a sign-out action. Anonymous sessions still work without
/// it — this is always an optional upgrade, never a gate.
class GoogleSignInCard extends ConsumerStatefulWidget {
  const GoogleSignInCard({super.key});

  @override
  ConsumerState<GoogleSignInCard> createState() => _GoogleSignInCardState();
}

class _GoogleSignInCardState extends ConsumerState<GoogleSignInCard> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(settingsProvider.notifier).signInWithGoogle();
      if (mounted) AppToast.show(context, 'Signed in with Google');
    } on GoogleSignInCancelled {
      // The user changed their mind — nothing to report.
    } on BackendAuthException catch (e) {
      if (mounted) AppToast.show(context, e.message);
    } catch (_) {
      if (mounted) AppToast.show(context, 'Google sign-in failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await ref.read(settingsProvider.notifier).signOut();
      if (mounted) AppToast.show(context, 'Signed out');
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not sign out. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final linked = settings?.googleLinked ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.barkRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle_rounded,
                  color: AppColors.plantain, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  linked ? 'Signed in with Google' : 'Continue with Google',
                  style: AppText.title(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            linked
                ? 'Your plan and usage are tied to your Google account.'
                : 'Keep your plan and data if you reinstall or switch phones.',
            style: AppText.bodyMuted(fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (linked)
            TextButton.icon(
              onPressed: _busy ? null : _signOut,
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text(_busy ? 'Signing out…' : 'Sign out'),
              style: TextButton.styleFrom(foregroundColor: AppColors.smoke),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: const Icon(Icons.login_rounded, size: 20),
              label: Text(_busy ? 'Opening Google…' : 'Continue with Google'),
            ),
        ],
      ),
    );
  }
}
