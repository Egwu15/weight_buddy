import 'package:intl/intl.dart';

/// Presentation helpers — the ledger reads with no decimals,
/// dates read as "Sat, 12 Jul".
abstract final class Formatters {
  static final NumberFormat _int = NumberFormat.decimalPattern();

  static String kcal(num value) => _int.format(value.round());

  static String grams(num value) {
    if (value == value.roundToDouble()) {
      return _int.format(value.toInt());
    }
    return value.toStringAsFixed(1);
  }

  static String timeOfDay(int timestampMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
    return DateFormat('HH:mm').format(d);
  }

  static String dayHeader(DateTime day) =>
      DateFormat('EEE, d MMM').format(day);

  static String fullDate(DateTime day) =>
      DateFormat('EEEE, d MMMM yyyy').format(day);

  /// A weight readout in the active unit (kg | lb), one decimal.
  static String weight(double kg, String unit) {
    if (unit == 'lb') return (kg * 2.2046226218).toStringAsFixed(1);
    return kg.toStringAsFixed(1);
  }
}
