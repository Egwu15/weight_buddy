import 'dart:convert';

/// A meal or an exercise.
enum EntryType {
  meal('meal'),
  exercise('exercise');

  const EntryType(this.apiName);
  final String apiName;

  static EntryType fromApiName(String value) =>
      value == exercise.apiName ? exercise : meal;
}

/// Which meal of the day a food entry belongs to. `meal` is the fallback for
/// legacy rows and defensive parses (and is meaningless for exercises).
enum MealType {
  meal('meal'),
  breakfast('breakfast'),
  lunch('lunch'),
  dinner('dinner'),
  snack('snack');

  const MealType(this.apiName);
  final String apiName;

  static MealType fromApiName(String value) => values.firstWhere(
        (m) => m.apiName == value,
        orElse: () => MealType.meal,
      );
}

/// A single food item parsed out of a spoken meal.
class MealItem {
  const MealItem({
    required this.name,
    required this.quantity,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final String name;
  final String quantity;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
      };

  factory MealItem.fromJson(Map<String, dynamic> json) => MealItem(
        name: (json['name'] ?? '').toString(),
        quantity: (json['quantity'] ?? '').toString(),
        calories: (json['calories'] as num?)?.toDouble() ?? 0,
        proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      );
}

/// One row in the local log — a meal or an exercise.
class LogEntry {
  const LogEntry({
    this.id,
    required this.timestamp,
    required this.type,
    required this.summary,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.rawTranscript,
    this.items = const [],
    this.mealType = MealType.meal,
    this.sets,
    this.reps,
    this.durationMinutes,
  });

  final int? id;

  /// UTC millis since epoch.
  final int timestamp;
  final EntryType type;

  /// Short human summary, e.g. "Jollof rice with 2 pieces fried chicken".
  final String summary;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// The raw transcript the entry was parsed from.
  final String rawTranscript;

  /// Parsed food items (meals only).
  final List<MealItem> items;

  /// Which meal of the day this is (breakfast/lunch/dinner/snack). `meal`
  /// means unknown/legacy; exercises always use the default.
  final MealType mealType;

  /// Optional structured exercise context: sets × reps for strength work and
  /// duration in minutes for time-based activities. Null for meals and legacy
  /// rows.
  final int? sets;
  final int? reps;
  final double? durationMinutes;

  /// Optional extra context for exercise entries (duration, activity name).
  String? get activity => null;

  LogEntry copyWith({
    int? id,
    int? sets,
    int? reps,
    double? durationMinutes,
  }) =>
      LogEntry(
        id: id ?? this.id,
        timestamp: timestamp,
        type: type,
        summary: summary,
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        rawTranscript: rawTranscript,
        items: items,
        mealType: mealType,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        durationMinutes: durationMinutes ?? this.durationMinutes,
      );

  Map<String, Object?> toMap() => {
        'timestamp': timestamp,
        'type': type.apiName,
        'summary': summary,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'raw_transcript': rawTranscript,
        'items': jsonEncode(items.map((i) => i.toJson()).toList()),
        'meal_type': mealType.apiName,
        'sets': sets,
        'reps': reps,
        'duration_minutes': durationMinutes,
      };

  factory LogEntry.fromMap(Map<String, Object?> map) {
    final itemsRaw = map['items'] as String?;
    List<MealItem> items = const [];
    if (itemsRaw != null && itemsRaw.isNotEmpty) {
      try {
        items = (jsonDecode(itemsRaw) as List)
            .map((e) => MealItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        items = const [];
      }
    }
    return LogEntry(
      id: map['id'] as int?,
      timestamp: (map['timestamp'] as num).toInt(),
      type: EntryType.fromApiName((map['type'] as String?) ?? 'meal'),
      summary: (map['summary'] as String?) ?? '',
      calories: ((map['calories'] as num?) ?? 0).toDouble(),
      proteinG: ((map['protein_g'] as num?) ?? 0).toDouble(),
      carbsG: ((map['carbs_g'] as num?) ?? 0).toDouble(),
      fatG: ((map['fat_g'] as num?) ?? 0).toDouble(),
      rawTranscript: (map['raw_transcript'] as String?) ?? '',
      items: items,
      mealType:
          MealType.fromApiName((map['meal_type'] as String?) ?? 'meal'),
      sets: (map['sets'] as num?)?.toInt(),
      reps: (map['reps'] as num?)?.toInt(),
      durationMinutes: (map['duration_minutes'] as num?)?.toDouble(),
    );
  }
}

/// Aggregates for one day.
class LogTotals {
  const LogTotals({
    this.eatenKcal = 0,
    this.burnedKcal = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
  });

  final double eatenKcal;
  final double burnedKcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  double get netKcal => eatenKcal - burnedKcal;

  factory LogTotals.fromEntries(Iterable<LogEntry> entries) {
    var eaten = 0.0, burned = 0.0, p = 0.0, c = 0.0, f = 0.0;
    for (final e in entries) {
      if (e.type == EntryType.meal) {
        eaten += e.calories;
        p += e.proteinG;
        c += e.carbsG;
        f += e.fatG;
      } else {
        burned += e.calories;
      }
    }
    return LogTotals(
      eatenKcal: eaten,
      burnedKcal: burned,
      proteinG: p,
      carbsG: c,
      fatG: f,
    );
  }

  LogTotals operator +(LogTotals other) => LogTotals(
        eatenKcal: eatenKcal + other.eatenKcal,
        burnedKcal: burnedKcal + other.burnedKcal,
        proteinG: proteinG + other.proteinG,
        carbsG: carbsG + other.carbsG,
        fatG: fatG + other.fatG,
      );
}

/// Aggregates for a whole period — a week or a month — pairing the ledger
/// totals with the maintenance budget that period carries.
///
/// For the **ongoing period** (the one containing today) the budget covers
/// only the days from today to the period's end: untracked earlier days count
/// for nothing, and any overspend on tracked days before today carries forward
/// (clamped at zero — under-eating never banks). LEFT then answers "how many
/// calories do I have left from today to the end of the period?" without late
/// sign-ins or skipped days inflating it. Past periods keep the full-period
/// ledger for review.
class PeriodTotals {
  const PeriodTotals({
    required this.totals,
    required this.budgetKcal,
    this.overageKcal = 0,
    this.fromToday = false,
  });

  final LogTotals totals;

  /// Sum of the daily maintenance target over the days this period's budget
  /// covers — every day for past/future periods, today → period end for the
  /// ongoing one.
  final double budgetKcal;

  /// Overspend carried in from tracked days before today in the ongoing
  /// period, clamped at zero. Always zero for past and future periods.
  final double overageKcal;

  /// True when the period contains today and the budget therefore runs from
  /// today to the period's end instead of covering the whole period.
  final bool fromToday;

  /// What's left of the period's budget: budget − net over the covered days,
  /// minus any carried overspend.
  double get leftKcal => budgetKcal - totals.netKcal - overageKcal;
}
