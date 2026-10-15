import 'package:flutter_test/flutter_test.dart';

import 'package:weight_buddy/models/log_entry.dart';
import 'package:weight_buddy/ui/widgets/meal_edit_parts.dart';

void main() {
  const eggs = MealItem(
    name: 'Boiled eggs',
    quantity: '3 eggs',
    calories: 210,
    proteinG: 18,
    carbsG: 3,
    fatG: 15,
  );

  test('scales calories and macros with the typed number', () {
    final c = MealQuantityController(eggs);
    final two = c.scaledTo('2 eggs')!;
    expect(two.calories, closeTo(140, 1e-9));
    expect(two.proteinG, closeTo(12, 1e-9));
    expect(two.quantity, '2 eggs');
    c.dispose();
  });

  test('clearing the field midway does not lose the reference number', () {
    final c = MealQuantityController(eggs);
    final cleared = c.scaledTo('')!;
    expect(cleared.calories, 210);
    expect(c.scaledTo('2')!.calories, closeTo(140, 1e-9));
    c.dispose();
  });

  test('a zero quantity is ignored rather than wiping the item', () {
    final c = MealQuantityController(eggs);
    expect(c.scaledTo('0'), isNull);
    c.dispose();
  });
}
