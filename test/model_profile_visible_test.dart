import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/mine_screen.dart';
import 'package:global_overview/screens/model_form_screen.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('新增模型后「我的」列表应立即显示该模型', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cfg = AppConfigService();
    await cfg.init();

    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(FakeDb()),
        appConfigProvider.overrideWith((ref) => cfg),
      ],
      child: MaterialApp(
        routes: {'/model-form': (c) => const ModelFormScreen()},
        home: const MineScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('＋ 新增模型'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'MyTestModel');
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('MyTestModel'), findsWidgets, reason: '新增模型后返回列表应立即显示，无需重启');
  });
}
