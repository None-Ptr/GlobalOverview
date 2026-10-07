import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/habit_service.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  HabitState? _s;
  bool _noticeShown = false;
  static const _catOrder = ['streak', 'total', 'accuracy', 'perfect', 'over'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台时重排提醒：设备改过系统时间、或用户刚在设置里授予精确闹钟权限，
  /// 都会让已排的闹钟失效，重排一次最稳妥（`apply` 幂等）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await ref.read(habitProvider).getState();
    if (mounted) setState(() => _s = s);
    // 同步本地提醒（幂等；测试环境内部短路）。达标后航程预警自动顺延到明天。
    final notif = ref.read(notificationProvider);
    final ns = await notif.loadSettings();
    await notif.apply(enabled: ns.enabled, hour: ns.hour, minute: ns.minute, doneToday: s.isTodayDone, streak: s.streak);
    if (!_noticeShown) {
      _noticeShown = true;
      final show = await ref.read(habitProvider).consumeUpgradeNotice();
      if (show && mounted) _showUpgradeNotice();
    }
  }

  /// 口径升级说明：达标从“测验次数”改为“见闻”。老用户航程已清零，必须明确告知，
  /// 否则会被当成 bug、白白流失用户。
  void _showUpgradeNotice() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('学习规则升级'),
        content: const Text(
          '现在用「见闻」统一记录学习：读完文章、复习单词、交卷、收藏都会攒见闻，'
          '当日见闻达到目标就算达标。\n\n'
          '由于达标口径从“测验次数”改成了“见闻”，历史连续记录已按新规则重新开始，感谢理解！',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
      ),
    );
  }

  String get _greet {
    final h = DateTime.now().hour;
    if (h < 6) return '夜深了';
    if (h < 12) return '早上好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  List<HabitBadgeGroup> _groups(HabitState s) {
    final map = <String, List<HabitBadge>>{};
    for (final b in s.badges) {
      (map[b.cat] ??= []).add(b);
    }
    return _catOrder.where(map.containsKey).map((c) {
      final meta = HabitService.catMeta[c]!;
      return HabitBadgeGroup(
        cat: c,
        label: meta.$1,
        icon: meta.$2,
        items: map[c]!,
      );
    }).toList();
  }

  Future<void> _pickGoal(int n) async {
    await ref.read(habitProvider).setGoal(n);
    await _refresh();
  }

  void _openGoalSheet(HabitState s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        decoration: const BoxDecoration(
          color: Go.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Go.rXl)),
        ),
        padding: EdgeInsets.only(
          left: Go.sp5,
          right: Go.sp5,
          top: Go.sp4,
          bottom: MediaQuery.of(c).padding.bottom + Go.sp6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: Go.r(64),
              height: 3,
              decoration: BoxDecoration(
                color: Go.outlineStrong,
                borderRadius: BorderRadius.circular(Go.rFull),
              ),
            ),
            const SizedBox(height: Go.sp4),
            const Text(
              '每天攒多少见闻算达标？',
              style: TextStyle(
                fontSize: Go.fsTitle,
                fontWeight: FontWeight.w600,
                color: Go.onSurface,
              ),
            ),
            const SizedBox(height: Go.sp5),
            Wrap(
              spacing: Go.sp3,
              runSpacing: Go.sp3,
              alignment: WrapAlignment.center,
              children: [
                for (final n in HabitService.goalOptions)
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(c);
                      _pickGoal(n);
                    },
                    child: Container(
                      height: Go.r(72),
                      padding: const EdgeInsets.symmetric(horizontal: Go.sp6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.goal == n ? Go.primary : Go.surface2,
                        borderRadius: BorderRadius.circular(Go.rFull),
                        border: Border.all(
                          color: s.goal == n ? Go.primary : Go.outline,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '$n 见闻',
                        style: TextStyle(
                          fontSize: Go.fsBodySm,
                          fontWeight: FontWeight.w500,
                          color: s.goal == n ? Go.onPrimary : Go.onSurface2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(habitRevisionProvider, (_, _) => _refresh());
    final s = _s;
    return GoPage(
      topPad: false,
      globe: true,
      globeActive: ref.watch(tabIndexProvider) == 0,
      child: Column(
        children: [
          GoAppBar(
            title: '学习首页',
            style: GoAppBarStyle.floating,
            actions: [
              GoIconBtn(
                icon: 'mine',
                onTap: () => ref.read(tabIndexProvider.notifier).set(4),
              ),
            ],
          ),
          Expanded(
            child: s == null
                ? const Center(child: PolySpinner())
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: GoContent(
                        child: GoStagger(
                          spacing: Go.sp4,
                          children: [
                            _hero(s),
                            _questCard(s),
                            _streakCard(s),
                            _statsCard(s),
                            _compareCard(s),
                            _badgesCard(s),
                            Padding(
                              padding: const EdgeInsets.only(top: Go.sp4),
                              child: SizedBox(
                                height: Go.r(96),
                                child: GoBtn(
                                  label: '去学习 →',
                                  block: true,
                                  onTap: () => ref
                                      .read(tabIndexProvider.notifier)
                                      .set(1),
                                ),
                              ),
                            ),
                            const SizedBox(height: Go.sp8),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _hero(HabitState s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Go.sp6, vertical: Go.sp6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCC241A3A), Go.glassBg],
        ),
        borderRadius: BorderRadius.circular(Go.glassRadius),
        border: Border.all(color: Go.glassBorder, width: 0.5),
        boxShadow: Go.glassShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_greet, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3, letterSpacing: 0.6)),
              const Spacer(),
              GestureDetector(
                onTap: () => _openGoalSheet(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Go.primary90, borderRadius: BorderRadius.circular(Go.rFull)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('目标 ${s.goalXp}', style: const TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w500, color: Go.primary)),
                      const SizedBox(width: Go.sp1),
                      const GoIcon('settings', size: 15, color: Go.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Go.sp4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Go.sp3, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Go.primary, Go.secondary]),
                  borderRadius: BorderRadius.circular(Go.rFull),
                ),
                child: Text('环球 Lv.${s.level}', style: const TextStyle(fontSize: Go.fsBodySm, fontWeight: FontWeight.w700, color: Go.onPrimary)),
              ),
              const SizedBox(width: Go.sp3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: '见闻 ', style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
                        TextSpan(text: '${s.xpTotal}', style: const TextStyle(fontSize: Go.fsH2, fontWeight: FontWeight.w700, color: Go.onSurface, fontFamily: Go.fontMono)),
                        TextSpan(text: ' / ${s.levelCeil}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3, fontFamily: Go.fontMono)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Go.sp2),
                    GoProgress(value: s.levelPct),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Go.sp5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${s.todayXp}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Go.primary, height: 1, fontFamily: Go.fontMono, letterSpacing: 0.5)),
              Text(' / ${s.goalXp}', style: const TextStyle(fontSize: Go.fsH2, fontWeight: FontWeight.w600, color: Go.onSurface2, fontFamily: Go.fontMono)),
              const SizedBox(width: Go.sp2),
              const Expanded(
                child: Text('今日见闻', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
              ),
              if (s.isTodayDone) _pill('已达标', color: Go.success),
            ],
          ),
          const SizedBox(height: Go.sp3),
          GoProgress(value: (s.goalXp <= 0 ? 0 : (s.todayXp / s.goalXp)).clamp(0, 1).toDouble()),
        ],
      ),
    );
  }

  Widget _questCard(HabitState s) {
    final quests = <({String icon, String label, int cur, int target})>[
      (icon: 'reading', label: '读 1 篇', cur: s.questRead, target: HabitService.questReadTarget),
      (icon: 'book', label: '复习 10 词', cur: s.questVocab, target: HabitService.questVocabTarget),
      (icon: 'quiz', label: '交 1 次测验', cur: s.questQuiz, target: HabitService.questQuizTarget),
    ];
    return GoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead(
            '今日航程',
            trailing: s.questBonus ? _pill('全清 +${HabitService.questBonus}', color: Go.success) : null,
          ),
          const SizedBox(height: Go.sp4),
          for (final q in quests) _questRow(q.icon, q.label, q.cur, q.target),
        ],
      ),
    );
  }

  Widget _questRow(String icon, String label, int cur, int target) {
    final done = cur >= target;
    return Padding(
      padding: const EdgeInsets.only(bottom: Go.sp3),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? Go.success.withValues(alpha: 0.18) : Go.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: done ? Go.success.withValues(alpha: 0.5) : Go.outline, width: 0.5),
            ),
            child: GoIcon(done ? 'check' : icon, size: 16, color: done ? Go.success : Go.onSurface3),
          ),
          const SizedBox(width: Go.sp3),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: Go.fsBodySm,
                fontWeight: FontWeight.w500,
                color: done ? Go.onSurface3 : Go.onSurface,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            '${cur.clamp(0, target)}/$target',
            style: TextStyle(fontSize: Go.fsMeta, color: done ? Go.success : Go.onSurface3, fontFamily: Go.fontMono),
          ),
        ],
      ),
    );
  }

  Widget _streakCard(HabitState s) {
    return GoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GoIcon('flame', size: 26, color: Go.tertiary),
              const SizedBox(width: Go.sp3),
              Text('${s.streak}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Go.primary, fontFamily: Go.fontMono)),
              const SizedBox(width: Go.sp1),
              const Expanded(
                child: Text('天连续航行', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface2)),
              ),
              _pill('护航 ${s.freezesAvailable}/${HabitService.maxFreezes}', color: Go.secondary),
            ],
          ),
          if (s.brokenYesterday)
            Padding(
              padding: const EdgeInsets.only(top: Go.sp4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '昨天断航了，可花 ${HabitService.repairCost} 见闻补航',
                      style: const TextStyle(fontSize: Go.fsMeta, color: Go.warning),
                    ),
                  ),
                  GoBtn(label: '补航', onTap: _repair),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: Go.sp3),
              child: Text('护航可在断航当天自动保住航程', style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
            ),
        ],
      ),
    );
  }

  Future<void> _repair() async {
    final res = await ref.read(habitProvider).repairBrokenDay();
    ref.read(habitRevisionProvider.notifier).bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.msg)));
  }

  Widget _compareCard(HabitState s) {
    final diff = s.weekXp - s.lastWeekXp;
    final label = diff > 0 ? '比上周 +$diff' : (diff < 0 ? '比上周 $diff' : '与上周持平');
    return GoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('和过去的自己比', trailing: _pill(label, color: diff >= 0 ? Go.success : Go.warning)),
          const SizedBox(height: Go.sp4),
          Row(
            children: [
              Expanded(child: _statTile(('${s.weekXp}', '本周见闻'))),
              const SizedBox(width: Go.sp3),
              Expanded(child: _statTile(('${s.lastWeekXp}', '上周见闻'))),
              const SizedBox(width: Go.sp3),
              Expanded(child: _statTile(('${s.bestDayXp}', '单日最佳'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardHead(String title, {Widget? trailing, String? icon}) => Row(
    children: [
      if (icon != null) ...[
        GoIcon(icon, size: 17, color: Go.primary),
        const SizedBox(width: Go.sp2),
      ],
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: Go.fsTitle,
            fontWeight: FontWeight.w600,
            color: Go.onSurface,
          ),
        ),
      ),
      const Spacer(),
      ?trailing,
    ],
  );

  Widget _statsCard(HabitState s) {
    final stats = [
      ('${s.total}', '累计测验'),
      (s.accuracy == null ? '—' : '${s.accuracy}%', '累计正确率'),
      ('${s.maxStreak}', '最长连续'),
      ('${s.streak}', '当前连续'),
    ];
    return GoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead('学习数据'),
          const SizedBox(height: Go.sp4),
          for (var i = 0; i < stats.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : Go.sp3),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _statTile(stats[i])),
                    const SizedBox(width: Go.sp3),
                    Expanded(
                      child: i + 1 < stats.length ? _statTile(stats[i + 1]) : const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statTile((String, String) st) => Container(
        padding: const EdgeInsets.all(Go.sp4),
        decoration: BoxDecoration(
          color: Go.surface2,
          borderRadius: BorderRadius.circular(Go.rMd),
          border: Border.all(color: Go.outline, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                st.$1,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Go.onSurface,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              st.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3),
            ),
          ],
        ),
      );

  Widget _badgesCard(HabitState s) {
    return GoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead(
            '成就徽章',
            icon: 'trophy',
            trailing: _pill('已解锁 ${s.unlocked}/${s.totalBadges}', color: Go.primary),
          ),
          for (final g in _groups(s)) ...[
            const SizedBox(height: Go.sp5),
            Row(
              children: [
                GoIcon(g.icon, size: 14, color: Go.primary),
                const SizedBox(width: Go.sp2),
                Text(
                  g.label,
                  style: const TextStyle(
                    fontSize: Go.fsBodySm,
                    fontWeight: FontWeight.w600,
                    color: Go.onSurface,
                  ),
                ),
                const SizedBox(width: Go.sp3),
                Expanded(child: Container(height: 0.5, color: Go.outline)),
                const SizedBox(width: Go.sp3),
                _pill('${g.unlocked}/${g.total}', color: g.unlocked > 0 ? Go.primary : Go.onSurface3),
              ],
            ),
            const SizedBox(height: Go.sp3),
            _badgeGrid(g.items),
          ],
        ],
      ),
    );
  }

  /// 小胶囊：用于分组进度、总进度等计数展示。
  Widget _pill(String text, {required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Go.rFull),
          border: Border.all(color: color.withValues(alpha: 0.30), width: 0.5),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: Go.fsCap, fontWeight: FontWeight.w600, color: color),
        ),
      );

  /// 两列徽章网格：用 IntrinsicHeight 让同行等高，高度由内容决定（不再用固定
  /// childAspectRatio，避免大字号下文字被钳制/底部留大片空白），奇数个时右侧占位。
  Widget _badgeGrid(List<HabitBadge> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _badgeTile(left)),
            const SizedBox(width: Go.sp3),
            Expanded(child: right == null ? const SizedBox() : _badgeTile(right)),
          ],
        ),
      ));
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : Go.sp3), child: rows[i]),
      ],
    );
  }

  /// 徽章等级配色：青铜 / 白银 / 黄金 / 钻石，未解锁也保留等级色（仅降饱和），
  /// 这样四张卡片不再是一模一样的灰块。
  Color _tierColor(String tier) {
    switch (tier) {
      case 'bronze':
        return const Color(0xFFCB9163);
      case 'silver':
        return const Color(0xFFB9C2D6);
      case 'gold':
        return const Color(0xFFE8BE4E);
      case 'diamond':
        return const Color(0xFF6FE3E0);
      default:
        return Go.primary;
    }
  }

  Widget _badgeTile(HabitBadge b) {
    final locked = !b.unlocked;
    final tc = _tierColor(b.tier);
    final iconColor = locked ? Color.lerp(tc, Go.onSurfaceDisabled, 0.62)! : tc;
    return Container(
      padding: const EdgeInsets.all(Go.sp4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: locked
              ? const [Go.surface2, Go.surface1]
              : [tc.withValues(alpha: 0.20), Go.primary95],
        ),
        borderRadius: BorderRadius.circular(Go.rLg),
        border: Border.all(
          color: locked ? Go.outline : tc.withValues(alpha: 0.42),
          width: 0.5,
        ),
        boxShadow: locked
            ? null
            : [BoxShadow(color: tc.withValues(alpha: 0.16), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tc.withValues(alpha: locked ? 0.12 : 0.20),
                  shape: BoxShape.circle,
                  border: Border.all(color: tc.withValues(alpha: locked ? 0.22 : 0.45), width: 0.5),
                ),
                child: GoIcon(b.icon, size: 18, color: iconColor),
              ),
              const Spacer(),
              GoIcon(
                locked ? 'lock' : 'check',
                size: 14,
                color: locked ? Go.onSurfaceDisabled : tc,
              ),
            ],
          ),
          const SizedBox(height: Go.sp3),
          Text(
            b.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: Go.fsBodySm,
              fontWeight: FontWeight.w600,
              color: locked ? Go.onSurface2 : Go.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            b.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: Go.fsCap,
              fontWeight: locked ? FontWeight.w400 : FontWeight.w600,
              color: locked ? Go.onSurface3 : tc,
            ),
          ),
          const Spacer(),
          const SizedBox(height: Go.sp3),
          _miniBar(b.progress, tc, locked),
        ],
      ),
    );
  }

  /// 细进度条：轨道与填充都按等级着色，0 进度时也仍是一条可辨识的轨道
  /// （旧实现是 3px 纯灰线，看起来像分割线）。
  Widget _miniBar(double progress, Color tc, bool locked) => ClipRRect(
        borderRadius: BorderRadius.circular(Go.rFull),
        child: Container(
          height: Go.r(10),
          color: locked ? Go.surfaceVariant : tc.withValues(alpha: 0.18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [tc, Color.lerp(tc, Colors.white, 0.28)!]),
                  borderRadius: BorderRadius.circular(Go.rFull),
                ),
              ),
            ),
          ),
        ),
      );
}
