import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/mine_screen.dart';
import 'package:global_overview/services/update_controller.dart';
import 'package:global_overview/services/update_service.dart';
import 'package:global_overview/widgets/go_update_sheet.dart';

import 'fake_db.dart';

const _apkUrl = 'https://github.com/None-Ptr/GlobalOverview/releases/latest/download/GlobalOverview.apk';

UpdateInfo _info({String notes = '修了几个 bug'}) => UpdateInfo(
      version: '3.6.0',
      versionCode: 360,
      url: _apkUrl,
      sha256: 'a' * 64,
      size: 62 * 1024 * 1024,
      notes: notes,
    );

Future<void> _openSheet(WidgetTester tester, UpdateController c) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(onPressed: () => showGoUpdateSheet(ctx, c), child: const Text('open')),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('「我的」页有检查更新入口，且初始显示当前版本', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(FakeDb())],
      child: const MaterialApp(home: MineScreen()),
    ));
    await tester.pumpAndSettle();

    final row = find.text('检查更新');
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    final c = ProviderScope.containerOf(tester.element(find.byType(MineScreen))).read(updateProvider);
    expect(
      find.text(c.installedLabel.isEmpty ? '当前版本' : '当前 ${c.installedLabel}'),
      findsOneWidget,
    );
  });

  testWidgets('更新卡片：有版本对比、包大小与三档按钮', (tester) async {
    final c = UpdateController(UpdateService())
      ..installedLabel = 'v3.5.0'
      ..info = _info()
      ..phase = UpdatePhase.available;
    await _openSheet(tester, c);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v3.6.0'), findsWidgets);
    expect(find.text('v3.5.0'), findsOneWidget);
    expect(find.text('62.0 MB'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('跳过此版本'), findsOneWidget);
  });

  testWidgets('更新说明不限长：超长纯文本走滚动，不撑爆布局', (tester) async {
    final c = UpdateController(UpdateService())
      ..installedLabel = 'v3.5.0'
      ..info = _info(notes: List.generate(300, (i) => '第 $i 行更新说明').join('\n'))
      ..phase = UpdatePhase.available;
    await _openSheet(tester, c);

    expect(tester.takeException(), isNull, reason: '超长说明不该 RenderFlex overflow');
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.textContaining('第 299 行'), findsOneWidget);
  });

  testWidgets('下载中显示百分比与已下载大小，校验中改文案', (tester) async {
    final c = UpdateController(UpdateService())
      ..installedLabel = 'v3.5.0'
      ..info = _info()
      ..phase = UpdatePhase.downloading
      ..total = 62 * 1024 * 1024
      ..received = 31 * 1024 * 1024;
    await _openSheet(tester, c);

    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('/ 62.0 MB'), findsOneWidget);

    c.phase = UpdatePhase.verifying;
    c.notifyListeners();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('正在校验安装包…'), findsOneWidget);
  });

  testWidgets('失败态给出原因与重试；跳过此版本后状态回到 idle', (tester) async {
    final c = UpdateController(UpdateService())
      ..installedLabel = 'v3.5.0'
      ..info = _info()
      ..phase = UpdatePhase.failed
      ..error = '安装包校验未通过，已丢弃（可换个线路重试）';
    await _openSheet(tester, c);

    expect(find.textContaining('校验未通过'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    c.phase = UpdatePhase.available;
    c.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();
    expect(c.phase, UpdatePhase.idle, reason: '跳过 = 忽略该 versionCode');
  });
}
