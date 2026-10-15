/// Unit conversions for height and weight inputs — shared by the onboarding
/// flow and Settings → Targets so feet/inches always round-trips to the
/// stored centimetres.
library;

/// Conversions around the metric values the app stores internally (height is
/// always cm, weight is always kg). The units are only a display preference.
abstract final class Units {
  static const double _cmPerInch = 2.54;
  static const double _kgPerLb = 0.45359237;

  /// Kilograms from a pounds value.
  static double lbToKg(double lb) => lb * _kgPerLb;

  /// Pounds from a kilograms value.
  static double kgToLb(double kg) => kg / _kgPerLb;

  /// Centimetres from total inches.
  static double inchesToCm(double inches) => inches * _cmPerInch;

  /// Total inches from a centimetre height.
  static double cmToInches(double cm) => cm / _cmPerInch;

  /// The nearest feet/inches pair for a centimetre height (inches 0–11).
  static (int, int) cmToFeetInches(double cm) {
    final total = cmToInches(cm).round();
    return (total ~/ 12, total % 12);
  }

  /// Centimetres from feet + inches.
  static double feetInchesToCm(int feet, int inches) =>
      inchesToCm((feet * 12 + inches).toDouble());
}
