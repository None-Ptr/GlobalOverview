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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HabitState? _s;
  static const _catOrder = ['streak', 'total', 'accuracy', 'perfect', 'over'];
  static const _goalOptions = [1, 2, 3, 5];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final s = await ref.read(habitProvider).getState();
    if (mounted) setState(() => _s = s);
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
              '每天做几次测验算达标？',
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
                for (final n in _goalOptions)
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
                        '$n 次',
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
                            _goalCard(s),
                            _statsCard(s),
                            _badgesCard(s),
                            Padding(
                              padding: const EdgeInsets.only(top: Go.sp4),
                              child: SizedBox(
                                height: Go.r(96),
                                child: GoBtn(
                                  label: '去做测验 →',
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

  double _pct(int today, int goal) =>
      goal <= 0 ? 0 : (today / goal * 100).clamp(0, 100).toDouble();

  Widget _hero(HabitState s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Go.sp6, vertical: Go.sp8),
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
        children: [
          Text(
            _greet,
            style: const TextStyle(
              fontSize: Go.fsMeta,
              color: Go.onSurface3,
              letterSpacing: 0.6,
            ),
          ),
          if (s.brokenYesterday)
            Container(
              margin: const EdgeInsets.only(top: Go.sp3),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: Go.warning.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(Go.rFull),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoIcon('alert', size: 14, color: Go.onWarning),
                  SizedBox(width: Go.sp1),
                  Text(
                    '昨日断签，今天续上',
                    style: TextStyle(
                      fontSize: Go.fsMeta,
                      fontWeight: FontWeight.w600,
                      color: Go.onWarning,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Go.sp4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const GoIcon('flame', size: 28, color: Go.tertiary),
                const SizedBox(width: Go.sp2),
                Text(
                  '${s.streak}',
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: Go.primary,
                    height: 1,
                    fontFamily: Go.fontMono,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: Go.sp2),
                const Text(
                  '天连续',
                  style: TextStyle(
                    fontSize: Go.fsH2,
                    color: Go.onSurface2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: Go.sp3),
            child: Text(
              '保持不断电，知识越积越厚',
              style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3),
            ),
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
      Text(
        title,
        style: const TextStyle(
          fontSize: Go.fsTitle,
          fontWeight: FontWeight.w600,
          color: Go.onSurface,
        ),
      ),
      const Spacer(),
      ?trailing,
    ],
  );

  Widget _goalCard(HabitState s) {
    final done = s.isTodayDone;
    return GoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHead(
            '今日目标',
            trailing: GestureDetector(
              onTap: () => _openGoalSheet(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Go.primary90,
                  borderRadius: BorderRadius.circular(Go.rFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '每天 ${s.goal} 次',
                      style: const TextStyle(
                        fontSize: Go.fsMeta,
                        fontWeight: FontWeight.w500,
                        color: Go.primary,
                      ),
                    ),
                    const SizedBox(width: Go.sp1),
                    const GoIcon('settings', size: 15, color: Go.primary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Go.sp4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${s.todayCount}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Go.onSurface,
                  height: 1,
                  fontFamily: Go.fontMono,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: Go.sp1),
              const Text(
                '/',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Go.onSurface2,
                ),
              ),
              const SizedBox(width: Go.sp1),
              Text(
                '${s.goal}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Go.onSurface2,
                  fontFamily: Go.fontMono,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: Go.sp1),
              const Text(
                '次测验',
                style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3),
              ),
            ],
          ),
          const SizedBox(height: Go.sp3),
          GoProgress(value: _pct(s.todayCount, s.goal) / 100),
          Padding(
            padding: const EdgeInsets.only(top: Go.sp3),
            child: Text(
              done
                  ? '今日已达标，明天见！'
                  : '还差 ${(s.goal - s.todayCount).clamp(0, s.goal)} 次，去测一把',
              style: TextStyle(
                fontSize: Go.fsMeta,
                color: done ? Go.success : Go.onSurface3,
                fontWeight: done ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
