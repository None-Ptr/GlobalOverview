// Hallmark · screen: reading desk · genre: editorial · theme: custom (observation station) · scope: app · viewport: wide
// critique: P5 H5 E5 S5 R4 V4 · weakest R — the preview reads a row without leaving the list; filters stay in reach
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/feeds_data.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/services/plain_text.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/article_launcher.dart';
import 'package:global_overview/v4/widgets/article_row.dart';
import 'package:global_overview/v4/widgets/import_sheet.dart';
import 'package:global_overview/v4/widgets/v4_difficulty.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4ReadingScreen extends ConsumerStatefulWidget {
  final V4Profile profile;
  const V4ReadingScreen({super.key, required this.profile});

  @override
  ConsumerState<V4ReadingScreen> createState() => _V4ReadingScreenState();
}

class _V4ReadingScreenState extends ConsumerState<V4ReadingScreen> {
  List<Map<String, dynamic>> _items = const [];
  String _category = '全部';
  bool _loading = true;
  bool _refreshing = false;
  bool _searching = false;
  bool _feedEnabled = true;
  DateTime? _feedLastSync;
  String _query = '';
  int _difficulty = 0;
  String _origin = 'all';
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final svc = ref.read(feedsProvider);
      final feedOverview = FeedOverviewService(
        ref.read(dbProvider),
        ref.read(httpProvider),
      );
      await svc.ensureFeeds();
      var rows = await svc.loadItemsJoined(80, 0);
      if (rows.isEmpty) {
        try {
          await feedOverview.syncIfNeeded();
          rows = await svc.loadItemsJoined(80, 0);
        } catch (_) {}
      }
      if (rows.isEmpty) {
        final feeds = await svc.listFeeds();
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        await Future.wait(
          feeds
              .take(5)
              .map((f) => svc.fetchFeedInto(f, false, deadline: deadline)),
        );
        rows = await svc.loadItemsJoined(80, 0);
      }
      final feedEnabled = await feedOverview.enabled();
      final feedLastSync = await feedOverview.lastSync();
      if (!mounted) return;
      setState(() {
        _items = _dedupe(rows);
        _feedEnabled = feedEnabled;
        _feedLastSync = feedLastSync;
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

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final svc = ref.read(feedsProvider);
      try {
        await FeedOverviewService(
          ref.read(dbProvider),
          ref.read(httpProvider),
        ).syncIfNeeded(force: true);
      } catch (_) {}
      final feeds = await svc.listFeeds();
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      for (var i = 0; i < feeds.length; i += 4) {
        final chunk = feeds.skip(i).take(4).toList();
        await Future.wait(
          chunk.map((f) => svc.fetchFeedInto(f, true, deadline: deadline)),
        );
      }
      final rows = await svc.loadItemsJoined(80, 0);
      if (!mounted) return;
      setState(() => _items = _dedupe(rows));
    } catch (_) {
      if (mounted) setState(() => _error = '刷新失败，已保留本地文章');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _import() async {
    final req = await showImportSheet(context);
    if (req == null || !mounted) return;
    try {
      final svc = ref.read(importProvider);
      if (req.byUrl) {
        await svc.importUrl(url: req.url);
      } else {
        await svc.importText(title: req.title, body: req.body);
      }
      await _load();
      if (!mounted) return;
      showV4Snack(context, '已加入阅读列表', tone: V4SnackTone.success);
    } catch (e) {
      if (!mounted) return;
      showV4Snack(context, errText(e), tone: V4SnackTone.error);
    }
  }

  List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final key = (row['guid'] as String?) ?? (row['link'] as String?) ?? '';
      if (key.isNotEmpty && seen.add(key)) out.add(row);
    }
    return out;
  }

  String _source(Map<String, dynamic> row) {
    final origin = row['sourceOrigin'] as String?;
    final source = row['sourceTitle'] as String?;
    final name = (source != null && source.trim().isNotEmpty)
        ? source.trim()
        : 'GlobalOverview';
    if (origin == 'imported') return '我的导入';
    if (origin == 'custom') return '$name（自定义）';
    return name;
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
    return date.month.toString() + ' 月 ' + date.day.toString() + ' 日';
  }

  List<String> get _categories {
    final seen = <String>{};
    final out = <String>['全部'];
    for (final interest in widget.profile.interests) {
      if (seen.add(interest)) out.add(interest);
    }
    for (final row in _items) {
      final key = row['sourceCat'] as String? ?? '';
      final label = categoryLabel(key) ?? key;
      if (label.isNotEmpty && seen.add(label)) out.add(label);
    }
    return out;
  }

  bool get _filtered =>
      _difficulty > 0 || _origin != 'all' || _query.trim().isNotEmpty;

  List<Map<String, dynamic>> get _visible {
    final query = _query.trim().toLowerCase();
    return _items.where((row) {
      final key = row['sourceCat'] as String? ?? '';
      if (_category != '全部' && (categoryLabel(key) ?? key) != _category) {
        return false;
      }
      if (_difficulty > 0) {
        final tier = V4Difficulty.tierOf(
          (row['difficulty'] as num?)?.toInt(),
        );
        if (tier == null || tier.index + 1 != _difficulty) return false;
      }
      final origin = row['sourceOrigin'] as String? ?? '';
      if (_origin == 'custom' && origin != 'custom') return false;
      if (_origin == 'imported' && origin != 'imported') return false;
      if (_origin == 'feed' && (origin == 'custom' || origin == 'imported')) {
        return false;
      }
      if (query.isNotEmpty) {
        final hay = '${row['title'] ?? ''} ${row['sourceTitle'] ?? ''} '
                '${row['preview'] ?? ''}'
            .toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  String _syncLabel() {
    if (!_feedEnabled) return '正在使用直接抓取';
    final last = _feedLastSync;
    if (last == null) return '内容加速已开启，尚未同步';
    String two(int v) => v.toString().padLeft(2, '0');
    return '内容加速已开启，上次更新 ${two(last.hour)}:${two(last.minute)}';
  }

  Future<void> _openFilters() async {
    var difficulty = _difficulty;
    var origin = _origin;
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      backgroundColor: context.v4.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(V4Radius.sheet),
        ),
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          final v4 = c.v4;
          final type = c.v4Type;
          Widget chip(String label, bool on, VoidCallback tap) => ChoiceChip(
                label: Text(label),
                selected: on,
                onSelected: (_) => tap(),
                selectedColor: v4.surfaceSubtle,
                showCheckmark: false,
                side: BorderSide(color: on ? v4.brand : v4.rule),
                backgroundColor: v4.surface,
                labelStyle: type.caption.copyWith(
                  color: on ? v4.brand : v4.inkSecondary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(V4Radius.control),
                ),
              );
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(V4Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('筛选', style: type.sectionTitle),
                  const SizedBox(height: V4Space.lg),
                  Text('难度', style: type.label),
                  const SizedBox(height: V4Space.sm),
                  Wrap(
                    spacing: V4Space.sm,
                    runSpacing: V4Space.sm,
                    children: [
                      chip('全部', difficulty == 0,
                          () => setSheet(() => difficulty = 0)),
                      for (final tier in V4DifficultyTier.values)
                        chip(
                          tier.label,
                          difficulty == tier.index + 1,
                          () => setSheet(
                            () => difficulty = tier.index + 1,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: V4Space.xl),
                  Text('来源', style: type.label),
                  const SizedBox(height: V4Space.sm),
                  Wrap(
                    spacing: V4Space.sm,
                    runSpacing: V4Space.sm,
                    children: [
                      chip('全部', origin == 'all',
                          () => setSheet(() => origin = 'all')),
                      chip('加速', origin == 'feed',
                          () => setSheet(() => origin = 'feed')),
                      chip('自定义', origin == 'custom',
                          () => setSheet(() => origin = 'custom')),
                      chip('我的导入', origin == 'imported',
                          () => setSheet(() => origin = 'imported')),
                    ],
                  ),
                  const SizedBox(height: V4Space.xl),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(c).pop((0, 'all')),
                        child: const Text('清除'),
                      ),
                      const Spacer(),
                      V4PrimaryButton(
                        onPressed: () => Navigator.of(c).pop(
                          (difficulty, origin),
                        ),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _difficulty = result.$1;
      _origin = result.$2;
    });
  }

  Future<void> _open(Map<String, dynamic> item) =>
      openV4Article(context, ref, item);

  // ---- Desk -------------------------------------------------------------

  /// The row the preview pane is showing; null means the first visible row.
  String? _selectedKey;

  String _keyOf(Map<String, dynamic> row) =>
      (row['guid'] as String?) ??
      (row['link'] as String?) ??
      (row['title'] as String? ?? '');

  Map<String, dynamic>? _previewOf(List<Map<String, dynamic>> visible) {
    if (visible.isEmpty) return null;
    final key = _selectedKey;
    if (key != null) {
      for (final row in visible) {
        if (_keyOf(row) == key) return row;
      }
    }
    return visible.first;
  }

  int _countIn(String label) {
    if (label == '全部') return _items.length;
    var count = 0;
    for (final row in _items) {
      final key = row['sourceCat'] as String? ?? '';
      if ((categoryLabel(key) ?? key) == label) count++;
    }
    return count;
  }

  /// RSS descriptions arrive as HTML; the pane shows sentences, not markup.
  String _plainPreview(String? html) => v4PlainText(html);

  Widget _wide(BuildContext context) {
    final v4 = context.v4;
    final visible = _visible;
    final preview = _previewOf(visible);
    final desk = V4Layout.isDesk(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wideHeader(context),
          Expanded(
            child: V4Column(
              maxWidth: V4Layout.content,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V4Space.xxxl,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: V4Layout.rail, child: _wideRail(context)),
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(
                        horizontal: V4Space.lg,
                      ),
                      color: v4.rule,
                    ),
                    Expanded(child: _wideList(context, visible, preview)),
                    if (desk) ...[
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(
                          horizontal: V4Space.lg,
                        ),
                        color: v4.rule,
                      ),
                      SizedBox(
                        width: V4Layout.preview,
                        child: _widePreview(context, preview),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideHeader(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V4Space.xxxl,
        V4Space.xl,
        V4Space.xxxl,
        V4Space.lg,
      ),
      child: V4Column(
        maxWidth: V4Layout.content,
        child: Row(
          children: [
            Text(
              '阅读',
              style: type.pageTitle.copyWith(fontSize: 30, height: 1.2),
            ),
            const SizedBox(width: V4Space.md),
            Text(_visible.length.toString() + ' 篇', style: type.caption),
            const Spacer(),
            SizedBox(width: 280, child: _wideSearch(context)),
            const SizedBox(width: V4Space.xs),
            IconButton(
              tooltip: '导入文章',
              onPressed: _import,
              icon: Icon(Icons.add_box_outlined, color: v4.inkSecondary),
            ),
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.all(V4Space.md),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: '刷新文章',
                onPressed: _refresh,
                icon: Icon(Icons.refresh, color: v4.inkSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _wideSearch(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return TextField(
      key: const ValueKey('v4-reading-search-field'),
      controller: _search,
      style: type.body.copyWith(fontSize: 15),
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: '搜索标题、来源或摘要',
        hintStyle: type.caption,
        filled: true,
        fillColor: v4.surface,
        isDense: true,
        prefixIcon: Icon(Icons.search, size: 18, color: v4.inkMuted),
        contentPadding: const EdgeInsets.symmetric(vertical: V4Space.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V4Radius.control),
          borderSide: BorderSide(color: v4.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V4Radius.control),
          borderSide: BorderSide(color: v4.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V4Radius.control),
          borderSide: BorderSide(color: v4.brand, width: 2),
        ),
      ),
    );
  }

  Widget _wideRail(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final categories = _categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: V4Space.xl),
        Text('分类', style: type.caption),
        const SizedBox(height: V4Space.sm),
        Flexible(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final label in categories)
                _railItem(
                  context,
                  label: label,
                  count: _countIn(label),
                  selected: label == _category,
                  onTap: () => setState(() {
                    _category = label;
                    _selectedKey = null;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: V4Space.xl),
        Text('难度', style: type.caption),
        const SizedBox(height: V4Space.sm),
        Wrap(
          spacing: V4Space.sm,
          runSpacing: V4Space.sm,
          children: [
            _railToggle(context, '全部', _difficulty == 0,
                () => setState(() => _difficulty = 0)),
            for (final tier in V4DifficultyTier.values)
              _railToggle(
                context,
                tier.label,
                _difficulty == tier.index + 1,
                () => setState(() => _difficulty = tier.index + 1),
              ),
          ],
        ),
        const SizedBox(height: V4Space.xl),
        Text('来源', style: type.caption),
        const SizedBox(height: V4Space.sm),
        Wrap(
          spacing: V4Space.sm,
          runSpacing: V4Space.sm,
          children: [
            _railToggle(context, '全部', _origin == 'all',
                () => setState(() => _origin = 'all')),
            _railToggle(context, '加速', _origin == 'feed',
                () => setState(() => _origin = 'feed')),
            _railToggle(context, '自定义', _origin == 'custom',
                () => setState(() => _origin = 'custom')),
            _railToggle(context, '我的导入', _origin == 'imported',
                () => setState(() => _origin = 'imported')),
          ],
        ),
        if (_filtered) ...[
          const SizedBox(height: V4Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _difficulty = 0;
                _origin = 'all';
                _search.clear();
                _query = '';
              }),
              child: const Text('清除筛选'),
            ),
          ),
        ],
        const SizedBox(height: V4Space.xxl),
        Text(_syncLabel(), style: type.caption),
        if (_error != null) ...[
          const SizedBox(height: V4Space.sm),
          Text(_error!, style: type.caption.copyWith(color: v4.warning)),
        ],
        const SizedBox(height: V4Space.xl),
      ],
    );
  }

  Widget _railItem(
    BuildContext context, {
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        hoverColor: v4.surfaceSubtle,
        borderRadius: BorderRadius.circular(V4Radius.control),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: V4Space.sm),
          decoration: BoxDecoration(
            color: selected ? v4.surfaceSubtle : v4.page,
            borderRadius: BorderRadius.circular(V4Radius.control),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.label.copyWith(
                    color: selected ? v4.ink : v4.inkSecondary,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: V4Space.xs),
              Text(
                count.toString(),
                style: type.caption.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railToggle(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    final v4 = context.v4;
    // A fixed pill width: IntrinsicWidth measures wrapped text at one
    // character under Wrap's unbounded horizontal constraints.
    final width = label.length >= 4 ? 96.0 : 72.0;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        hoverColor: v4.surfaceSubtle,
        borderRadius: BorderRadius.circular(V4Radius.control),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: V4Space.md),
          decoration: BoxDecoration(
            color: on ? v4.surfaceSubtle : v4.page,
            border: Border.all(color: on ? v4.brand : v4.rule),
            borderRadius: BorderRadius.circular(V4Radius.control),
          ),
          child: Center(
            child: Text(
              label,
              style: context.v4Type.caption.copyWith(
                color: on ? v4.brand : v4.inkSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideList(
    BuildContext context,
    List<Map<String, dynamic>> visible,
    Map<String, dynamic>? preview,
  ) {
    final v4 = context.v4;
    final type = context.v4Type;
    final selectedKey = preview == null ? null : _keyOf(preview);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            V4Space.sm,
            V4Space.xl,
            V4Space.sm,
            V4Space.md,
          ),
          child: Row(
            children: [
              Text(_category, style: type.itemTitle),
              const SizedBox(width: V4Space.sm),
              Text(visible.length.toString() + ' 篇', style: type.caption),
            ],
          ),
        ),
        Divider(height: 1, color: v4.rule),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : visible.isEmpty
                  ? _wideEmpty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.only(
                        top: V4Space.xs,
                        bottom: V4Space.xxxl,
                      ),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: v4.rule),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final selected = _keyOf(item) == selectedKey;
                        return Container(
                          decoration: BoxDecoration(
                            color: selected ? v4.surfaceSubtle : v4.page,
                            border: Border(
                              left: BorderSide(
                                color: selected ? v4.brand : v4.page,
                                width: 2,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: V4Space.md,
                          ),
                          child: V4ArticleRow(
                            title: item['title'] as String? ?? '未命名文章',
                            source: _source(item),
                            meta: _meta(item),
                            difficulty: (item['difficulty'] as num?)?.toInt(),
                            onTap: () => setState(
                              () => _selectedKey = _keyOf(item),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _wideEmpty(BuildContext context) {
    final type = context.v4Type;
    return ListView(
      padding: const EdgeInsets.all(V4Space.lg),
      children: [
        const SizedBox(height: V4Space.xxl),
        Text('这个主题暂时没有新文章', style: type.sectionTitle),
        const SizedBox(height: V4Space.sm),
        Text('可以换个主题，或者刷新内容来源。', style: type.label),
        const SizedBox(height: V4Space.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: V4PrimaryButton(
            onPressed: _refresh,
            child: const Text('刷新'),
          ),
        ),
      ],
    );
  }

  Widget _widePreview(BuildContext context, Map<String, dynamic>? item) {
    final v4 = context.v4;
    final type = context.v4Type;
    if (item == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: V4Space.xl),
        child: Container(
          decoration: BoxDecoration(
            color: v4.surface,
            borderRadius: BorderRadius.circular(V4Radius.card),
            border: Border.all(color: v4.rule),
          ),
          child: Center(child: Text('这一栏暂时没有文章', style: type.label)),
        ),
      );
    }
    final difficulty = (item['difficulty'] as num?)?.toInt();
    final previewText = _plainPreview(item['preview'] as String?);
    // A pane, not an article: enough to judge the piece, then whitespace.
    final body = previewText.length > 260
        ? previewText.substring(0, 260).trimRight() + '…'
        : previewText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V4Space.xl),
      child: Container(
        padding: const EdgeInsets.all(V4Space.xl),
        decoration: BoxDecoration(
          color: v4.surface,
          borderRadius: BorderRadius.circular(V4Radius.card),
          border: Border.all(color: v4.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 28, height: 2, color: v4.brand),
            const SizedBox(height: V4Space.md),
            Text(_source(item), style: type.label),
            const SizedBox(height: V4Space.md),
            Text(
              item['title'] as String? ?? '未命名文章',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: type.articleTitle.copyWith(
                fontFamily: V4Fonts.reading,
                fontSize: 26,
                height: 1.3,
              ),
            ),
            const SizedBox(height: V4Space.md),
            Row(
              children: [
                if (difficulty != null) ...[
                  V4Difficulty(score: difficulty),
                  const SizedBox(width: V4Space.sm),
                ],
                Expanded(
                  child: Text(
                    _meta(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption,
                  ),
                ),
              ],
            ),
            const SizedBox(height: V4Space.lg),
            Divider(height: 1, color: v4.rule),
            const SizedBox(height: V4Space.lg),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  body.isEmpty
                      ? '这篇文章只提供了标题，点开可以读全文。'
                      : body,
                  style: type.articleLead.copyWith(
                    fontSize: 16,
                    height: 1.7,
                    color: v4.inkSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: V4Space.lg),
            SizedBox(
              width: double.infinity,
              child: V4PrimaryButton(
                onPressed: () => _open(item),
                child: const Text('开始阅读'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (V4Layout.isWide(context)) return _wide(context);
    return _narrow(context);
  }

  Widget _narrow(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final visible = _visible;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              V4Space.lg,
              V4Space.md,
              V4Space.sm,
              V4Space.sm,
            ),
            child: Row(
              children: [
                Text('阅读', style: type.pageTitle),
                const Spacer(),
                IconButton(
                  key: const ValueKey('v4-reading-search'),
                  tooltip: _searching ? '关闭搜索' : '搜索',
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _search.clear();
                      _query = '';
                    }
                  }),
                  icon: Icon(
                    _searching ? Icons.close : Icons.search,
                    color: v4.inkSecondary,
                  ),
                ),
                IconButton(
                  key: const ValueKey('v4-reading-filter'),
                  tooltip: '筛选',
                  onPressed: _openFilters,
                  icon: Icon(
                    Icons.tune,
                    color: _filtered ? v4.brand : v4.inkSecondary,
                  ),
                ),
                IconButton(
                  key: const ValueKey('v4-reading-import'),
                  tooltip: '导入文章',
                  onPressed: _import,
                  icon: Icon(Icons.add_box_outlined, color: v4.inkSecondary),
                ),
                const SizedBox(width: V4Space.xs),
                if (_refreshing)
                  const Padding(
                    padding: EdgeInsets.all(V4Space.md),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    key: const ValueKey('v4-reading-refresh'),
                    tooltip: '刷新文章',
                    onPressed: _refresh,
                    icon: Icon(Icons.refresh, color: v4.inkSecondary),
                  ),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                0,
                V4Space.lg,
                V4Space.sm,
              ),
              child: TextField(
                key: const ValueKey('v4-reading-search-field'),
                controller: _search,
                autofocus: true,
                style: type.body,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '搜索标题、来源或摘要',
                  hintStyle: type.caption,
                  filled: true,
                  fillColor: v4.surfaceSubtle,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: V4Space.md,
                    vertical: V4Space.md,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(V4Radius.control),
                    borderSide: BorderSide(color: v4.rule),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(V4Radius.control),
                    borderSide: BorderSide(color: v4.rule),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(V4Radius.control),
                    borderSide: BorderSide(color: v4.brand, width: 2),
                  ),
                ),
              ),
            ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: V4Space.lg),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: V4Space.sm),
              itemBuilder: (context, index) {
                final label = _categories[index];
                final selected = label == _category;
                return Center(
                  child: ChoiceChip(
                    key: ValueKey('v4-category-' + label),
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = label),
                    selectedColor: v4.surfaceSubtle,
                    showCheckmark: false,
                    side: BorderSide(color: selected ? v4.brand : v4.rule),
                    backgroundColor: v4.surface,
                    labelStyle: type.label.copyWith(
                      color: selected ? v4.brand : v4.inkSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(V4Radius.control),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              V4Space.lg,
              V4Space.sm,
              V4Space.lg,
              0,
            ),
            child: Text(_syncLabel(), style: type.caption),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                V4Space.sm,
                V4Space.lg,
                0,
              ),
              child: Text(
                _error!,
                style: type.caption.copyWith(color: v4.warning),
              ),
            ),
          const SizedBox(height: V4Space.sm),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : RefreshIndicator(
                    onRefresh: _refresh,
                    color: v4.brand,
                    child: visible.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(V4Space.lg),
                            children: [
                              const SizedBox(height: V4Space.huge),
                              Text('这个主题暂时没有新文章', style: type.sectionTitle),
                              const SizedBox(height: V4Space.sm),
                              Text('可以换个主题，或者刷新内容来源。', style: type.label),
                              const SizedBox(height: V4Space.lg),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: V4PrimaryButton(
                                  onPressed: _refresh,
                                  child: const Text('刷新'),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              V4Space.lg,
                              0,
                              V4Space.lg,
                              V4Space.xxxl,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: v4.rule),
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              return V4ArticleRow(
                                title: item['title'] as String? ?? '未命名文章',
                                source: _source(item),
                                meta: _meta(item),
                                difficulty: (item['difficulty'] as num?)
                                    ?.toInt(),
                                onTap: () => _open(item),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
