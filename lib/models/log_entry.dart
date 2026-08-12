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

  /// Optional extra context for exercise entries (duration, activity name).
  String? get activity => null;

  LogEntry copyWith({int? id}) => LogEntry(
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
