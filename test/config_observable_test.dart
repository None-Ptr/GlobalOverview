import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('配置变更会自动重建监听它的界面（无需手动 setState）', (tester) async {
    SharedPreferences.setMockInitialValues({
      'llm_profiles': jsonEncode([
        {'id': 'a', 'name': 'ModelA', 'baseUrl': 'https://a', 'apiKey': 'k', 'model': 'm1'},
        {'id': 'b', 'name': 'ModelB', 'baseUrl': 'https://b', 'apiKey': 'k', 'model': 'm2'},
      ]),
      'llm_current': 'a',
    });
    final cfg = AppConfigService();
    await cfg.init();

    await tester.pumpWidget(ProviderScope(
      overrides: [appConfigProvider.overrideWith((ref) => cfg)],
      child: MaterialApp(
        home: Consumer(
          builder: (c, ref, _) {
            final conf = ref.watch(appConfigProvider);
            return Text('cur:${conf.currentProfileId}', textDirection: TextDirection.ltr);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('cur:a'), findsOneWidget);

    await cfg.setCurrentProfile('b');
    await tester.pumpAndSettle();

    expect(find.text('cur:b'), findsOneWidget, reason: '配置变更应自动通知界面重建，无需手动 setState');
  });
}
