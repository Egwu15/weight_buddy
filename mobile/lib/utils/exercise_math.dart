/// Deterministic, non-inflated calorie math for logged exercise — the engine
/// behind every burn figure the app records.
///
/// Short rep-based bodyweight strength is priced by the mechanical work
/// actually performed against gravity (mass × g × displacement × reps),
/// divided by ~22% human muscular efficiency. Time-based activities are
/// priced by a MET value on the precise seconds active. What this never does:
/// round a 45-second set up to a 5-minute block, invent a number, or count
/// resting metabolism as workout effort.
library;

import 'dart:math' as math;

/// Known bodyweight strength movements, each with the vertical displacement
/// of the body's centre of mass per rep (metres) and the fraction of
/// bodyweight actually lifted. Push-ups lift roughly two-thirds of bodyweight
/// (the hands carry the rest); dips and pull-ups lift essentially all of it.
enum BodyweightMovement {
  dips('Dips', displacementM: 0.4, effectiveMassFraction: 1.0),
  pullUps('Pull-ups', displacementM: 0.5, effectiveMassFraction: 1.0),
  pushUps('Push-ups', displacementM: 0.25, effectiveMassFraction: 0.65),
  squats('Squats', displacementM: 0.45, effectiveMassFraction: 1.0),
  lunges('Lunges', displacementM: 0.45, effectiveMassFraction: 1.0);

  const BodyweightMovement(
    this.label, {
    required this.displacementM,
    required this.effectiveMassFraction,
  });

  final String label;

  /// Vertical centre-of-mass displacement per rep, in metres.
  final double displacementM;

  /// Fraction of bodyweight actually lifted.
  final double effectiveMassFraction;

  /// Matches a parsed exercise name to a known movement. Substring matching
  /// on a normalised name, so "Knee press-ups", "Press-ups" and "Push-ups"
  /// all resolve to [pushUps], and "Chin-ups" to [pullUps].
  static BodyweightMovement? fromName(String? name) {
    if (name == null) return null;
    final n = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    if (n.contains('dip')) return dips;
    if (n.contains('pull up') ||
        n.contains('chin up') ||
        n.contains('pullup') ||
        n.contains('chinup')) {
      return pullUps;
    }
    if (n.contains('push up') ||
        n.contains('press up') ||
        n.contains('pushup') ||
        n.contains('pressup')) {
      return pushUps;
    }
    if (n.contains('squat')) return squats;
    if (n.contains('lunge')) return lunges;
    return null;
  }
}

/// Pure calorie math. No I/O — trivially unit-testable, mirroring
/// `CalorieMath` for the daily maintenance target.
abstract final class ExerciseMath {
  /// Acceleration due to gravity (m/s²).
  static const double gravity = 9.81;

  /// Energy in one dietary kilocalorie (Joules).
  static const double joulesPerKcal = 4184.0;

  /// Human muscular efficiency for concentric work, ~20–25%. 22% sits in the
  /// middle of that band. Lowering (eccentric) and static work cost real
  /// energy that this deliberately conservative model does not count.
  static const double muscularEfficiency = 0.22;

  /// Fallback vertical displacement for rep-based movements not in
  /// [BodyweightMovement]: a conservative full-body lift of ~40 cm.
  static const double genericDisplacementM = 0.4;

  /// MET for vigorous calisthenics (Compendium of Physical Activities) — the
  /// duration-based fallback in the spec.
  static const double calisthenicsMet = 8.0;

  /// Sanity cap: a single set of reps is never worth more than this, so a
  /// mis-parsed "200 dips" can never report a workout-sized burn. Matches the
  /// spec's guard — reject ≥ 20 kcal for one set of 20 reps.
  static const double maxKcalPerSet = 20.0;

  /// Mechanical-work calories for a rep-based movement:
  ///
  ///   work (J) = mass × g × displacement × reps
  ///   kcal     = work (J) ÷ (4,184 × 0.22)
  ///
  /// The denominator converts Joules to dietary kcal and divides by muscular
  /// efficiency, so the result is the metabolic cost of the set. Example: 20
  /// dips at 87 kg → 87 × 9.81 × 0.4 × 20 = 6,828 J → ≈ 7.4 kcal.
  static double mechanicalKcal({
    required double weightKg,
    required double displacementM,
    double effectiveMassFraction = 1.0,
    required int reps,
  }) {
    final workJ =
        weightKg * effectiveMassFraction * gravity * displacementM * reps;
    return workJ / (joulesPerKcal * muscularEfficiency);
  }

  /// MET-based calories for a time-based activity, priced on the precise
  /// seconds active — never rounded up to a minimum session block:
  ///
  ///   kcal = MET × 3.5 × weight(kg) ÷ 200 × duration(minutes)
  static double metKcal({
    required double met,
    required double weightKg,
    required double seconds,
  }) => met * 3.5 * weightKg / 200 * (seconds / 60);

  /// The one entry point the app uses: route a parsed exercise to the honest
  /// method. Reps win — mechanical work is the ground truth for strength
  /// work; duration alone is priced by MET on precise minutes. When neither
  /// is known the burn is 0: better honest than invented.
  static double burnForExercise({
    required String name,
    required double weightKg,
    int? sets,
    int? reps,
    double? durationMinutes,
  }) {
    final totalReps = (reps ?? 0) * (sets ?? 1);
    if (totalReps > 0) {
      final movement = BodyweightMovement.fromName(name);
      final kcal = mechanicalKcal(
        weightKg: weightKg,
        displacementM: movement?.displacementM ?? genericDisplacementM,
        effectiveMassFraction: movement?.effectiveMassFraction ?? 1.0,
        reps: totalReps,
      );
      final setsCount = sets == null || sets < 1 ? 1 : sets;
      return math.min(kcal, maxKcalPerSet * setsCount);
    }
    if (durationMinutes != null && durationMinutes > 0) {
      return metKcal(
        met: metForName(name),
        weightKg: weightKg,
        seconds: durationMinutes * 60,
      );
    }
    return 0;
  }

  /// MET for a time-based activity by name. Unknown activities fall back to
  /// vigorous calisthenics (8.0) per the spec; common cardio is mapped from
  /// the Compendium of Physical Activities so duration logging stays honest
  /// in both directions — running is not priced as a walk.
  ///
  /// Order matters: the most specific string wins (a "sprint" contains
  /// "run", a "treadmill run" is still a run).
  static double metForName(String name) {
    final n = name.toLowerCase();
    const rules = <(String, double)>[
      ('sprint', 14.0),
      ('run', 9.8),
      ('jog', 7.0),
      ('walk', 4.3),
      ('cycle', 7.5),
      ('bike', 7.5),
      ('row', 7.0),
      ('swim', 6.0),
      ('elliptic', 5.0),
      ('treadmill', 8.5),
      ('hiit', 8.0),
      ('circuit', 8.0),
      ('crossfit', 8.0),
      ('strength', 8.0),
      ('weights', 8.0),
      ('calisthenic', 8.0),
      ('bodyweight', 8.0),
      ('plank', 3.8),
      ('yoga', 2.5),
      ('stretch', 2.5),
    ];
    for (final (needle, met) in rules) {
      if (n.contains(needle)) return met;
    }
    return calisthenicsMet;
  }
}
