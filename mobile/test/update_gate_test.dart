import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weight_buddy/data/app_update.dart';
import 'package:weight_buddy/providers/providers.dart';
import 'package:weight_buddy/ui/update_gate.dart';

AppUpdateService _service(Map<String, Object?> body) {
  return AppUpdateService(
    baseUrl: 'https://api.test',
    client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String version,
  required AppUpdateService service,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionProvider.overrideWith((ref) => version),
        appUpdateServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: UpdateGate(child: Text('app content'))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('blocks an outdated install', (tester) async {
    await _pump(
      tester,
      version: '1.0.4',
      service: _service({
        'minimum_version': '1.0.5',
        'store_url':
            'https://play.google.com/store/apps/details?id=com.tedif.weight_buddy',
        'message': 'Please update to continue.',
      }),
    );

    expect(find.text('Update to keep going'), findsOneWidget);
    expect(find.text('app content'), findsNothing);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('allows a supported install', (tester) async {
    await _pump(
      tester,
      version: '1.0.5',
      service: _service({
        'minimum_version': '1.0.5',
        'store_url':
            'https://play.google.com/store/apps/details?id=com.tedif.weight_buddy',
        'message': 'Please update to continue.',
      }),
    );

    expect(find.text('app content'), findsOneWidget);
    expect(find.text('Update to keep going'), findsNothing);
  });

  testWidgets('fits a small screen without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      version: '1.0.4',
      service: _service({
        'minimum_version': '1.0.5',
        'store_url':
            'https://play.google.com/store/apps/details?id=com.tedif.weight_buddy',
        'message': 'Please update to continue.',
      }),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('fails open when the check is unavailable', (tester) async {
    final service = AppUpdateService(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => http.Response('offline', 500)),
    );
    await _pump(tester, version: '1.0.4', service: service);

    expect(find.text('app content'), findsOneWidget);
  });
}
