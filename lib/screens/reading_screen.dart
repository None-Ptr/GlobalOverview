import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/article_screen.dart';
import 'package:global_overview/services/feeds_data.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 阅读页：1:1 对齐 legacy/src/pages/reading/reading.vue
class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key});
  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  List<Feed> _feeds = [];
  List<Map<String, dynamic>> _allItems = [];
  String _activeCat = 'all';
  String? _activeFeed;
  bool _loading = false;
  String _error = '';
  bool _refreshSpinning = false;
  bool _fetching = false;
  String _catalogCat = 'Learner';
  final _customUrl = TextEditingController();
  Map<String, bool> _planning = {};
  int _cap = 80;
  bool _hasMore = false;
  static const _failThreshold = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _customUrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final svc = ref.read(feedsProvider);
      await svc.ensureFeeds();
      _feeds = await svc.listFeeds();
      final cached = await ref.read(dbProvider).select("SELECT COUNT(*) AS c FROM feed_items WHERE title IS NOT NULL AND title <> ''");
      final hasCache = cached.isNotEmpty && (cached.first['c'] as int? ?? 0) > 0;
      if (!hasCache) {
        await _refreshAll(true);
      } else {
        await _loadAll(true);
      }
      _planning = await svc.loadPlanning();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadPlanning() async {
    final p = await ref.read(feedsProvider).loadPlanning();
    if (mounted) setState(() => _planning = p);
  }

  String? _catLabel(String key) => categoryLabel(key);

  String get _pageTitle => _activeCat == 'all' ? '阅读' : (_catLabel(_activeCat) ?? _activeCat);

  List<(String key, String label, int count)> get _catTabs {
    final feedCats = <String>{};
    for (final f in _feeds) {
      final c = f.category;
      if (c != null && c.isNotEmpty) feedCats.add(c);
    }
    final counts = <String, int>{};
    for (final it in _allItems) {
      final c = it['sourceCat'] as String? ?? '';
      if (c.isNotEmpty) counts[c] = (counts[c] ?? 0) + 1;
    }
    final arr = <(String, String, int)>[(_activeCatKeyAll, '全部', _allItems.length)];
    for (final c in categories) {
      if (feedCats.contains(c.$1)) {
        arr.add((c.$1, _catLabel(c.$1) ?? c.$1, counts[c.$1] ?? 0));
      }
    }
    return arr;
  }

  static const _activeCatKeyAll = 'all';

  List<Feed> get _feedsInCat =>
      _activeCat == 'all' ? _feeds : _feeds.where((f) => f.category == _activeCat).toList();

  List<Map<String, dynamic>> get _displayItems {
    var list = _allItems;
    if (_activeCat != 'all') list = list.where((it) => it['sourceCat'] == _activeCat).toList();
    if (_activeFeed != null) list = list.where((it) => it['sourceUrl'] == _activeFeed).toList();
    return list;
  }

  Future<void> _loadAll(bool reset) async {
    if (reset) _cap = 80;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await ref.read(feedsProvider).loadItemsJoined(_cap, reset ? 0 : _allItems.length);
      final mapped = rows
          .map((r) => <String, dynamic>{
                'id': r['id'],
                'feedId': r['feedId'],
                'guid': r['guid'],
                'title': (r['title'] as String?)?.trim().isNotEmpty == true ? r['title'] : '(无标题)',
                'link': r['link'],
                'preview': r['preview'] ?? '',
                'pubDate': r['pubDate'] ?? 0,
                'sourceTitle': r['sourceTitle'] ?? '未知源',
                'sourceUrl': r['sourceUrl'] ?? '',
                'sourceCat': r['sourceCat'] ?? '',
              })
          .where((it) => (it['title'] as String? ?? '').trim().isNotEmpty)
          .toList();
      setState(() {
        _allItems = reset ? _dedupe(mapped) : _dedupe([..._allItems, ...mapped]);
        _hasMore = mapped.length >= _cap;
      });
    } catch (e) {
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> list) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final it in list) {
      final g = it['guid'] as String? ?? '';
      if (seen.contains(g)) continue;
      seen.add(g);
      out.add(it);
    }
    return out;
  }

  void _loadMore() {
    if (_loading || !_hasMore) return;
    _cap += 40;
    _loadAll(false);
  }

  Future<List<({bool ok, int count, int failCount})>> _mapConcurrent<T>(List<T> list, int limit, Future<({bool ok, int count, int failCount})> Function(T) fn) async {
    final results = List<({bool ok, int count, int failCount})>.filled(list.length, (ok: true, count: 0, failCount: 0));
    var i = 0;
    Future<void> worker() async {
      while (i < list.length) {
        final idx = i++;
        results[idx] = await fn(list[idx]);
      }
    }

    await Future.wait(List.generate(limit < list.length ? limit : list.length, (_) => worker()));
    return results;
  }

  Future<void> _refreshAll(bool replaceCache) async {
    final svc = ref.read(feedsProvider);
    if (_feeds.isEmpty) {
      await svc.ensureFeeds();
      _feeds = await svc.listFeeds();
    }
    if (_feeds.isEmpty) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    final results = await _mapConcurrent(_feeds, 4, (f) => svc.fetchFeedInto(f, replaceCache));
    for (var k = results.length - 1; k >= 0; k--) {
      final r = results[k];
      if (!r.ok && r.failCount >= _failThreshold) {
        await svc.unsubscribe(_feeds[k]);
      }
    }
    _feeds = await svc.listFeeds();
    if (mounted) setState(() => _loading = false);
    await _loadAll(true);
  }

  Future<void> _onRefreshTap() async {
    if (_loading) return;
    setState(() => _refreshSpinning = true);
    try {
      await _refreshAll(true);
    } finally {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _refreshSpinning = false);
    }
  }

  Future<void> _addToPlan(Map<String, dynamic> it) async {
    final guid = it['guid'] as String;
    final svc = ref.read(feedsProvider);
    if (_planning[guid] == true) {
      final aid = await svc.articleIdByGuid(guid);
      if (aid != null) await svc.removePlan(aid);
      setState(() => _planning = {..._planning, guid: false});
      ref.read(planRevisionProvider.notifier).bump();
      return;
    }
    setState(() => _fetching = true);
    try {
      final aid = await svc.captureArticle(guid, it['link'] as String? ?? '', it['title'] as String? ?? '');
      await svc.addPlan(aid);
      setState(() => _planning = {..._planning, guid: true});
      ref.read(planRevisionProvider.notifier).bump();
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(title: const Text('加入失败'), content: Text('$e'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定'))]),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _openItem(Map<String, dynamic> it) async {
    setState(() => _fetching = true);
    try {
      final id = await ref.read(feedsProvider).captureArticle(it['guid'] as String, it['link'] as String? ?? '', it['title'] as String? ?? '');
      if (!mounted) return;
      setState(() => _fetching = false);
      Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(articleId: id)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _fetching = false);
      showDialog(
        context: context,
        builder: (c) => AlertDialog(title: const Text('抓取失败'), content: Text('$e'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定'))]),
      );
    }
  }

  Future<void> _subscribe(FeedDef f) async {
    final svc = ref.read(feedsProvider);
    await svc.subscribe(f.title, f.url, f.category);
    _feeds = await svc.listFeeds();
    final row = _feeds.where((x) => x.url == f.url).toList();
    if (row.isNotEmpty) await svc.fetchFeedInto(row.first, true);
    await _loadAll(true);
  }

  Future<void> _unsubscribe(Feed f) async {
    if (_activeFeed == f.url) _activeFeed = null;
    await ref.read(feedsProvider).unsubscribe(f);
    _feeds = await ref.read(feedsProvider).listFeeds();
    await _loadAll(true);
  }

  Future<void> _addCustomFeed() async {
    var url = _customUrl.text.trim().replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');
    if (url.isEmpty) return;
    if (!RegExp(r'^https?://.+').hasMatch(url)) return;
    if (_feeds.any((f) => f.url == url)) return;
    var title = url;
    try {
      final items = await ref.read(rssProvider).fetch(url);
      if (items.isNotEmpty) title = url;
    } catch (_) {}
    await ref.read(feedsProvider).subscribe(title, url, 'Life');
    _feeds = await ref.read(feedsProvider).listFeeds();
    _customUrl.clear();
    final row = _feeds.where((x) => x.url == url).toList();
    if (row.isNotEmpty) await ref.read(feedsProvider).fetchFeedInto(row.first, true);
    await _loadAll(true);
  }

  String _relTime(int? ts) {
    if (ts == null || ts <= 0) return '';
    final diff = DateTime.now().millisecondsSinceEpoch - ts;
    const m = 60000, h = 3600000, d = 86400000;
    if (diff < m) return '刚刚';
    if (diff < h) return '${diff ~/ m} 分钟前';
    if (diff < d) return '${diff ~/ h} 小时前';
    if (diff < 7 * d) return '${diff ~/ d} 天前';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.month}月${dt.day}日';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(planRevisionProvider, (_, _) => _reloadPlanning());
    final items = _displayItems;
    return GoPage(
      topPad: false,
      child: Stack(
        children: [
          Column(
            children: [
              GoAppBar(
                title: _pageTitle,
                style: GoAppBarStyle.floating,
                actions: [GoIconBtn(icon: 'refresh', primary: true, spin: _refreshSpinning, onTap: _onRefreshTap)],
              ),
              _catRail(),
              if (_feedsInCat.isNotEmpty) _feedRail(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refreshAll(true),
                  child: _listBody(items),
                ),
              ),
            ],
          ),
          GoFab(label: '订阅源', icon: 'plus', onTap: () => _openCatalog()),
          if (_fetching)
            Container(
              color: Go.scrim,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Go.sp10, vertical: Go.sp8),
                decoration: BoxDecoration(color: Go.surfaceRaised, borderRadius: BorderRadius.circular(Go.rLg), boxShadow: Go.shadow3),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PolySpinner(),
                    SizedBox(height: Go.sp4),
                    Text('抓取正文…', style: TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface2, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _catRail() {
    final tabs = _catTabs;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in tabs)
            Padding(
              padding: const EdgeInsets.only(right: Go.sp2),
              child: GestureDetector(
                onTap: () => setState(() {
                  _activeCat = c.$1;
                  _activeFeed = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp2),
                  decoration: BoxDecoration(
                    color: _activeCat == c.$1 ? Go.primary : Go.glassBg,
                    borderRadius: BorderRadius.circular(Go.rFull),
                    boxShadow: Go.elev1,
                  ),
                  child: Row(
                    children: [
                      Text(c.$2, style: TextStyle(fontSize: Go.fsBodySm, fontWeight: FontWeight.w600, color: _activeCat == c.$1 ? Go.onPrimary : Go.onSurface2)),
                      const SizedBox(width: Go.sp2),
                      Text('${c.$3}', style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w700, color: _activeCat == c.$1 ? Go.onPrimary.withValues(alpha: 0.7) : Go.onSurfaceDisabled)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _feedRail() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: Go.sp4, right: Go.sp4, bottom: Go.sp2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _feedChip('全部', _activeFeed == null, () => setState(() => _activeFeed = null)),
          for (final f in _feedsInCat) _feedChip(f.title ?? '', _activeFeed == f.url, () => setState(() => _activeFeed = _activeFeed == f.url ? null : f.url)),
        ],
      ),
    );
  }

  Widget _feedChip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: Go.sp2),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp1),
            decoration: BoxDecoration(
              color: active ? Go.primary.withValues(alpha: 0.14) : Go.surface2,
              borderRadius: BorderRadius.circular(Go.rFull),
              border: active ? Border.all(color: Go.primary.withValues(alpha: 0.3), width: 0.5) : null,
            ),
            child: Text(label, style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w500, color: active ? Go.primary : Go.onSurface3)),
          ),
        ),
      );

  Widget _listBody(List<Map<String, dynamic>> items) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Go.sp4, Go.sp2, Go.sp4, Go.sp16),
      children: [
        if (_error.isNotEmpty)
          _stateCard(
            Row(
              children: [
                Expanded(child: Text(_error, style: const TextStyle(color: Go.danger))),
                GestureDetector(onTap: () => _refreshAll(true), child: const Text('重试', style: TextStyle(color: Go.primary, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        if (_loading && items.isEmpty)
          for (var n = 0; n < 5; n++)
            Container(
              margin: const EdgeInsets.only(bottom: Go.sp3),
              padding: const EdgeInsets.all(Go.sp5),
              decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), border: Border.all(color: Go.outline, width: 0.5)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GoSkeleton(width: 200, height: 16),
                  SizedBox(height: Go.sp3),
                  GoSkeleton(height: 12),
                  SizedBox(height: Go.sp3),
                  GoSkeleton(width: 260, height: 12),
                ],
              ),
            ),
        for (final it in items) ...[
          _articleRow(it),
        ],
        if (_hasMore && items.isNotEmpty)
          GestureDetector(
            onTap: _loadMore,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: Go.sp5),
              child: Text('加载更多', textAlign: TextAlign.center, style: TextStyle(color: Go.primary, fontSize: Go.fsBodySm, fontWeight: FontWeight.w600)),
            ),
          ),
        if (!_loading && _error.isEmpty && items.isEmpty)
          GoEmpty(
            icon: _feeds.isNotEmpty ? 'reading' : 'rss',
            title: _feeds.isNotEmpty ? '这个分类下还没有文章' : '还没有订阅任何源',
            desc: _feeds.isNotEmpty ? '下拉或在右上角重新拉取' : '点右下角「订阅源」挑选几个感兴趣的',
            action: GoBtn(label: _feeds.isNotEmpty ? '立即拉取' : '去选择订阅源', onTap: () => _feeds.isNotEmpty ? _refreshAll(true) : _openCatalog()),
          ),
      ],
    );
  }

  Widget _stateCard(Widget child) => Container(
        margin: const EdgeInsets.all(Go.sp6),
        padding: const EdgeInsets.symmetric(horizontal: Go.sp6, vertical: Go.sp16),
        decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), boxShadow: Go.elev1),
        child: child,
      );

  Widget _articleRow(Map<String, dynamic> it) {
    final guid = it['guid'] as String? ?? '';
    final planned = _planning[guid] == true;
    final initial = (it['sourceTitle'] ?? it['title'] ?? '?').toString();
    final rel = _relTime(it['pubDate'] as int?);
    return Container(
      margin: const EdgeInsets.only(bottom: Go.sp3),
      child: Stack(
        children: [
          // 左侧 accent bar
          Positioned(left: 0, top: 4, bottom: 4, child: Container(width: 3, decoration: BoxDecoration(color: Go.primary, borderRadius: BorderRadius.circular(Go.rFull)))),
          GoCard(
            padding: const EdgeInsets.fromLTRB(Go.sp3, Go.sp5, Go.sp4, Go.sp5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: Go.r(76),
                  height: Go.r(76),
                  margin: const EdgeInsets.only(top: Go.sp1, right: Go.sp3),
                  decoration: BoxDecoration(color: Go.primary, borderRadius: BorderRadius.circular(Go.rMd), boxShadow: Go.elev1),
                  alignment: Alignment.center,
                  child: Text(initial.isEmpty ? '?' : initial.characters.first, style: const TextStyle(fontSize: Go.fsH1, fontWeight: FontWeight.w700, color: Go.onPrimaryVariant)),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openItem(it),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(it['sourceTitle'] as String? ?? '未知源', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: Go.primary))),
                            if (rel.isNotEmpty) ...[
                              const Text(' · ', style: TextStyle(color: Go.onSurfaceDisabled)),
                              Text(rel, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
                            ],
                          ],
                        ),
                        const SizedBox(height: Go.sp2),
                        Text(it['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Go.fsH2, fontWeight: FontWeight.w600, height: Go.lhSnug, color: Go.onSurface)),
                        const SizedBox(height: Go.sp2),
                        Text(it['preview'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3)),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _addToPlan(it),
                  child: Container(
                    margin: const EdgeInsets.only(left: Go.sp2),
                    padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp2),
                    decoration: BoxDecoration(
                      color: planned ? Go.primary.withValues(alpha: 0.14) : Go.primary,
                      borderRadius: BorderRadius.circular(Go.rFull),
                      border: planned ? Border.all(color: Go.primary.withValues(alpha: 0.28), width: 0.5) : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GoIcon(planned ? 'star' : 'plus', size: 13, color: planned ? Go.primary : Go.onPrimary),
                        const SizedBox(width: Go.sp1),
                        Text(planned ? '已加入' : '加入计划', style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: planned ? Go.primary : Go.onPrimary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openCatalog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          final list = feedCatalog.where((f) => f.category == _catalogCat).toList();
          return Container(
            height: MediaQuery.of(c).size.height * 0.78,
            decoration: const BoxDecoration(color: Go.surfaceRaised, borderRadius: BorderRadius.vertical(top: Radius.circular(Go.rXl))),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp5, Go.sp5, Go.sp3),
                  child: Row(
                    children: [
                      const Text('选择订阅源', style: TextStyle(fontSize: Go.fsH1, fontWeight: FontWeight.w600, color: Go.onSurface)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          setSheet(() {});
                          Navigator.pop(c);
                        },
                        child: const GoIcon('stop', size: 24, color: Go.onSurface3),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Go.sp5),
                    children: [
                      for (final cat in categories)
                        Padding(
                          padding: const EdgeInsets.only(right: Go.sp2),
                          child: GestureDetector(
                            onTap: () => setSheet(() => _catalogCat = cat.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp1),
                              decoration: BoxDecoration(color: _catalogCat == cat.$1 ? Go.primary : Go.surface2, borderRadius: BorderRadius.circular(Go.rFull)),
                              child: Text('${cat.$2}${feedCatalog.where((f) => f.category == cat.$1).length}', style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w500, color: _catalogCat == cat.$1 ? Go.onPrimary : Go.onSurface3)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp4, Go.sp5, Go.sp4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('自定义订阅源', style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: Go.onSurface3)),
                      const SizedBox(height: Go.sp2),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: Go.r(68),
                              child: TextField(
                                controller: _customUrl,
                                style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface),
                                decoration: InputDecoration(
                                  hintText: '粘贴 RSS 地址（https://…）',
                                  hintStyle: const TextStyle(color: Go.onSurfaceDisabled),
                                  filled: true,
                                  fillColor: Go.surface2,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: Go.sp3),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(Go.rMd), borderSide: const BorderSide(color: Go.outline, width: 0.5)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: Go.sp2),
                          SizedBox(height: Go.r(68), child: GoBtn(label: '添加', onTap: () async {
                            await _addCustomFeed();
                            setSheet(() {});
                          })),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 0.5, thickness: 0.5, color: Go.outline),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(Go.sp12), child: Text('该分类暂无源', style: TextStyle(color: Go.onSurface3))))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp2),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final f = list[i];
                            final sub = _feeds.any((x) => x.url == f.url);
                            return Container(
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Go.outline, width: 0.5))),
                              padding: const EdgeInsets.symmetric(vertical: Go.sp4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(f.title, style: const TextStyle(fontSize: Go.fsBody, fontWeight: FontWeight.w500, color: Go.onSurface)),
                                        Text(f.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      Feed? row;
                                      for (final x in _feeds) {
                                        if (x.url == f.url) row = x;
                                      }
                                      if (row != null) {
                                        await _unsubscribe(row);
                                      } else {
                                        await _subscribe(f);
                                      }
                                      setSheet(() {});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp2),
                                      decoration: BoxDecoration(
                                        color: sub ? Go.surface2 : Go.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(Go.rFull),
                                        border: Border.all(color: sub ? Go.outline : Go.primary.withValues(alpha: 0.3), width: 0.5),
                                      ),
                                      child: Text(sub ? '已订阅' : '订阅', style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: sub ? Go.onSurfaceDisabled : Go.primary)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
