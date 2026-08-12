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

  /// A half-open local-day range [start, end) read as
  /// "Mon 4 Aug – Sun 10 Aug" (or "28 Jul – 2 Aug" across months).
  static String range(DateTime start, DateTime endExclusive) {
    final end = endExclusive.subtract(const Duration(days: 1));
    if (start.year == end.year && start.month == end.month) {
      return '${DateFormat('d').format(start)} – ${DateFormat('d MMM').format(end)}';
    }
    return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
  }

  static String fullDate(DateTime day) =>
      DateFormat('EEEE, d MMMM yyyy').format(day);

  /// A weight readout in the active unit (kg | lb), one decimal.
  static String weight(double kg, String unit) {
    if (unit == 'lb') return (kg * 2.2046226218).toStringAsFixed(1);
    return kg.toStringAsFixed(1);
  }
}
