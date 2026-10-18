import 'package:flutter_test/flutter_test.dart';
import 'package:weight_buddy/utils/app_version.dart';

void main() {
  group('isVersionOlder', () {
    final tests = <(String, String, bool)>[
      ('1.0.4', '1.0.5', true),
      ('1.0.5', '1.0.5', false),
      ('1.0.6', '1.0.5', false),
      ('1.0', '1.0.1', true),
      ('1.0.1', '1.0', false),
      ('1.0.4+7', '1.0.5', true),
      ('1.0.5-beta.1', '1.0.5', false),
      ('2.0.0', '1.99.99', false),
      ('1.0.4', '1.0.4.0', false),
      ('1.0.4', 'not-a-version', false),
    ];
    for (final (current, minimum, want) in tests) {
      test('$current vs $minimum', () {
        expect(isVersionOlder(current, minimum), want);
      });
    }
  });

  test('parseAppVersion rejects non-numeric parts', () {
    expect(parseAppVersion('1.0.4'), [1, 0, 4]);
    expect(parseAppVersion('1.0.x'), isNull);
    expect(parseAppVersion('1..4'), isNull);
    expect(parseAppVersion(''), isNull);
  });
}
