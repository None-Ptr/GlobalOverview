import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/mine_screen.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('我的页在深色主题下使用深色 Token', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(FakeDb())],
        child: MaterialApp(
          theme: V4Theme.light(),
          darkTheme: V4Theme.dark(),
          themeMode: ThemeMode.dark,
          home: const V4MineScreen(profile: V4Profile(completed: true)),
        ),
      ),
    );
    await tester.pump();

    final title = tester.widget<Text>(find.text('我的'));
    expect(title.style?.color, V4Colors.inkDark);

    final summary = tester.widget<Text>(find.text('高中  课内提升'));
    expect(summary.style?.color, V4Colors.inkDark);

    final note = tester.widget<Text>(find.text('每日 20 分钟'));
    expect(note.style?.color, V4Colors.inkMutedDark);

    expect(tester.takeException(), isNull);
  });
}
