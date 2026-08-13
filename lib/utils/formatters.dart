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

  /// A weight readout in kilograms, one decimal. Weights are always stored
  /// and displayed in kg — the kg/lb toggle on the weigh-in sheet is only a
  /// per-entry input convenience.
  static String weight(double kg) => kg.toStringAsFixed(1);

  /// A local date stored in `app_settings` as a stable, sortable ISO-8601
  /// date (`yyyy-MM-dd`).
  static String isoDate(DateTime day) =>
      DateFormat('yyyy-MM-dd').format(day);

  /// The inverse of [isoDate]; null for absent or malformed values.
  static DateTime? parseIsoDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final d = DateFormat('yyyy-MM-dd').parseStrict(raw.trim());
      return DateTime(d.year, d.month, d.day);
    } on FormatException {
      return null;
    }
  }
}
