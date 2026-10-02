import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/app.dart';
import 'package:global_overview/providers/providers.dart';

import 'fake_db.dart';

void main() {
  testWidgets('app builds', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(FakeDb())],
      child: const MyApp(),
    ));
    expect(find.byType(MyApp), findsOneWidget);
  });
}
