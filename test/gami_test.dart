import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/services/habit_service.dart';

import 'fake_db.dart';

/// 相对今天 n 天前的日期串（用于构造历史 days）。
String _d(int ago) => HabitService.ymd(DateTime.now().subtract(Duration(days: ago)));

/// 持久化 kv 的假库（见闻系统全部落在 habit_gami 这个 JSON blob 上）。
class _MemDb extends FakeDb {
  final Map<String, String> kv;
  _MemDb([Map<String, String>? init]) : kv = {...?init};

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    if (sql.contains('FROM kv') && params != null && params.isNotEmpty) {
      final v = kv[params.first];
      return v == null ? [] : [<String, dynamic>{'value': v}];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    if (sql.contains('INSERT OR REPLACE INTO kv') && params != null && params.length >= 2) {
      kv['${params[0]}'] = '${params[1]}';
    }
  }
}

void main() {
  test('读完文章 +30，同日同 guid 不重复给分', () async {
    final svc = HabitService(_MemDb());
    expect(await svc.awardRead('g1'), isTrue);
    expect(await svc.awardRead('g1'), isFalse, reason: '同一篇同一天只计一次');
    final st = await svc.getState();
    // 读 +30 + 每日任务“读 1 篇”奖励 +10 = 40
    expect(st.todayXp, 40);
  });

  test('未达标目标高时，交卷 +20（满分再 +10）+ 任务奖励', () async {
    final svc = HabitService(_MemDb());
    await svc.setGoal(999);
    await svc.recordCompletion(correct: 4, done: 5); // +20 + 任务(测验)10
    var st = await svc.getState();
    expect(st.todayXp, 30);

    final svc2 = HabitService(_MemDb());
    await svc2.setGoal(999);
    await svc2.recordCompletion(correct: 5, done: 5); // +20 +10(满分) + 任务10
    st = await svc2.getState();
    expect(st.todayXp, 40);
  });

  test('当日首次达标一次性 +50', () async {
    final svc = HabitService(_MemDb());
    await svc.setGoal(30);
    await svc.awardRead('g1'); // 读30 → 达标 → +50；再加任务10
    final st = await svc.getState();
    expect(st.todayXp, 90);
    expect(st.isTodayDone, isTrue);
  });

  test('复习词 +2，每日封顶 20 个', () async {
    final svc = HabitService(_MemDb());
    await svc.setGoal(999);
    for (var i = 0; i < 25; i++) {
      await svc.awardVocabReview();
    }
    final st = await svc.getState();
    // 20×2 = 40，第 10 个完成“复习 10 词”任务 +10
    expect(st.todayXp, 50);
  });

  test('三个每日任务全清额外 +20', () async {
    final svc = HabitService(_MemDb());
    await svc.setGoal(999);
    await svc.awardRead('g1');
    for (var i = 0; i < 10; i++) {
      await svc.awardVocabReview();
    }
    await svc.recordCompletion(correct: 5, done: 5);
    final st = await svc.getState();
    expect(st.questRead, greaterThanOrEqualTo(HabitService.questReadTarget));
    expect(st.questVocab, greaterThanOrEqualTo(HabitService.questVocabTarget));
    expect(st.questQuiz, greaterThanOrEqualTo(HabitService.questQuizTarget));
    expect(st.questBonus, isTrue);
  });

  test('收藏单篇封顶 +10', () async {
    final svc = HabitService(_MemDb());
    await svc.setGoal(999);
    for (var i = 0; i < 20; i++) {
      await svc.awardCollect('g1');
    }
    final st = await svc.getState();
    expect(st.todayXp, 10);
  });

  test('等级累计阈值', () {
    expect(HabitService.levelOf(0).level, 1);
    expect(HabitService.levelOf(99).level, 1);
    expect(HabitService.levelOf(100).level, 2);
    expect(HabitService.levelOf(300).level, 3);
    expect(HabitService.levelOf(600).level, 4);
  });

  test('老库升级只提示一次“规则升级”', () async {
    final svc = HabitService(_MemDb({'habit_total': '5', 'habit_maxstreak': '8'}));
    expect(await svc.consumeUpgradeNotice(), isTrue);
    expect(await svc.consumeUpgradeNotice(), isFalse);
    // 全新库不提示
    final fresh = HabitService(_MemDb());
    expect(await fresh.consumeUpgradeNotice(), isFalse);
  });

  test('冻结：断签日被自动覆盖，连胜延续且冻结扣减', () async {
    // 4 个达标日 → 1 个冻结；d(2) 是断签日（夹在连胜中间）
    final gami = {
      'xpTotal': 240,
      'goalXp': 60,
      'maxStreak': 0,
      'days': {_d(1): 60, _d(3): 60, _d(4): 60, _d(5): 60},
    };
    final svc = HabitService(_MemDb({'habit_gami': jsonEncode(gami)}));
    final st = await svc.getState();
    expect(st.streak, 5, reason: 'd(2) 的断签被冻结覆盖，连胜延续');
    expect(st.freezesAvailable, 0, reason: '唯一冻结已被消耗');
  });

  test('补签：花见闻把昨天补回，连胜延续', () async {
    final gami = {
      'xpTotal': 200,
      'goalXp': 60,
      'maxStreak': 0,
      'days': {_d(2): 60, _d(3): 60},
    };
    final svc = HabitService(_MemDb({'habit_gami': jsonEncode(gami)}));
    expect((await svc.getState()).canRepair, isTrue);
    final res = await svc.repairBrokenDay();
    expect(res.ok, isTrue);
    final st = await svc.getState();
    expect(st.streak, 3);
    expect(st.xpTotal, 200 - HabitService.repairCost);
  });

  test('和过去的自己比：本周 / 上周 / 单日最佳', () async {
    final gami = {
      'xpTotal': 300,
      'goalXp': 60,
      'maxStreak': 0,
      'days': {_d(1): 50, _d(3): 120, _d(8): 30, _d(9): 20},
    };
    final svc = HabitService(_MemDb({'habit_gami': jsonEncode(gami)}));
    final st = await svc.getState();
    expect(st.weekXp, 170); // d1(50) + d3(120)
    expect(st.lastWeekXp, 50); // d8(30) + d9(20)
    expect(st.bestDayXp, 120);
  });
}
