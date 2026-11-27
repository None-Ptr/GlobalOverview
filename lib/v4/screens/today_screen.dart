// Hallmark · screen: today · genre: editorial · theme: custom (observation station) · scope: app · viewport: wide
// critique: P5 H5 E5 S4 R4 V4 · weakest V — the desk puts the day's article in type on paper and its record beside it
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/feeds_data.dart';
import 'package:global_overview/services/habit_service.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/services/plain_text.dart';
import 'package:global_overview/v4/services/profile_labels.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/article_launcher.dart';
import 'package:global_overview/v4/widgets/article_row.dart';
import 'package:global_overview/v4/widgets/observation_ring.dart';
import 'package:global_overview/v4/widgets/v4_difficulty.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4TodayScreen extends ConsumerStatefulWidget {
  final V4Profile profile;
  final VoidCallback onOpenReading;

  const V4TodayScreen({
    super.key,
    required this.profile,
    required this.onOpenReading,
  });

  @override
  ConsumerState<V4TodayScreen> createState() => _V4TodayScreenState();
}

class _V4TodayScreenState extends ConsumerState<V4TodayScreen> {
  List<Map<String, dynamic>> _items = const [];
  HabitState? _habit;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool bootstrap = true}) async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final feeds = ref.read(feedsProvider);
      await feeds.ensureFeeds();
      var rows = await feeds.loadItemsJoined(20, 0);
      if (rows.isEmpty) {
        try {
          await FeedOverviewService(
            ref.read(dbProvider),
            ref.read(httpProvider),
          ).syncIfNeeded();
          rows = await feeds.loadItemsJoined(20, 0);
        } catch (_) {}
      }
      if (rows.isEmpty && bootstrap) {
        final allFeeds = await feeds.listFeeds();
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        await Future.wait(
          allFeeds
              .take(3)
              .map((f) => feeds.fetchFeedInto(f, false, deadline: deadline)),
        );
        rows = await feeds.loadItemsJoined(20, 0);
      }
      final habit = await ref.read(habitProvider).getState();
      if (!mounted) return;
      setState(() {
        _items = _dedupe(rows);
        _habit = habit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final key = (row['guid'] as String?) ?? (row['link'] as String?) ?? '';
      if (key.isNotEmpty && seen.add(key)) out.add(row);
      if (out.length == 3) break;
    }
    return out;
  }

  String _source(Map<String, dynamic> row) {
    final origin = row['sourceOrigin'] as String?;
    if (origin == 'imported') return '我的导入';
    final source = row['sourceTitle'] as String?;
    if (source != null && source.trim().isNotEmpty) {
      final name = source.trim();
      return origin == 'custom' ? '$name（自定义）' : name;
    }
    final category = row['sourceCat'] as String?;
    if (category != null && category.trim().isNotEmpty) {
      final label = categoryLabel(category) ?? category;
      return origin == 'custom' ? '$label（自定义）' : label;
    }
    return 'GlobalOverview';
  }

  String _meta(Map<String, dynamic> row) {
    final category = row['sourceCat'] as String? ?? '';
    final label = categoryLabel(category) ?? category;
    final timestamp = row['pubDate'] as int?;
    final time = timestamp == null ? '时间未知' : _relative(timestamp);
    return label.isEmpty ? time : label + '  ' + time;
  }

  String _relative(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '刚刚';
    if (diff.inHours < 24) return diff.inHours.toString() + ' 小时前';
    if (diff.inDays < 7) return diff.inDays.toString() + ' 天前';
    return (date.month).toString() + ' 月 ' + (date.day).toString() + ' 日';
  }

  Future<void> _open(Map<String, dynamic> item) =>
      openV4Article(context, ref, item);

  @override
  Widget build(BuildContext context) {
    if (V4Layout.isWide(context)) return _wide(context);
    return _narrow(context);
  }

  /// Desk: the day's article on the left at reading scale, the record on the
  /// right. No card around the lead — a front page is type on paper.
  Widget _wide(BuildContext context) {
    final type = context.v4Type;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          V4Space.xxxl,
          V4Space.xxl,
          V4Space.xxxl,
          V4Space.huge,
        ),
        children: [
          V4Column(
            maxWidth: V4Layout.content,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '今日',
                      style: type.pageTitle.copyWith(
                        fontSize: 30,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: V4Space.md),
                    Text(
                      v4LevelLabel(widget.profile.level) +
                          '  ' +
                          v4GoalLabel(widget.profile.goal),
                      style: type.caption,
                    ),
                  ],
                ),
                const SizedBox(height: V4Space.xxl),
                if (_loading)
                  _loadingState()
                else if (_error != null)
                  _errorState()
                else if (_items.isEmpty)
                  _emptyState()
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: _wideLead(context)),
                      const SizedBox(width: V4Space.huge),
                      Expanded(flex: 5, child: _wideProgress(context)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideLead(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final item = _items.first;
    final rest = _items.length > 1
        ? _items.sublist(1)
        : const <Map<String, dynamic>>[];
    final difficulty = (item['difficulty'] as num?)?.toInt();
    final standfirst = v4Standfirst(item['preview'] as String?);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 28, height: 2, color: v4.brand),
        const SizedBox(height: V4Space.md),
        Text('今日阅读', style: type.sectionTitle),
        const SizedBox(height: V4Space.md),
        Text(
          item['title'] as String? ?? '未命名文章',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: type.articleTitle.copyWith(fontSize: 38, height: 1.22),
        ),
        if (standfirst.isNotEmpty) ...[
          const SizedBox(height: V4Space.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              standfirst,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: type.articleLead.copyWith(
                fontSize: 17,
                height: 1.7,
                color: v4.inkSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: V4Space.lg),
        Row(
          children: [
            Flexible(child: Text(_source(item), style: type.label)),
            if (difficulty != null) ...[
              const SizedBox(width: V4Space.md),
              V4Difficulty(score: difficulty),
            ],
          ],
        ),
        const SizedBox(height: V4Space.xs),
        Text(_meta(item), style: type.caption),
        const SizedBox(height: V4Space.xl),
        SizedBox(
          width: 168,
          child: V4PrimaryButton(
            onPressed: () => _open(item),
            child: const Text('开始阅读'),
          ),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: V4Space.xxxl),
          Divider(height: 1, color: v4.rule),
          const SizedBox(height: V4Space.xl),
          Text('再选一篇', style: type.sectionTitle),
          const SizedBox(height: V4Space.xs),
          for (var i = 0; i < rest.length; i++) ...[
            V4ArticleRow(
              title: rest[i]['title'] as String? ?? '未命名文章',
              source: _source(rest[i]),
              meta: _meta(rest[i]),
              difficulty: (rest[i]['difficulty'] as num?)?.toInt(),
              onTap: () => _open(rest[i]),
            ),
            if (i < rest.length - 1) Divider(height: 1, color: v4.rule),
          ],
        ],
      ],
    );
  }

  Widget _wideProgress(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final current = _habit?.todayCount ?? 0;
    final goal = _habit?.goal ?? 0;
    final streak = _habit?.streak ?? 0;
    return Container(
      padding: const EdgeInsets.all(V4Space.xl),
      decoration: BoxDecoration(
        color: v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: v4.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日进度', style: type.itemTitle),
          const SizedBox(height: V4Space.lg),
          Row(
            children: [
              V4ObservationRing(current: current, goal: goal, size: 128),
              const SizedBox(width: V4Space.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _figure(context, goal.toString(), '每日目标'),
                    const SizedBox(height: V4Space.lg),
                    _figure(context, streak.toString(), '连续天数'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: V4Space.xl),
          Divider(height: 1, color: v4.rule),
          const SizedBox(height: V4Space.lg),
          _fact(context, '等级', v4LevelLabel(widget.profile.level)),
          const SizedBox(height: V4Space.md),
          _fact(context, '方向', v4GoalLabel(widget.profile.goal)),
          const SizedBox(height: V4Space.md),
          _fact(
            context,
            '每日',
            widget.profile.minutes.toString() + ' 分钟',
          ),
        ],
      ),
    );
  }

  Widget _figure(BuildContext context, String value, String label) {
    final type = context.v4Type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: type.displayNumber.copyWith(
            fontSize: 26,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: V4Space.xs),
        Text(label, style: type.caption),
      ],
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    final type = context.v4Type;
    return Row(
      children: [
        Expanded(child: Text(label, style: type.caption)),
        Text(value, style: type.label),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              V4Space.lg,
              V4Space.md,
              V4Space.lg,
              V4Space.sm,
            ),
            child: Row(
              children: [
                Text('GlobalOverview', style: type.sectionTitle),
                const Spacer(),
                if ((_habit?.streak ?? 0) > 0)
                  Text(_habit!.streak.toString() + ' 天', style: type.caption),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(bootstrap: false),
              color: v4.brand,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  V4Space.lg,
                  V4Space.sm,
                  V4Space.lg,
                  V4Space.xxxl,
                ),
                children: [
                  Text(
                    v4LevelLabel(widget.profile.level) +
                        '  ' +
                        v4GoalLabel(widget.profile.goal),
                    style: type.caption,
                  ),
                  const SizedBox(height: V4Space.lg),
                  if (_loading)
                    _loadingState()
                  else if (_error != null)
                    _errorState()
                  else if (_items.isEmpty)
                    _emptyState()
                  else ...[
                    _todayCard(),
                    const SizedBox(height: V4Space.xxl),
                    if (_items.length > 1) ...[
                      Text('再选一篇', style: type.sectionTitle),
                      const SizedBox(height: V4Space.sm),
                      for (var i = 1; i < _items.length; i++) ...[
                        V4ArticleRow(
                          title: _items[i]['title'] as String? ?? '未命名文章',
                          source: _source(_items[i]),
                          meta: _meta(_items[i]),
                          difficulty: (_items[i]['difficulty'] as num?)
                              ?.toInt(),
                          onTap: () => _open(_items[i]),
                        ),
                        if (i < _items.length - 1)
                          Divider(height: 1, color: v4.rule),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayCard() {
    final v4 = context.v4;
    final type = context.v4Type;
    final item = _items.first;
    final current = _habit?.todayCount ?? 0;
    final goal = _habit?.goal ?? 0;
    return Container(
      padding: const EdgeInsets.all(V4Space.xl),
      decoration: BoxDecoration(
        color: v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: v4.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今日阅读', style: type.caption.copyWith(color: v4.brand)),
                    const SizedBox(height: V4Space.sm),
                    Text(
                      item['title'] as String? ?? '未命名文章',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: type.pageTitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: V4Space.md),
              V4ObservationRing(current: current, goal: goal, size: 92),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Row(
            children: [
              Expanded(child: Text(_source(item), style: type.label)),
              if ((item['difficulty'] as num?) != null) ...[
                const SizedBox(width: V4Space.sm),
                V4Difficulty(score: (item['difficulty'] as num).toInt()),
              ],
            ],
          ),
          const SizedBox(height: V4Space.xs),
          Text(_meta(item), style: type.caption),
          const SizedBox(height: V4Space.xl),
          SizedBox(
            width: double.infinity,
            child: V4PrimaryButton(
              onPressed: () => _open(item),
              child: const Text('开始阅读'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingState() {
    final v4 = context.v4;
    final type = context.v4Type;
    return Container(
      padding: const EdgeInsets.all(V4Space.xl),
      decoration: BoxDecoration(
        color: v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: v4.rule),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: V4Space.md),
          Text('正在寻找适合你的今日文章', style: type.label),
        ],
      ),
    );
  }

  Widget _errorState() {
    final type = context.v4Type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('暂时无法获取今日文章', style: type.sectionTitle),
        const SizedBox(height: V4Space.sm),
        Text('网络恢复后可以重试，本地学习记录不会受影响。', style: type.label),
        const SizedBox(height: V4Space.lg),
        V4PrimaryButton(
          onPressed: () => _load(),
          child: const Text('重试'),
        ),
      ],
    );
  }

  Widget _emptyState() {
    final type = context.v4Type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('还没有可读的新文章', style: type.sectionTitle),
        const SizedBox(height: V4Space.sm),
        Text('可以先去阅读页挑选主题，或稍后刷新。', style: type.label),
        const SizedBox(height: V4Space.lg),
        Wrap(
          spacing: V4Space.md,
          children: [
            V4PrimaryButton(
              onPressed: () => _load(),
              child: const Text('刷新'),
            ),
            TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.outline,
              onPressed: widget.onOpenReading,
              child: const Text('去阅读页'),
            ),
          ],
        ),
      ],
    );
  }
}
