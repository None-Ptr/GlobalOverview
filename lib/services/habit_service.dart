import 'dart:convert';

import 'package:global_overview/services/db_service.dart';

/// 学习习惯 / 见闻值（XP）/ 连续打卡（“不断电”）本地存储层。
///
/// 见闻值（XP）是所有学习动作的统一货币：读完文章 / 交卷 / 复习词 / 收藏 / 当日达标。
/// 达标与连续航行不再是“测验次数”，而是 **当日见闻 ≥ 目标**。
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

  // —— 见闻系统 ——
  final int xpTotal;
  final int todayXp;
  final int goalXp;
  final int level;
  final int levelFloor; // 本级起始累计见闻
  final int levelCeil; // 下一级所需累计见闻
  final int questRead;
  final int questVocab;
  final int questQuiz;
  final bool questBonus;

  // —— 防流失：护航 / 补航 / 和过去的自己比 ——
  final int freezesAvailable; // 可用护航数
  final int weekXp; // 最近 7 天见闻
  final int lastWeekXp; // 前 7 天见闻
  final int bestDayXp; // 个人单日最佳
  final bool canRepair; // 昨天断航、可补航

  int get unlocked => badges.where((b) => b.unlocked).length;
  int get totalBadges => badges.length;
  int get levelSpan => (levelCeil - levelFloor).clamp(1, 1 << 30);
  int get levelProgress => (xpTotal - levelFloor).clamp(0, levelSpan);
  double get levelPct => (levelProgress / levelSpan).clamp(0, 1).toDouble();

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
    required this.xpTotal,
    required this.todayXp,
    required this.goalXp,
    required this.level,
    required this.levelFloor,
    required this.levelCeil,
    required this.questRead,
    required this.questVocab,
    required this.questQuiz,
    required this.questBonus,
    required this.freezesAvailable,
    required this.weekXp,
    required this.lastWeekXp,
    required this.bestDayXp,
    required this.canRepair,
  });
}

class _BadgeDef {
  final String id, cat, label, icon, tier;
  final int req, reqQ;
  const _BadgeDef(this.id, this.cat, this.label, this.req, this.icon, this.tier, [this.reqQ = 0]);
}

/// 今日航程进度（每天重置）。
class _Quest {
  int read, vocab, quiz;
  bool rRead, rVocab, rQuiz, bonus;
  _Quest({this.read = 0, this.vocab = 0, this.quiz = 0, this.rRead = false, this.rVocab = false, this.rQuiz = false, this.bonus = false});

  Map<String, dynamic> toJson() => {
        'read': read, 'vocab': vocab, 'quiz': quiz,
        'rRead': rRead, 'rVocab': rVocab, 'rQuiz': rQuiz, 'bonus': bonus,
      };

  factory _Quest.fromJson(Map<String, dynamic> j) => _Quest(
        read: (j['read'] as num?)?.toInt() ?? 0,
        vocab: (j['vocab'] as num?)?.toInt() ?? 0,
        quiz: (j['quiz'] as num?)?.toInt() ?? 0,
        rRead: j['rRead'] == true,
        rVocab: j['rVocab'] == true,
        rQuiz: j['rQuiz'] == true,
        bonus: j['bonus'] == true,
      );
}

/// 见闻系统聚合状态（单一 JSON blob，减少 kv 读写）。
class _Gami {
  int xpTotal;
  int goalXp;
  int maxStreak;
  Map<String, int> days; // 每日获得见闻
  Map<String, _Quest> quests; // 今日航程
  Map<String, List<String>> reads; // 每日已读文章 guid（去重给分）
  Map<String, int> vocabReviews; // 每日复习词数（封顶）
  Map<String, Map<String, int>> coll; // 每日每篇收藏计数（封顶）
  Set<String> frozen; // 被“护航”覆盖的日子（自动，延续航程）
  Set<String> repaired; // 被“补航”覆盖的日子（手动、消耗见闻）

  _Gami({
    required this.xpTotal,
    required this.goalXp,
    this.maxStreak = 0,
    Map<String, int>? days,
    Map<String, _Quest>? quests,
    Map<String, List<String>>? reads,
    Map<String, int>? vocabReviews,
    Map<String, Map<String, int>>? coll,
    Set<String>? frozen,
    Set<String>? repaired,
  })  : days = days ?? {},
        quests = quests ?? {},
        reads = reads ?? {},
        vocabReviews = vocabReviews ?? {},
        coll = coll ?? {},
        frozen = frozen ?? {},
        repaired = repaired ?? {};

  factory _Gami.fresh(int goalXp) => _Gami(xpTotal: 0, goalXp: goalXp);

  Map<String, dynamic> toJson() => {
        'xpTotal': xpTotal,
        'goalXp': goalXp,
        'maxStreak': maxStreak,
        'days': days,
        'quests': {for (final e in quests.entries) e.key: e.value.toJson()},
        'reads': reads,
        'vocabReviews': vocabReviews,
        'coll': coll,
        'frozen': frozen.toList(),
        'repaired': repaired.toList(),
      };

  factory _Gami.fromJson(Map<String, dynamic> j) => _Gami(
        xpTotal: (j['xpTotal'] as num?)?.toInt() ?? 0,
        goalXp: (j['goalXp'] as num?)?.toInt() ?? HabitService.defaultGoalXp,
        maxStreak: (j['maxStreak'] as num?)?.toInt() ?? 0,
        days: {for (final e in (j['days'] as Map? ?? {}).entries) e.key.toString(): (e.value as num).toInt()},
        quests: {for (final e in (j['quests'] as Map? ?? {}).entries) e.key.toString(): _Quest.fromJson(Map<String, dynamic>.from(e.value as Map))},
        reads: {for (final e in (j['reads'] as Map? ?? {}).entries) e.key.toString(): [for (final g in (e.value as List)) g.toString()]},
        vocabReviews: {for (final e in (j['vocabReviews'] as Map? ?? {}).entries) e.key.toString(): (e.value as num).toInt()},
        coll: {
          for (final e in (j['coll'] as Map? ?? {}).entries)
            e.key.toString(): {for (final k in (e.value as Map).entries) k.key.toString(): (k.value as num).toInt()},
        },
        frozen: {for (final d in (j['frozen'] as List? ?? [])) d.toString()},
        repaired: {for (final d in (j['repaired'] as List? ?? [])) d.toString()},
      );
}

class HabitService {
  final DbService _db;
  HabitService(this._db);

  // —— 见闻规则常量（可调）——
  static const int xpRead = 30; // 读完一篇文章
  static const int xpQuiz = 20; // 交卷一次
  static const int xpPerfect = 10; // 满分额外
  static const int xpVocab = 2; // 复习一个词
  static const int xpCollect = 1; // 收藏一个词/句
  static const int xpGoalBonus = 50; // 当日首次达标一次性
  static const int vocabDailyCap = 20; // 每日复习计分上限（词）
  static const int collectPerArticleCap = 10; // 单篇收藏计分上限
  static const int questReadTarget = 1;
  static const int questVocabTarget = 10;
  static const int questQuizTarget = 1;
  static const int questReward = 10; // 单个任务奖励
  static const int questBonus = 20; // 三任务全清额外
  static const int defaultGoalXp = 60;
  static const List<int> goalOptions = [30, 60, 100, 150]; // 每日见闻目标可选值
  static const int freezeEveryDays = 3; // 每累计 N 个达标日赠 1 次护航
  static const int maxFreezes = 2; // 护航上限
  static const int repairCost = 50; // 补航消耗的见闻

  /// 等级累计阈值：升到 [level] 需要的累计见闻。
  static int levelNeed(int level) => 50 * level * (level - 1);

  static ({int level, int floor, int ceil}) levelOf(int xp) {
    var lv = 1;
    while (levelNeed(lv + 1) <= xp) {
      lv++;
    }
    return (level: lv, floor: levelNeed(lv), ceil: levelNeed(lv + 1));
  }

  static const _daysKey = 'habit_days';
  static const _totalKey = 'habit_total';
  static const _correctKey = 'habit_correct';
  static const _totalQKey = 'habit_totalq';
  static const _maxKey = 'habit_maxstreak';
  static const _perfectKey = 'habit_perfect';
  static const _overKey = 'habit_over';
  static const _reachKey = 'habit_reach';
  static const _badgesKey = 'habit_badges';
  static const _gamiKey = 'habit_gami';
  static const _upgradeKey = 'habit_upgrade_notice';

  static const badgeDefs = <_BadgeDef>[
    _BadgeDef('s3', 'streak', '刮目相看', 3, 'flame', 'bronze'),
    _BadgeDef('s7', 'streak', '三之及一', 7, 'flame', 'silver'),
    _BadgeDef('s30', 'streak', '亏盈之变', 30, 'flame', 'gold'),
    _BadgeDef('s100', 'streak', '百日维新', 100, 'flame', 'gold'),
    _BadgeDef('s365', 'streak', '易岁之坚', 365, 'flame', 'diamond'),
    _BadgeDef('v10', 'total', '初试锋芒', 10, 'quiz', 'bronze'),
    _BadgeDef('v50', 'total', '渐入佳境', 50, 'quiz', 'silver'),
    _BadgeDef('v200', 'total', '滴水聚百', 200, 'quiz', 'gold'),
    _BadgeDef('v500', 'total', '万千之间', 500, 'quiz', 'diamond'),
    _BadgeDef('a90', 'accuracy', '九成之握', 90, 'check', 'silver', 50),
    _BadgeDef('a98', 'accuracy', '出神入化', 98, 'check', 'gold', 100),
    _BadgeDef('p1', 'perfect', '初盈之喜', 1, 'trophy', 'silver'),
    _BadgeDef('p10', 'perfect', '盈满之诗', 10, 'trophy', 'gold'),
    _BadgeDef('o1', 'over', ' 一五计划', 1, 'star', 'bronze'),
    _BadgeDef('o10', 'over', '好学之成', 10, 'star', 'gold'),
  ];

  static const catMeta = <String, (String label, String icon)>{
    'streak': ('连续打卡', 'flame'),
    'total': ('累计测验', 'quiz'),
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
    return v == null ? fallback : (int.tryParse(v) ?? fallback);
  }

  /// 达标的自然日数（当日见闻 ≥ 目标）。
  static int _reachedDays(_Gami g) => g.days.values.where((x) => x >= g.goalXp).length;

  /// 超额的自然日数（当日见闻 > 目标）。
  static int _overDays(_Gami g) => g.days.values.where((x) => x > g.goalXp).length;

  // ——— 见闻系统读写 ———
  Future<_Gami> _loadGami() async {
    final raw = await _get(_gamiKey);
    if (raw == null || raw.isEmpty) {
      // 首次读取：老库（有旧统计）→ 清零 + 置“规则升级”提示；全新库 → 静默初始化。
      final legacy = await _get(_totalKey);
      final hadLegacy = legacy != null && (int.tryParse(legacy) ?? 0) > 0;
      final g = _Gami.fresh(defaultGoalXp);
      await _saveGami(g);
      await _set(_upgradeKey, hadLegacy ? '1' : '0');
      if (hadLegacy) {
        // 清零决策：历史航程不再沿用
        await _set(_daysKey, '{}');
        await _set(_maxKey, '0');
      }
      return g;
    }
    try {
      return _Gami.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return _Gami.fresh(defaultGoalXp);
    }
  }

  Future<void> _saveGami(_Gami g) => _set(_gamiKey, jsonEncode(g.toJson()));

  /// 首次升级后弹一次“规则升级”说明；返回 true 表示这次应弹。
  Future<bool> consumeUpgradeNotice() async {
    await _loadGami(); // 确保首次读取时已按老库情况置好提示位
    final v = await _get(_upgradeKey);
    if (v == '1') {
      await _set(_upgradeKey, '0');
      return true;
    }
    return false;
  }

  static String _today() => ymd(DateTime.now());

  _Quest _questOf(_Gami g, String date) => g.quests[date] ??= _Quest();

  /// 给当天与累计加见闻；处理“当日首次达标 +50”。返回本次结果。
  Future<({int todayXp, int goalXp, bool reachedGoal, bool levelUp, int level})> _addXp(_Gami g, int amount) async {
    final today = _today();
    final beforeTotal = g.xpTotal;
    final beforeToday = g.days[today] ?? 0;
    g.days[today] = beforeToday + amount;
    g.xpTotal = beforeTotal + amount;

    var reached = false;
    if (beforeToday < g.goalXp && g.days[today]! >= g.goalXp) {
      reached = true;
      g.days[today] = g.days[today]! + xpGoalBonus;
      g.xpTotal += xpGoalBonus;
    }
    // 更新最大航程（顺带自动护航覆盖断航）
    final streak = _computeStreak(g);
    if (streak > g.maxStreak) g.maxStreak = streak;

    await _saveGami(g);
    final lv = levelOf(g.xpTotal);
    return (todayXp: g.days[today]!, goalXp: g.goalXp, reachedGoal: reached, levelUp: lv.level > levelOf(beforeTotal).level, level: lv.level);
  }

  /// 今日航程推进；命中目标给奖励，三项全清给额外奖励。
  Future<void> _bumpQuest(_Gami g, String kind, int n) async {
    final today = _today();
    final q = _questOf(g, today);
    if (kind == 'read') q.read += n;
    if (kind == 'vocab') q.vocab += n;
    if (kind == 'quiz') q.quiz += n;

    if (kind == 'read' && !q.rRead && q.read >= questReadTarget) {
      q.rRead = true;
      await _addXp(g, questReward);
    }
    if (kind == 'vocab' && !q.rVocab && q.vocab >= questVocabTarget) {
      q.rVocab = true;
      await _addXp(g, questReward);
    }
    if (kind == 'quiz' && !q.rQuiz && q.quiz >= questQuizTarget) {
      q.rQuiz = true;
      await _addXp(g, questReward);
    }
    if (!q.bonus && q.rRead && q.rVocab && q.rQuiz) {
      q.bonus = true;
      await _addXp(g, questBonus);
    } else {
      await _saveGami(g);
    }
  }

  /// 读完一篇文章（按 guid 每天只计一次）。
  Future<bool> awardRead(String guid) async {
    final g = await _loadGami();
    final today = _today();
    final list = g.reads[today] ??= [];
    if (guid.isNotEmpty && list.contains(guid)) return false;
    if (guid.isNotEmpty) list.add(guid);
    await _addXp(g, xpRead);
    await _bumpQuest(g, 'read', 1);
    return true;
  }

  /// 复习了一个单词（每日封顶）。
  Future<void> awardVocabReview() async {
    final g = await _loadGami();
    final today = _today();
    final n = g.vocabReviews[today] ?? 0;
    if (n >= vocabDailyCap) return;
    g.vocabReviews[today] = n + 1;
    await _addXp(g, xpVocab);
    await _bumpQuest(g, 'vocab', 1);
  }

  /// 收藏一个词/句（单篇封顶）。
  Future<void> awardCollect(String guid) async {
    final g = await _loadGami();
    final today = _today();
    final per = g.coll[today] ??= {};
    final c = per[guid] ?? 0;
    if (c >= collectPerArticleCap) return;
    per[guid] = c + 1;
    await _addXp(g, xpCollect);
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

  /// 某日是否“算数”：当日见闻达标，或被护航/补航覆盖。
  static bool _dayOk(_Gami g, String date) =>
      (g.days[date] ?? 0) >= g.goalXp || g.frozen.contains(date) || g.repaired.contains(date);

  /// 可用护航数：每 [freezeEveryDays] 个达标日赠 1 次，上限 [maxFreezes]，减去已用。
  static int _freezesAvailable(_Gami g) =>
      ((_reachedDays(g) ~/ freezeEveryDays).clamp(0, maxFreezes) - g.frozen.length).clamp(0, maxFreezes);

  /// 计算当前航程；顺带自动护航覆盖“最近一个断航日”（最多用光可用护航）。
  /// 注意：可能修改 [g].frozen，调用方需在变化后保存。
  static int _computeStreak(_Gami g) {
    final today = ymd(DateTime.now());
    var cursor = _dayOk(g, today) ? today : _addDays(today, -1);
    var streak = 0;
    while (true) {
      if (_dayOk(g, cursor)) {
        streak++;
        cursor = _addDays(cursor, -1);
        continue;
      }
      // 断航日：严格早于今天、且还有可用护航 → 自动护航，延续航程
      if (cursor != today && _freezesAvailable(g) > 0) {
        g.frozen.add(cursor);
        streak++;
        cursor = _addDays(cursor, -1);
        continue;
      }
      break;
    }
    return streak;
  }

  /// [from, to] 闭区间内每日见闻之和（逐日累加，区间很短）。
  static int _sumDays(_Gami g, String from, String to) {
    var s = 0;
    var c = from;
    while (true) {
      s += g.days[c] ?? 0;
      if (c == to) break;
      c = _addDays(c, 1);
    }
    return s;
  }

  Future<int> getGoal() async => (await _loadGami()).goalXp;

  Future<void> setGoal(int xp) async {
    final g = await _loadGami();
    g.goalXp = xp > 0 ? xp : defaultGoalXp;
    await _saveGami(g);
  }

  /// 补航：把“昨天”这一断航日补回来（消耗 [repairCost] 见闻），延续航程。
  /// 若昨天已被护航覆盖 / 本就达标，则无需补航。
  Future<({bool ok, String msg})> repairBrokenDay() async {
    final g = await _loadGami();
    final yesterday = _addDays(_today(), -1);
    if (_dayOk(g, yesterday)) return (ok: false, msg: '昨天没有断航');
    if (g.xpTotal < repairCost) return (ok: false, msg: '见闻不足，需 $repairCost');
    g.xpTotal -= repairCost;
    g.repaired.add(yesterday);
    final streak = _computeStreak(g);
    if (streak > g.maxStreak) g.maxStreak = streak;
    await _saveGami(g);
    return (ok: true, msg: '已补航，航程延续');
  }

  /// 交卷一次调用；correct / done 为本次已判分的正确题数 / 总题数（pending 不计入）。
  Future<({int todayCount, int streak, int maxStreak, int total, List<HabitBadge> newBadges, int xpGained, bool levelUp, int level})>
      recordCompletion({int correct = 0, int done = 0}) async {
    // 见闻：交卷 +20（满分再 +10）+ 今日航程
    final g = await _loadGami();
    final beforeToday = g.days[_today()] ?? 0;
    final beforeLevel = levelOf(g.xpTotal).level;
    final perfect = done > 0 && correct == done;
    await _addXp(g, xpQuiz + (perfect ? xpPerfect : 0));
    await _bumpQuest(g, 'quiz', 1);

    // 旧统计（徽章仍依赖）
    final total = await _getInt(_totalKey, 0) + 1;
    await _set(_totalKey, total.toString());
    final correctSum = await _getInt(_correctKey, 0) + correct;
    await _set(_correctKey, correctSum.toString());
    final totalQ = await _getInt(_totalQKey, 0) + done;
    await _set(_totalQKey, totalQ.toString());

    final reached = _reachedDays(g);
    final over = _overDays(g);
    await _set(_reachKey, reached.toString());
    await _set(_overKey, over.toString());

    var perfectCnt = await _getInt(_perfectKey, 0);
    if (perfect) perfectCnt++;
    await _set(_perfectKey, perfectCnt.toString());

    final streak = _computeStreak(g);
    final maxStreak = [g.maxStreak, streak].reduce((a, b) => a > b ? a : b);
    g.maxStreak = maxStreak;
    await _saveGami(g);

    final todayXp = g.days[_today()] ?? 0;
    final ctx = await _buildCtx(total, maxStreak, correctSum, totalQ, perfectCnt, over);
    final unlocked = await _evaluateUnlocks(ctx, await _getUnlocked());

    final nowLevel = levelOf(g.xpTotal).level;
    return (
      todayCount: todayXp,
      streak: streak,
      maxStreak: maxStreak,
      total: total,
      xpGained: todayXp - beforeToday,
      levelUp: nowLevel > beforeLevel,
      level: nowLevel,
      newBadges: [
        for (final b in unlocked.fresh)
          HabitBadge(
            id: b.id, cat: b.cat, label: b.label, req: b.req, reqQ: b.reqQ,
            icon: b.icon, tier: b.tier, unlocked: true, progress: 1.0, hint: '已解锁',
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

  Future<Set<String>> _getUnlocked() async {
    final v = await _get(_badgesKey);
    if (v == null || v.isEmpty) return {};
    try {
      return (jsonDecode(v) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// 读取首页所需的全部展示数据。
  Future<HabitState> getState() async {
    final g = await _loadGami();
    final total = await _getInt(_totalKey, 0);
    final correct = await _getInt(_correctKey, 0);
    final totalQ = await _getInt(_totalQKey, 0);
    final perfect = await _getInt(_perfectKey, 0);
    final over = await _getInt(_overKey, 0);
    final unlocked = await _getUnlocked();

    final today = _today();
    final todayXp = g.days[today] ?? 0;
    final frozenBefore = g.frozen.length;
    final maxBefore = g.maxStreak;
    final streak = _computeStreak(g);
    if (streak > g.maxStreak) g.maxStreak = streak;
    if (g.frozen.length != frozenBefore || g.maxStreak != maxBefore) await _saveGami(g);
    final isTodayDone = todayXp >= g.goalXp;
    final yesterday = _addDays(today, -1);
    final yesterdayOk = _dayOk(g, yesterday);
    final brokenYesterday = !isTodayDone && !yesterdayOk && g.maxStreak > 0;
    final accuracy = totalQ > 0 ? ((correct / totalQ) * 100).round() : null;
    final lv = levelOf(g.xpTotal);
    final quest = _questOf(g, today);
    final weekXp = _sumDays(g, _addDays(today, -6), today);
    final lastWeekXp = _sumDays(g, _addDays(today, -13), _addDays(today, -7));
    final bestDayXp = g.days.values.isEmpty ? 0 : g.days.values.reduce((a, b) => a > b ? a : b);
    final freezes = _freezesAvailable(g);
    final canRepair = !isTodayDone && !yesterdayOk;

    final ctx = await _buildCtx(total, g.maxStreak, correct, totalQ, perfect, over);
    final badges = badgeDefs.map((b) {
      final unlockedNow = unlocked.contains(b.id);
      final prog = unlockedNow ? (p: 1.0, hint: '已解锁') : _badgeProgress(b, ctx);
      return HabitBadge(
        id: b.id, cat: b.cat, label: b.label, req: b.req, reqQ: b.reqQ,
        icon: b.icon, tier: b.tier, unlocked: unlockedNow, progress: prog.p, hint: prog.hint,
      );
    }).toList();

    return HabitState(
      streak: streak,
      maxStreak: g.maxStreak,
      total: total,
      accuracy: accuracy,
      todayCount: todayXp,
      goal: g.goalXp,
      isTodayDone: isTodayDone,
      brokenYesterday: brokenYesterday,
      badges: badges,
      xpTotal: g.xpTotal,
      todayXp: todayXp,
      goalXp: g.goalXp,
      level: lv.level,
      levelFloor: lv.floor,
      levelCeil: lv.ceil,
      questRead: quest.read,
      questVocab: quest.vocab,
      questQuiz: quest.quiz,
      questBonus: quest.bonus,
      freezesAvailable: freezes,
      weekXp: weekXp,
      lastWeekXp: lastWeekXp,
      bestDayXp: bestDayXp,
      canRepair: canRepair,
    );
  }
}
