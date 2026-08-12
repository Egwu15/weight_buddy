import 'package:flutter/material.dart';

/// Weight Buddy palette — "the pot and the plate."
///
/// A deep roasted-cocoa night kitchen, lit by the food itself.
/// Every accent is a food color from the West African kitchen the app is
/// built around (jollof, plantain, ugu).
abstract final class AppColors {
  /// Page background — warm brown-black, not neutral near-black.
  static const pot = Color(0xFF221A17);

  /// Raised surface (cards, sheets) — a step above the pot.
  static const bark = Color(0xFF2B211B);

  /// Surface raised once more (inputs, tiles).
  static const barkRaised = Color(0xFF352820);

  /// Hairline separators.
  static const ember = Color(0xFF3C2E25);

  /// Primary text — warm bone white.
  static const bone = Color(0xFFF4EAD9);

  /// Primary accent / action — tomato-pepper red-orange.
  static const jollof = Color(0xFFE85D2F);

  /// Pressed / deep jollof.
  static const jollofDeep = Color(0xFFB8411A);

  /// Secondary accent — plantain gold.
  static const plantain = Color(0xFFF2B53C);

  /// Leafy green — protein, exercise, positive delta.
  static const ugu = Color(0xFF5CA96C);

  /// Muted secondary text.
  static const smoke = Color(0xFFA8937F);

  /// Danger / destructive (delete).
  static const chili = Color(0xFFE0563E);
}
