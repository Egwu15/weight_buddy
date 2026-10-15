/// A single weigh-in record.
///
/// [date] is a local midnight `DateTime`; it is stored as UTC millis since
/// epoch, the same convention the `logs` timestamps use.
class WeighIn {
  const WeighIn({
    this.id,
    required this.date,
    required this.weightKg,
    this.note = '',
  });

  final int? id;
  final DateTime date;
  final double weightKg;
  final String note;

  Map<String, Object?> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'weight_kg': weightKg,
        'note': note,
      };

  factory WeighIn.fromMap(Map<String, Object?> map) => WeighIn(
        id: map['id'] as int?,
        date: DateTime.fromMillisecondsSinceEpoch((map['date'] as num).toInt()),
        weightKg: ((map['weight_kg'] as num?) ?? 0).toDouble(),
        note: (map['note'] as String?) ?? '',
      );

  WeighIn copyWith({int? id}) => WeighIn(
        id: id ?? this.id,
        date: date,
        weightKg: weightKg,
        note: note,
      );
}
