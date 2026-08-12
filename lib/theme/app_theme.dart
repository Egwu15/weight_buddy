import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typographic roles for Weight Buddy.
///
/// The kitchen-scale / ledger idea: every number that matters is a
/// monospace instrument readout (IBM Plex Mono); everything a person reads
/// is set in the warm humanist sans Karla.
abstract final class AppText {
  /// Brand + labels: small mono, uppercase.
  static TextStyle label({Color color = AppColors.smoke}) => GoogleFonts.ibmPlexMono(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
        height: 1.2,
        color: color,
      );

  /// The big calorie readouts — the loudest voice on the dashboard.
  static TextStyle dataXL({Color color = AppColors.bone}) =>
      GoogleFonts.ibmPlexMono(fontSize: 44, fontWeight: FontWeight.w700, height: 1.05, color: color);

  /// Secondary data readouts (net, per-item kcal).
  static TextStyle dataL({Color color = AppColors.bone}) =>
      GoogleFonts.ibmPlexMono(fontSize: 28, fontWeight: FontWeight.w600, height: 1.15, color: color);

  /// Inline data (grams, durations).
  static TextStyle dataM({Color color = AppColors.bone}) =>
      GoogleFonts.ibmPlexMono(fontSize: 18, fontWeight: FontWeight.w600, height: 1.2, color: color);

  /// Small data.
  static TextStyle dataS({Color color = AppColors.bone}) =>
      GoogleFonts.ibmPlexMono(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3, color: color);

  /// Screen headlines.
  static TextStyle headline({Color color = AppColors.bone}) =>
      GoogleFonts.karla(fontSize: 24, fontWeight: FontWeight.w700, height: 1.15, color: color);

  /// Section titles.
  static TextStyle title({Color color = AppColors.bone, double? fontSize}) =>
      GoogleFonts.karla(
          fontSize: fontSize ?? 17,
          fontWeight: FontWeight.w700,
          height: 1.25,
          color: color);

  /// Body copy.
  static TextStyle body({Color color = AppColors.bone}) =>
      GoogleFonts.karla(fontSize: 16, fontWeight: FontWeight.w400, height: 1.45, color: color);

  /// Muted body.
  static TextStyle bodyMuted({Color color = AppColors.smoke, double? fontSize}) =>
      GoogleFonts.karla(
          fontSize: fontSize ?? 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: color);
}

abstract final class AppTheme {
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.pot,
    );

    final scheme = ColorScheme.dark(
      primary: AppColors.jollof,
      onPrimary: AppColors.pot,
      secondary: AppColors.plantain,
      onSecondary: AppColors.pot,
      surface: AppColors.bark,
      onSurface: AppColors.bone,
      surfaceContainerHighest: AppColors.barkRaised,
      onSurfaceVariant: AppColors.smoke,
      error: AppColors.chili,
      onError: AppColors.pot,
      outline: AppColors.ember,
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: AppText.dataXL(),
      headlineMedium: AppText.dataL(),
      titleLarge: AppText.title(),
      titleMedium: AppText.title(fontSize: 15),
      bodyLarge: AppText.body(),
      bodyMedium: AppText.bodyMuted(),
      labelLarge: GoogleFonts.karla(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.bone),
      labelMedium: AppText.label(color: AppColors.smoke),
    );

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      dividerColor: AppColors.ember,
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        color: AppColors.bark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.ember),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.barkRaised,
        hintStyle: AppText.bodyMuted(),
        labelStyle: AppText.label(color: AppColors.smoke),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.ember),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.ember),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.jollof, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.barkRaised,
        contentTextStyle: AppText.body(),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.ember),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bark,
        modalBackgroundColor: AppColors.bark,
        showDragHandle: true,
        dragHandleColor: AppColors.smoke,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.bone,
          textStyle: GoogleFonts.karla(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.jollof,
          foregroundColor: AppColors.pot,
          disabledBackgroundColor: AppColors.ember,
          disabledForegroundColor: AppColors.smoke,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.karla(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.bone),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.jollof,
        linearTrackColor: AppColors.ember,
      ),
    );
  }
}
