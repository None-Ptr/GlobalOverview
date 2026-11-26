import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/feeds_data.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/custom_feed_sheet.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4SourceScreen extends ConsumerStatefulWidget {
  const V4SourceScreen({super.key});

  @override
  ConsumerState<V4SourceScreen> createState() => _V4SourceScreenState();
}

class _V4SourceScreenState extends ConsumerState<V4SourceScreen> {
  bool _enabled = true;
  bool _loading = true;
  bool _syncing = false;
  bool _custom = false;
  bool _savingUrl = false;
  DateTime? _lastSync;
  String? _urlError;
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _customFeeds = const [];
  String? _error;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final service = FeedOverviewService(
        ref.read(dbProvider),
        ref.read(httpProvider),
      );
      final enabled = await service.enabled();
      final lastSync = await service.lastSync();
      final root = await service.rootUrl();
      final rows = await ref.read(dbProvider).select(
        'SELECT f.category AS category, f.title AS title, COUNT(i.id) AS count '
        'FROM feeds f LEFT JOIN feed_items i ON i.feedId = f.id '
        'WHERE f.url LIKE ? GROUP BY f.id ORDER BY f.category',
        [root + 'feeds/%'],
      );
      final custom = await ref.read(dbProvider).select(
        'SELECT f.id AS id, f.title AS title, f.url AS url, f.category AS category, '
        'COUNT(i.id) AS count '
        'FROM feeds f LEFT JOIN feed_items i ON i.feedId = f.id '
        "WHERE f.origin = 'custom' GROUP BY f.id ORDER BY f.addedAt DESC",
      );
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _lastSync = lastSync;
        _custom = root != FeedOverviewService.baseUrl;
        _urlController.text = _custom ? root : '';
        _categories = rows;
        _customFeeds = custom;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '来源状态暂时不可用';
      });
    }
  }

  Future<void> _toggle(bool value) async {
    final service = FeedOverviewService(
      ref.read(dbProvider),
      ref.read(httpProvider),
    );
    await service.setEnabled(value);
    setState(() => _enabled = value);
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final count = await FeedOverviewService(
        ref.read(dbProvider),
        ref.read(httpProvider),
      ).syncIfNeeded(force: true);
      await _load();
      if (mounted) {
        showV4Snack(
          context,
          '已同步 ' + count.toString() + ' 条内容',
          tone: V4SnackTone.success,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '同步失败，已保留本地文章');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  FeedOverviewService get _service =>
      FeedOverviewService(ref.read(dbProvider), ref.read(httpProvider));

  Future<void> _selectOfficial() async {
    await _service.clearRootUrl();
    await _load();
  }

  Future<void> _saveCustom() async {
    if (_savingUrl) return;
    final normalized = FeedOverviewService.normalizeRootUrl(
      _urlController.text,
    );
    if (normalized == null) {
      setState(() => _urlError = '请输入以 HTTPS 开头的 Pages 地址');
      return;
    }
    setState(() {
      _savingUrl = true;
      _urlError = null;
    });
    try {
      await _service.setRootUrl(normalized);
      await _load();
      if (mounted) {
        showV4Snack(context, '自建加速地址已保存', tone: V4SnackTone.success);
      }
    } catch (_) {
      if (mounted) setState(() => _urlError = '地址保存失败，请重试');
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  Future<void> _addFeed() async {
    final req = await showCustomFeedSheet(context);
    if (req == null || !mounted) return;
    try {
      await ref.read(feedsProvider).addCustomFeed(
            title: req.name,
            url: req.url,
            category: req.category,
          );
      await _load();
      if (mounted) {
        showV4Snack(context, '订阅源已添加', tone: V4SnackTone.success);
      }
    } catch (e) {
      if (mounted) {
        showV4Snack(context, errText(e), tone: V4SnackTone.error);
      }
    }
  }

  Future<void> _refreshFeed(int id) async {
    final feeds = await ref.read(feedsProvider).listFeeds();
    final feed = feeds.where((f) => f.id == id).firstOrNull;
    if (feed == null || !mounted) return;
    showV4Snack(context, '正在刷新 ${feed.title}');
    final res = await ref.read(feedsProvider).fetchFeedInto(
          feed,
          true,
          deadline: DateTime.now().add(const Duration(seconds: 35)),
        );
    await _load();
    if (!mounted) return;
    showV4Snack(
      context,
      res.ok ? '已更新 ${res.count} 条' : (res.error ?? '刷新失败'),
      tone: res.ok ? V4SnackTone.success : V4SnackTone.error,
    );
  }

  Future<void> _removeFeed(int id) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('移除订阅源'),
        content: const Text('这个源已抓取的文章也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await ref.read(feedsProvider).removeFeed(id);
    await _load();
    if (mounted) showV4Snack(context, '订阅源已移除');
  }

  String _lastSyncLabel() {
    if (_lastSync == null) return '尚未同步';
    final diff = DateTime.now().difference(_lastSync!);
    if (diff.inMinutes < 1) return '刚刚同步';
    if (diff.inHours < 1) return diff.inMinutes.toString() + ' 分钟前同步';
    return diff.inHours.toString() + ' 小时前同步';
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Scaffold(
      backgroundColor: v4.page,
      appBar: AppBar(
        backgroundColor: v4.page,
        elevation: 0,
        title: const Text('来源与加速'),
      ),
      body: V4Column(
        child: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(V4Space.lg),
              children: [
                Container(
                  padding: const EdgeInsets.all(V4Space.lg),
                  decoration: BoxDecoration(
                    color: v4.surface,
                    borderRadius: BorderRadius.circular(V4Radius.card),
                    border: Border.all(color: v4.rule),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FeedOverview 内容加速', style: type.itemTitle),
                            const SizedBox(height: V4Space.xs),
                            Text('聚合多个外刊源，优先读取已抽取的精简正文。', style: type.caption),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        activeColor: v4.brand,
                        onChanged: _toggle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: V4Space.lg),
                Text(_lastSyncLabel(), style: type.label),
                if (_error != null) ...[
                  const SizedBox(height: V4Space.sm),
                  Text(
                    _error!,
                    style: type.caption.copyWith(color: v4.warning),
                  ),
                ],
                const SizedBox(height: V4Space.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TButton(
                    size: TButtonSize.large,
                    onPressed: _enabled && !_syncing ? _sync : null,
                    child: Text(_syncing ? '正在同步' : '立即同步'),
                  ),
                ),
                const SizedBox(height: V4Space.xxl),
                Text('加速地址', style: type.sectionTitle),
                const SizedBox(height: V4Space.sm),
                Container(
                  decoration: BoxDecoration(
                    color: v4.surface,
                    borderRadius: BorderRadius.circular(V4Radius.card),
                    border: Border.all(color: v4.rule),
                  ),
                  child: Column(
                    children: [
                      _modeRow(
                        context,
                        label: '官方加速',
                        selected: !_custom,
                        onTap: _selectOfficial,
                      ),
                      Divider(height: 1, color: v4.rule),
                      _modeRow(
                        context,
                        label: '自建加速',
                        selected: _custom,
                        onTap: () => setState(() => _custom = true),
                      ),
                    ],
                  ),
                ),
                if (_custom) ...[
                  const SizedBox(height: V4Space.md),
                  TextField(
                    key: const ValueKey('v4-source-url'),
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Pages 根地址',
                      hintText: 'https://<user>.github.io/FeedOverview/',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_urlError != null) ...[
                    const SizedBox(height: V4Space.sm),
                    Text(
                      _urlError!,
                      style: type.caption.copyWith(color: v4.error),
                    ),
                  ],
                  const SizedBox(height: V4Space.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TButton(
                      size: TButtonSize.large,
                      key: const ValueKey('v4-source-save'),
                      onPressed: _savingUrl ? null : _saveCustom,
                      child: Text(_savingUrl ? '正在保存' : '保存自建地址'),
                    ),
                  ),
                ],
                const SizedBox(height: V4Space.xxl),
                Text('分类来源', style: type.sectionTitle),
                const SizedBox(height: V4Space.sm),
                if (_categories.isEmpty)
                  Text('还没有缓存的分类内容，先执行一次同步。', style: type.label)
                else
                  for (final row in _categories) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: V4Space.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              categoryLabel(row['category'] as String? ?? '') ??
                                  (row['title'] as String? ?? '未分类'),
                              style: type.itemTitle,
                            ),
                          ),
                          Text(
                            ((row['count'] as num?)?.toInt() ?? 0).toString() +
                                ' 篇',
                            style: type.caption,
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: v4.rule),
                  ],
                const SizedBox(height: V4Space.xxl),
                Row(
                  children: [
                    Expanded(
                      child: Text('自定义 RSS', style: type.sectionTitle),
                    ),
                    TextButton(
                      key: const ValueKey('v4-source-add-feed'),
                      onPressed: _addFeed,
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: V4Space.sm),
                if (_customFeeds.isEmpty)
                  Text('还没有自定义订阅源。', style: type.label)
                else
                  for (final row in _customFeeds) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: V4Space.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${row['title'] ?? '未命名源'}',
                                  style: type.itemTitle,
                                ),
                                const SizedBox(height: V4Space.xs),
                                Text(
                                  '${(row['count'] as num?)?.toInt() ?? 0} 篇  '
                                  '${categoryLabel(row['category'] as String? ?? '') ?? ''}',
                                  style: type.caption,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '刷新这个源',
                            onPressed: () =>
                                _refreshFeed((row['id'] as num).toInt()),
                            icon: Icon(Icons.refresh, color: v4.inkSecondary),
                          ),
                          IconButton(
                            tooltip: '移除这个源',
                            onPressed: () =>
                                _removeFeed((row['id'] as num).toInt()),
                            icon: Icon(
                              Icons.delete_outline,
                              color: v4.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: v4.rule),
                  ],
                const SizedBox(height: V4Space.xxl),
                Text('加速只获取公共文章。生词、题集和作答仍然只保存在本机。', style: type.caption),
              ],
            ),
      ),
    );
  }

  Widget _modeRow(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final v4 = context.v4;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V4Space.lg,
              vertical: V4Space.md,
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? v4.brand : v4.inkMuted,
                ),
                const SizedBox(width: V4Space.md),
                Text(label, style: context.v4Type.body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
