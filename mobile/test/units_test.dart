import 'package:flutter_test/flutter_test.dart';

import 'package:weight_buddy/utils/units.dart';

void main() {
  test('pounds convert to kilograms and back', () {
    expect(Units.lbToKg(154.3), closeTo(70, 0.1));
    expect(Units.kgToLb(70), closeTo(154.32, 0.1));
  });

  test('feet and inches convert to centimetres', () {
    expect(Units.feetInchesToCm(5, 9), closeTo(175.26, 0.01));
    expect(Units.feetInchesToCm(6, 0), closeTo(182.88, 0.01));
    expect(Units.inchesToCm(69), closeTo(175.26, 0.01));
  });

  test('centimetres convert back to feet and inches', () {
    expect(Units.cmToFeetInches(175.26), (5, 9));
    expect(Units.cmToFeetInches(182.88), (6, 0));
    expect(Units.cmToFeetInches(152.4), (5, 0));
  });

  test('round-trip is lossless enough for the estimate', () {
    const cm = 175.26;
    final (feet, inches) = Units.cmToFeetInches(cm);
    expect(Units.feetInchesToCm(feet, inches), closeTo(cm, 0.001));
  });
}
