// Hallmark · screen: vocab · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S4 R4 V4 · weakest S — word rows carry occurrence counts, not chevrons or dot-joined meta
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/screens/review_screen.dart';
import 'package:global_overview/v4/services/article_repository.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 词汇库：到期优先，全部可查。例句与 AI 整理作为二级入口。
class V4VocabScreen extends ConsumerStatefulWidget {
  final String initialFilter;

  const V4VocabScreen({super.key, this.initialFilter = 'all'});

  @override
  ConsumerState<V4VocabScreen> createState() => _V4VocabScreenState();
}

class _V4VocabScreenState extends ConsumerState<V4VocabScreen> {
  List<Map<String, dynamic>> _heads = const [];
  int _due = 0;
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  Timer? _reload;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _reload?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final svc = ref.read(vocabProvider);
      await svc.syncHeadsFromCache();
      final heads = await svc.getHeads();
      final due = await svc.dueCount();
      if (!mounted) return;
      setState(() {
        _heads = heads;
        _due = due;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '暂时无法读取词汇';
      });
    }
  }

  /// 阅读中每次点词都会 bump，这里防抖后只重载一次。
  void _onVocabChanged() {
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  bool _isDue(Map<String, dynamic> head) {
    final due = (head['fsrs_due'] as num?)?.toInt();
    return due == null || due <= DateTime.now().millisecondsSinceEpoch;
  }

  List<Map<String, dynamic>> get _visible =>
      _filter == 'due' ? _heads.where(_isDue).toList() : _heads;

  bool get _hasWords => !_loading && _error == null && _heads.isNotEmpty;

  String _reviewLabel(Map<String, dynamic> head) {
    final due = (head['fsrs_due'] as num?)?.toInt();
    if (due == null) return '待安排';
    final diff = DateTime.fromMillisecondsSinceEpoch(
      due,
    ).difference(DateTime.now());
    if (diff.inMinutes <= 0) return '现在复习';
    final hours = (diff.inMinutes / 60).ceil();
    if (hours < 24) return hours.toString() + ' 小时后';
    final days = (diff.inMinutes / 1440).ceil();
    if (days == 1) return '明天';
    if (days < 30) return days.toString() + ' 天后';
    return '一个月后';
  }

  String _meta(Map<String, dynamic> head) {
    final parts = <String>[];
    final occ = (head['occCount'] as num?)?.toInt() ?? 0;
    if (occ > 0) parts.add('出现 $occ 次');
    final sources = (head['sourceCount'] as num?)?.toInt() ?? 0;
    if (sources > 0) parts.add('$sources 篇来源');
    return parts.join('  ');
  }

  void _openReview() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const V4ReviewScreen()));
  }

  void _openSentences() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const V4SentencesScreen()));
  }

  Future<void> _openWord(Map<String, dynamic> head) async {
    final svc = ref.read(vocabProvider);
    List<Map<String, dynamic>> occ = const [];
    try {
      occ = await svc.getOccurrence(head['head'] as String);
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.v4.surface,
      isScrollControlled: true,
      builder: (_) => _WordSheet(
        head: head,
        occurrences: occ,
        meta: _meta(head),
        onOpenArticle: _openArticle,
        onDelete: () {
          Navigator.of(context).pop();
          _delete(head);
        },
      ),
    );
  }

  Future<void> _openArticle(Map<String, dynamic> occurrence) async {
    final guid = occurrence['articleGuid'] as String?;
    if (guid == null || guid.isEmpty) return;
    final id = await V4ArticleRepository(ref.read(dbProvider)).idByGuid(guid);
    if (!mounted) return;
    if (id == null) {
      showV4Snack(context, '原文还没有保存到本机', tone: V4SnackTone.warning);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => V4ReaderScreen(articleId: id)));
  }

  Future<void> _delete(Map<String, dynamic> head) async {
    final svc = ref.read(vocabProvider);
    final name = head['head'] as String;
    Map<String, dynamic>? snapshot;
    try {
      snapshot = await svc.removeHeadSnapshot(name);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '删除失败，请重试', tone: V4SnackTone.error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _heads = _heads.where((h) => h['head'] != name).toList();
      if (_isDue(head)) _due = (_due - 1).clamp(0, 1 << 30);
    });
    showV4Snack(
      context,
      '已删除 ' + name,
      actionLabel: '撤销',
      duration: const Duration(seconds: 5),
      onAction: () {
        final data = snapshot;
        if (data == null) return;
        svc.restoreHead(data);
        _load();
      },
    );
  }

  Future<void> _organize() async {
    final svc = ref.read(vocabProvider);
    try {
      final res = await svc.organize();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.v4.surface,
        isScrollControlled: true,
        builder: (_) => _OrganizeSheet(groups: (res['groups'] as List?) ?? []),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      showV4Snack(
        context,
        message.contains('未配置') ? 'AI 整理需要先在「我的」配置模型' : 'AI 整理失败，请稍后再试',
        tone: V4SnackTone.error,
      );
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空词汇'),
        content: const Text('会删除全部收藏的词与复习进度，且无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(vocabProvider).clearVocab();
    if (!mounted) return;
    setState(() {
      _heads = const [];
      _due = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    ref.listen(vocabRevisionProvider, (_, _) => _onVocabChanged());
    // Filter once per build: the builder runs per visible row, and calling the
    // getter inside it would re-filter the whole list for every row.
    final visible = _visible;

    return Scaffold(
      backgroundColor: v4.page,
      body: SafeArea(
        bottom: false,
        child: V4Column(
          maxWidth: 900,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: v4.brand,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    V4Space.lg,
                    V4Space.sm,
                    V4Space.lg,
                    V4Space.huge,
                  ),
                  // Header first, then one item per word: a 500-word list must
                  // not build 500 rows before the first frame.
                  itemCount: 1 + (_hasWords ? visible.length : 0),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_summaryText(), style: type.caption),
                          const SizedBox(height: V4Space.md),
                          if (_loading)
                            _loadingCard()
                          else if (_error != null)
                            _errorState()
                          else if (_heads.isEmpty)
                            _emptyState()
                          else ...[
                            _filters(),
                            const SizedBox(height: V4Space.sm),
                          ],
                        ],
                      );
                    }
                    final row = i - 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (row > 0) Divider(height: 1, color: v4.rule),
                        _wordRow(visible[row]),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (!_loading && _due > 0) _reviewBar(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _header() {
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V4Space.sm,
        V4Space.sm,
        V4Space.md,
        V4Space.xs,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(child: Text('词汇', style: type.pageTitle)),
          TButton(
            size: TButtonSize.large,
            variant: TButtonVariant.text,
            onPressed: _openSentences,
            child: const Text('句子'),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == 'organize') _organize();
              if (value == 'clear') _clearAll();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'organize',
                enabled: _heads.isNotEmpty,
                child: const Text('AI 整理'),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: _heads.isNotEmpty,
                child: const Text('清空词汇'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _summaryText() {
    if (_loading) return '正在读取词汇';
    if (_error != null) return '词汇读取失败';
    if (_heads.isEmpty) return '收藏的单词会按最近出现排序';
    final base = _heads.length.toString() + ' 个词';
    if (_due == 0) return base + '  今天没有到期';
    return base + '  ' + _due.toString() + ' 个已到复习时间';
  }

  Widget _loadingCard() {
    final v4 = context.v4;
    return Container(
      padding: const EdgeInsets.all(V4Space.xl),
      decoration: BoxDecoration(
        color: v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: v4.rule),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _errorState() {
    final type = context.v4Type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_error!, style: type.sectionTitle),
        const SizedBox(height: V4Space.sm),
        Text('复习进度不会丢失，可以重试。', style: type.label),
        const SizedBox(height: V4Space.lg),
        V4PrimaryButton(
          onPressed: _load,
          child: const Text('重试'),
        ),
      ],
    );
  }

  Widget _emptyState() {
    final type = context.v4Type;
    return Padding(
      padding: const EdgeInsets.only(top: V4Space.huge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('还没有收藏的词汇', style: type.sectionTitle),
          const SizedBox(height: V4Space.sm),
          Text('在正文里点词，收藏的词会出现在这里。', style: type.label),
        ],
      ),
    );
  }

  Widget _filters() {
    final v4 = context.v4;
    final type = context.v4Type;
    Widget chip(String value, String label) {
      final on = _filter == value;
      return ChoiceChip(
        key: ValueKey('v4-vocab-filter-' + value),
        label: Text(label),
        selected: on,
        showCheckmark: false,
        selectedColor: v4.surfaceSubtle,
        backgroundColor: v4.surface,
        side: BorderSide(color: on ? v4.brand : v4.rule),
        labelStyle: type.label.copyWith(
          color: on ? v4.brand : v4.inkSecondary,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V4Radius.control),
        ),
        onSelected: (_) => setState(() => _filter = value),
      );
    }

    return Wrap(
      spacing: V4Space.sm,
      children: [
        chip('all', '全部 ' + _heads.length.toString()),
        chip('due', '待复习 ' + _due.toString()),
      ],
    );
  }

  Widget _wordRow(Map<String, dynamic> head) {
    final v4 = context.v4;
    final type = context.v4Type;
    final zh = (head['zh'] as String?) ?? '';
    final phrase = head['kind'] == 'phrase';
    final due = _isDue(head);
    return InkWell(
      key: ValueKey('v4-word-' + (head['head'] as String)),
      onTap: () => _openWord(head),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V4Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          head['head'] as String? ?? '',
                          style: type.itemTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (phrase) ...[
                        const SizedBox(width: V4Space.sm),
                        Text('短语', style: type.caption),
                      ],
                    ],
                  ),
                  if (zh.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        zh,
                        style: type.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(_meta(head), style: type.caption),
                ],
              ),
            ),
            const SizedBox(width: V4Space.md),
            SizedBox(
              width: 96,
              child: Text(
                _reviewLabel(head),
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.label.copyWith(
                  color: due ? v4.brand : v4.inkSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewBar() {
    final v4 = context.v4;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        V4Space.lg,
        V4Space.md,
        V4Space.lg,
        V4Space.lg,
      ),
      decoration: BoxDecoration(
        color: v4.page,
        border: Border(top: BorderSide(color: v4.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: V4PrimaryButton(
            onPressed: _openReview,
            child: const Text('开始复习'),
          ),
        ),
      ),
    );
  }
}

class _WordSheet extends StatelessWidget {
  final Map<String, dynamic> head;
  final List<Map<String, dynamic>> occurrences;
  final String meta;
  final void Function(Map<String, dynamic>) onOpenArticle;
  final VoidCallback onDelete;

  const _WordSheet({
    required this.head,
    required this.occurrences,
    required this.meta,
    required this.onOpenArticle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final zh = (head['zh'] as String?) ?? '';
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(V4Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(head['head'] as String? ?? '', style: type.pageTitle),
              if (zh.isNotEmpty) ...[
                const SizedBox(height: V4Space.xs),
                Text(zh, style: type.body),
              ],
              const SizedBox(height: V4Space.sm),
              Text(meta, style: type.caption),
              const SizedBox(height: V4Space.lg),
              Divider(height: 1, color: v4.rule),
              if (occurrences.isNotEmpty) ...[
                const SizedBox(height: V4Space.lg),
                Text('例句', style: type.itemTitle),
                for (final occ in occurrences) ...[
                  const SizedBox(height: V4Space.md),
                  InkWell(
                    onTap: () => onOpenArticle(occ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: V4Space.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (occ['sourceLabel'] as String? ?? '来源') +
                                '  ' +
                                (occ['articleTitle'] as String? ?? ''),
                            style: type.caption.copyWith(color: v4.brand),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '“' + (occ['sentence'] as String? ?? '') + '”',
                            style: type.label.copyWith(color: v4.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: V4Space.lg),
                Text('这条词还没有例句记录', style: type.caption),
              ],
              const SizedBox(height: V4Space.xl),
              Align(
                alignment: Alignment.centerLeft,
                child: TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.text,
                  colorPreset: TButtonColorPreset.danger,
                  onPressed: onDelete,
                  child: const Text('删除生词'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrganizeSheet extends StatelessWidget {
  final List<dynamic> groups;
  const _OrganizeSheet({required this.groups});

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(V4Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI 整理结果', style: type.pageTitle),
              const SizedBox(height: V4Space.lg),
              for (final group in groups) ...[
                Text(
                  (group as Map)['theme'] as String? ?? '未命名主题',
                  style: type.itemTitle.copyWith(color: v4.brand),
                ),
                const SizedBox(height: V4Space.sm),
                for (final item in (group['items'] as List? ?? const []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: V4Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (item as Map)['word'] as String? ?? '',
                          style: type.body,
                        ),
                        Text(
                          (item['zh'] as String? ?? '') +
                              '  ' +
                              (item['en'] as String? ?? ''),
                          style: type.caption,
                        ),
                        Text(
                          'e.g. ' + (item['example'] as String? ?? ''),
                          style: type.caption,
                        ),
                      ],
                    ),
                  ),
                Divider(height: 1, color: v4.rule),
                const SizedBox(height: V4Space.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 收藏的句子：回原文与 AI 拆解。
class V4SentencesScreen extends ConsumerStatefulWidget {
  const V4SentencesScreen({super.key});

  @override
  ConsumerState<V4SentencesScreen> createState() => _V4SentencesScreenState();
}

class _V4SentencesScreenState extends ConsumerState<V4SentencesScreen> {
  List<Map<String, dynamic>> _sentences = const [];
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(vocabProvider).getSentences();
      if (!mounted) return;
      setState(() {
        _sentences = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openArticle(Map<String, dynamic> row) async {
    final guid = row['articleGuid'] as String?;
    if (guid == null || guid.isEmpty) return;
    final id = await V4ArticleRepository(ref.read(dbProvider)).idByGuid(guid);
    if (!mounted) return;
    if (id == null) {
      showV4Snack(context, '原文还没有保存到本机', tone: V4SnackTone.warning);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => V4ReaderScreen(articleId: id)));
  }

  Future<void> _analyze(Map<String, dynamic> row) async {
    final sentence = row['sentence'] as String? ?? '';
    if (sentence.isEmpty) return;
    setState(() => _busy = sentence);
    try {
      final data = await ref.read(vocabProvider).analyzeSentence(sentence);
      if (!mounted) return;
      setState(() {
        row['_analysis'] = data;
        _busy = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = null);
      showV4Snack(context, '拆解失败，请检查模型配置后重试', tone: V4SnackTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Scaffold(
      backgroundColor: v4.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V4Space.sm,
                V4Space.sm,
                V4Space.lg,
                V4Space.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(child: Text('句子', style: type.pageTitle)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _sentences.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(V4Space.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('还没有收藏的句子', style: type.sectionTitle),
                          const SizedBox(height: V4Space.sm),
                          Text('在正文里长按选中句子即可收藏。', style: type.label),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        V4Space.lg,
                        V4Space.sm,
                        V4Space.lg,
                        V4Space.huge,
                      ),
                      itemCount: _sentences.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: V4Space.xxl, color: v4.rule),
                      itemBuilder: (context, index) =>
                          _sentenceCard(_sentences[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sentenceCard(Map<String, dynamic> row) {
    final v4 = context.v4;
    final type = context.v4Type;
    final sentence = row['sentence'] as String? ?? '';
    final analysis = row['_analysis'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('“' + sentence + '”', style: type.body),
        const SizedBox(height: V4Space.sm),
        Text(
          (row['sourceLabel'] as String? ?? '来源') +
              '  ' +
              (row['articleTitle'] as String? ?? ''),
          style: type.caption,
        ),
        const SizedBox(height: V4Space.sm),
        Row(
          children: [
            TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.text,
              onPressed: () => _openArticle(row),
              child: const Text('回到原文'),
            ),
            const SizedBox(width: V4Space.sm),
            TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.text,
              onPressed: _busy == sentence ? null : () => _analyze(row),
              child: Text(_busy == sentence ? '拆解中…' : 'AI 拆解'),
            ),
          ],
        ),
        if (analysis is Map) ...[
          const SizedBox(height: V4Space.sm),
          if ((analysis['translation'] as String? ?? '').isNotEmpty)
            Text(analysis['translation'] as String, style: type.label),
          for (final chunk in (analysis['chunks'] as List? ?? const []))
            Padding(
              padding: const EdgeInsets.only(top: V4Space.xs),
              child: Text(
                (chunk as Map)['text'] as String? ?? '',
                style: type.caption.copyWith(color: v4.ink),
              ),
            ),
        ],
      ],
    );
  }
}
