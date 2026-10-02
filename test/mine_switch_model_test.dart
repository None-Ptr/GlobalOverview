import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/mine_screen.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('「我的」点选模型即可切换当前使用的大模型', (tester) async {
    SharedPreferences.setMockInitialValues({
      'llm_profiles': jsonEncode([
        {'id': 'a', 'name': 'ModelA', 'baseUrl': 'https://a', 'apiKey': 'k1', 'model': 'm1'},
        {'id': 'b', 'name': 'ModelB', 'baseUrl': 'https://b', 'apiKey': 'k2', 'model': 'm2'},
      ]),
      'llm_current': 'a',
    });
    final cfg = AppConfigService();
    await cfg.init();

    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(FakeDb()),
        appConfigProvider.overrideWith((ref) => cfg),
      ],
      child: const MaterialApp(home: MineScreen()),
    ));
    await tester.pumpAndSettle();

    expect(cfg.currentProfileId, 'a');
    expect(find.text('使用中'), findsOneWidget, reason: '初始仅一个使用中的模型');

    await tester.tap(find.text('ModelB'));
    await tester.pumpAndSettle();

    expect(cfg.currentProfileId, 'b', reason: '点选模型后应切换为当前使用');
    expect(find.text('使用中'), findsOneWidget, reason: '「使用中」标记应唯一且随切换移动');
  });
}
