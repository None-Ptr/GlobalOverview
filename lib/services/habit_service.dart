import 'dart:convert';

import 'package:global_overview/services/db_service.dart';

/// 学习习惯 / 连续打卡（“不断电”）本地存储层。
class HabitBadge {
  final String id;
  final String cat;
  final String label;
  final int req;
  final int reqQ;
  final String icon;
  final String tier;
  final bool unlocked;
  final double progress;
  final String hint;
  const HabitBadge({
    required this.id,
    required this.cat,
    required this.label,
    required this.req,
    required this.reqQ,
    required this.icon,
    required this.tier,
    required this.unlocked,
    required this.progress,
    required this.hint,
  });
}

class HabitBadgeGroup {
  final String cat;
  final String label;
  final String icon;
  final List<HabitBadge> items;
  int get unlocked => items.where((b) => b.unlocked).length;
  int get total => items.length;
  const HabitBadgeGroup({required this.cat, required this.label, required this.icon, required this.items});
}

class HabitState {
  final int streak;
  final int maxStreak;
  final int total;
  final int? accuracy; // null 表示无已判分数据
  final int todayCount;
  final int goal;
  final bool isTodayDone;
  final bool brokenYesterday;
  final List<HabitBadge> badges;
  int get unlocked => badges.where((b) => b.unlocked).length;
  int get totalBadges => badges.length;
  const HabitState({
    required this.streak,
    required this.maxStreak,
    required this.total,
    required this.accuracy,
    required this.todayCount,
    required this.goal,
    required this.isTodayDone,
    required this.brokenYesterday,
    required this.badges,
  });
}

class _BadgeDef {
  final String id, cat, label, icon, tier;
  final int req, reqQ;
  const _BadgeDef(this.id, this.cat, this.label, this.req, this.icon, this.tier, [this.reqQ = 0]);
}

class HabitService {
  final DbService _db;
  HabitService(this._db);

  static const _daysKey = 'habit_days';
  static const _totalKey = 'habit_total';
  static const _correctKey = 'habit_correct';
  static const _totalQKey = 'habit_totalq';
  static const _goalKey = 'habit_goal';
  static const _maxKey = 'habit_maxstreak';
  static const _perfectKey = 'habit_perfect';
  static const _overKey = 'habit_over';
  static const _reachKey = 'habit_reach';
  static const _badgesKey = 'habit_badges';

  static const badgeDefs = <_BadgeDef>[
    _BadgeDef('s3', 'streak', '刮目相看', 3, 'flame', 'bronze'),
    _BadgeDef('s7', 'streak', '三之及一', 7, 'flame', 'silver'),
    _BadgeDef('s30', 'streak', '亏盈之变', 30, 'flame', 'gold'),
    _BadgeDef('s100', 'streak', '百日维新', 100, 'flame', 'gold'),
    _BadgeDef('s365', 'streak', '易岁之坚', 365, 'flame', 'diamond'),
    _BadgeDef('v10', 'total', '初试锋芒', 10, 'target', 'bronze'),
    _BadgeDef('v50', 'total', '渐入佳境', 50, 'target', 'silver'),
    _BadgeDef('v200', 'total', '滴水聚百', 200, 'target', 'gold'),
    _BadgeDef('v500', 'total', '万千之间', 500, 'target', 'diamond'),
    _BadgeDef('a90', 'accuracy', '九成之握', 90, 'check', 'silver', 50),
    _BadgeDef('a98', 'accuracy', '出神入化', 98, 'check', 'gold', 100),
    _BadgeDef('p1', 'perfect', '初盈之喜', 1, 'trophy', 'silver'),
    _BadgeDef('p10', 'perfect', '盈满之诗', 10, 'trophy', 'gold'),
    _BadgeDef('o1', 'over', ' 一五计划', 1, 'star', 'bronze'),
    _BadgeDef('o10', 'over', '好学之成', 10, 'star', 'gold'),
  ];

  static const catMeta = <String, (String label, String icon)>{
    'streak': ('连续打卡', 'flame'),
    'total': ('累计测验', 'target'),
    'accuracy': ('正确率', 'check'),
    'perfect': ('满分测验', 'trophy'),
    'over': ('超额完成', 'star'),
  };

  // ——— kv 读写 ———
  Future<String?> _get(String key) async {
    final rows = await _db.select('SELECT value FROM kv WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _set(String key, String value) async {
    await _db.execute('INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)', [key, value]);
  }

  Future<int> _getInt(String key, int fallback) async {
    final v = await _get(key);
    return v == null ? fallback : int.tryParse(v) ?? fallback;
  }

  Future<Map<String, int>> _getDays() async {
    final v = await _get(_daysKey);
    if (v == null || v.isEmpty) return {};
    try {
      final m = jsonDecode(v) as Map;
      return m.map((k, val) => MapEntry(k.toString(), (val as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _getUnlocked() async {
    final v = await _get(_badgesKey);
    if (v == null || v.isEmpty) return {};
    try {
      return (jsonDecode(v) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  // ——— 日期工具 ———
  static String ymd(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _addDays(String dateStr, int n) {
    final p = dateStr.split('-').map(int.parse).toList();
    final dt = DateTime(p[0], p[1], p[2]).add(Duration(days: n));
    return ymd(dt);
  }

  static bool _qualifies(Map<String, int> days, String dateStr, int goal) => (days[dateStr] ?? 0) >= goal;

  static int _computeStreak(Map<String, int> days, int goal) {
    final today = ymd(DateTime.now());
    var cursor = _qualifies(days, today, goal) ? today : _addDays(today, -1);
    var streak = 0;
    while (_qualifies(days, cursor, goal)) {
      streak++;
      cursor = _addDays(cursor, -1);
    }
    return streak;
  }

  Future<int> getGoal() async {
    final g = await _getInt(_goalKey, 1);
    return g > 0 ? g : 1;
  }

  Future<void> setGoal(int n) => _set(_goalKey, (n > 0 ? n : 1).toString());

  /// 交卷一次调用；correct / done 为本次已判分的正确题数 / 总题数（pending 不计入）。
  Future<({int todayCount, int streak, int maxStreak, int total, List<HabitBadge> newBadges})>
      recordCompletion({int correct = 0, int done = 0}) async {
    final days = await _getDays();
    final today = ymd(DateTime.now());
    final prevCount = days[today] ?? 0;
    final newCount = prevCount + 1;
    days[today] = newCount;
    await _set(_daysKey, jsonEncode(days));

    final total = await _getInt(_totalKey, 0) + 1;
    await _set(_totalKey, total.toString());
    final correctSum = await _getInt(_correctKey, 0) + correct;
    await _set(_correctKey, correctSum.toString());
    final totalQ = await _getInt(_totalQKey, 0) + done;
    await _set(_totalQKey, totalQ.toString());

    final goal = await getGoal();
    var reached = await _getInt(_reachKey, 0);
    var over = await _getInt(_overKey, 0);
    if (prevCount < goal && newCount >= goal) reached++;
    if (prevCount <= goal && newCount > goal) over++;
    await _set(_reachKey, reached.toString());
    await _set(_overKey, over.toString());

    var perfect = await _getInt(_perfectKey, 0);
    if (done > 0 && correct == done) perfect++;
    await _set(_perfectKey, perfect.toString());

    final streak = _computeStreak(days, goal);
    final maxStreak = [await _getInt(_maxKey, 0), streak].reduce((a, b) => a > b ? a : b);
    await _set(_maxKey, maxStreak.toString());

    final ctx = await _buildCtx(total, maxStreak, correctSum, totalQ, perfect, over);
    final unlocked = await _evaluateUnlocks(ctx, await _getUnlocked());

    return (
      todayCount: newCount,
      streak: streak,
      maxStreak: maxStreak,
      total: total,
      newBadges: [
        for (final b in unlocked.fresh)
          HabitBadge(
            id: b.id,
            cat: b.cat,
            label: b.label,
            req: b.req,
            reqQ: b.reqQ,
            icon: b.icon,
            tier: b.tier,
            unlocked: true,
            progress: 1.0,
            hint: '已解锁',
          ),
      ],
    );
  }

  Future<Map<String, dynamic>> _buildCtx(int total, int maxStreak, int correct, int totalQ, int perfect, int over) async {
    final accuracy = totalQ > 0 ? ((correct / totalQ) * 100).round() : null;
    return {
      'total': total,
      'maxStreak': maxStreak,
      'correct': correct,
      'totalQ': totalQ,
      'perfect': perfect,
      'over': over,
      'accuracy': accuracy,
      'goal': await getGoal(),
      'days': await _getDays(),
      'reached': await _getInt(_reachKey, 0),
    };
  }

  static bool _isUnlocked(_BadgeDef b, Map<String, dynamic> ctx) {
    switch (b.cat) {
      case 'streak':
        return (ctx['maxStreak'] as int) >= b.req;
      case 'total':
        return (ctx['total'] as int) >= b.req;
      case 'accuracy':
        final a = ctx['accuracy'] as int?;
        return a != null && a >= b.req && (ctx['totalQ'] as int) >= b.reqQ;
      case 'perfect':
        return (ctx['perfect'] as int) >= b.req;
      case 'over':
        return (ctx['over'] as int) >= b.req;
      default:
        return false;
    }
  }

  static ({double p, String hint}) _badgeProgress(_BadgeDef b, Map<String, dynamic> ctx) {
    double pct(num cur, int req) => req > 0 ? (cur / req).clamp(0, 1).toDouble() : 0.0;
    switch (b.cat) {
      case 'streak':
        return (p: pct(ctx['maxStreak'] as int, b.req), hint: '${ctx['maxStreak']}/${b.req} 天');
      case 'total':
        return (p: pct(ctx['total'] as int, b.req), hint: '${ctx['total']}/${b.req} 次');
      case 'accuracy':
        final a = ctx['accuracy'] as int?;
        return (p: pct(a ?? 0, b.req), hint: '${a ?? 0}% · 需 ${b.req}% / ${b.reqQ} 题');
      case 'perfect':
        return (p: pct(ctx['perfect'] as int, b.req), hint: '${ctx['perfect']}/${b.req} 次满分');
      case 'over':
        return (p: pct(ctx['over'] as int, b.req), hint: '${ctx['over']}/${b.req} 天超额');
      default:
        return (p: 0.0, hint: '');
    }
  }

  /// 评估并持久化解锁，返回 (全量已解锁, 本次新解锁)。
  Future<({Set<String> next, List<_BadgeDef> fresh})> _evaluateUnlocks(
    Map<String, dynamic> ctx,
    Set<String> prev,
  ) async {
    final next = {...prev};
    final fresh = <_BadgeDef>[];
    for (final b in badgeDefs) {
      if (!next.contains(b.id) && _isUnlocked(b, ctx)) {
        next.add(b.id);
        fresh.add(b);
      }
    }
    if (fresh.isNotEmpty) await _set(_badgesKey, jsonEncode(next.toList()));
    return (next: next, fresh: fresh);
  }

  /// 读取首页所需的全部展示数据。
  Future<HabitState> getState() async {
    final days = await _getDays();
    final goal = await getGoal();
    final total = await _getInt(_totalKey, 0);
    final correct = await _getInt(_correctKey, 0);
    final totalQ = await _getInt(_totalQKey, 0);
    final maxStreak = await _getInt(_maxKey, 0);
    final perfect = await _getInt(_perfectKey, 0);
    final over = await _getInt(_overKey, 0);
    final unlocked = await _getUnlocked();

    final streak = _computeStreak(days, goal);
    final today = ymd(DateTime.now());
    final todayCount = days[today] ?? 0;
    final isTodayDone = todayCount >= goal;
    final brokenYesterday = !isTodayDone && !_qualifies(days, _addDays(today, -1), goal) && maxStreak > 0;
    final accuracy = totalQ > 0 ? ((correct / totalQ) * 100).round() : null;

    final ctx = await _buildCtx(total, maxStreak, correct, totalQ, perfect, over);
    final badges = badgeDefs.map((b) {
      final unlockedNow = unlocked.contains(b.id);
      final prog = unlockedNow ? (p: 1.0, hint: '已解锁') : _badgeProgress(b, ctx);
      return HabitBadge(
        id: b.id,
        cat: b.cat,
        label: b.label,
        req: b.req,
        reqQ: b.reqQ,
        icon: b.icon,
        tier: b.tier,
        unlocked: unlockedNow,
        progress: prog.p,
        hint: prog.hint,
      );
    }).toList();

    return HabitState(
      streak: streak,
      maxStreak: maxStreak,
      total: total,
      accuracy: accuracy,
      todayCount: todayCount,
      goal: goal,
      isTodayDone: isTodayDone,
      brokenYesterday: brokenYesterday,
      badges: badges,
    );
  }
}
