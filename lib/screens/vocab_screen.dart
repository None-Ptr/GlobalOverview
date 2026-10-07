import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/screens/article_screen.dart';
import 'package:global_overview/screens/review_screen.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 词汇页：1:1 对齐 legacy/src/pages/vocab/vocab.vue
class VocabScreen extends ConsumerStatefulWidget {
  const VocabScreen({super.key});
  @override
  ConsumerState<VocabScreen> createState() => _VocabScreenState();
}

class _VocabScreenState extends ConsumerState<VocabScreen> {
  List<Map<String, dynamic>> _heads = [];
  String _mode = 'all';
  String _view = 'vocab';
  List<Map<String, dynamic>> _sentences = [];
  int _dueCount = 0;
  Map<String, dynamic>? _occ;
  Map<String, dynamic>? _org;
  bool _busy = false;
  Timer? _reloadTimer;
  int _seenRev = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    super.dispose();
  }

  /// 词汇在别处被改动时刷新（防抖：连续点词/评分只重载一次）。
  void _onVocabChanged() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  List<Map<String, dynamic>> get _filtered => _mode == 'all' ? _heads : _heads.where((h) => h['kind'] == _mode).toList();

  Future<void> _load() async {
    try {
      final svc = ref.read(vocabProvider);
      await svc.syncHeadsFromCache();
      _heads = await svc.getHeads();
      _dueCount = await svc.dueCount();
      final rawSent = await svc.getSentences();
      _sentences = rawSent.map((s) {
        dynamic a;
        try {
          if (s['analysis'] != null) a = jsonDecode(s['analysis'] as String);
        } catch (_) {}
        return {...s, '_analysis': a, '_analyzing': false};
      }).toList();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('词汇加载失败: $e')));
    }
  }

  Future<void> _onOrganize() async {
    if (_heads.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await ref.read(vocabProvider).organize();
      if (!mounted) return;
      setState(() => _org = res);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = errText(e);
      if (msg.contains('未配置') || msg.contains('profile')) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('未配置 LLM'),
            content: const Text('AI 整理需要模型配置，是否前往「我的」添加？'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('前往'))],
          ),
        );
        if (ok == true) ref.read(tabIndexProvider.notifier).set(4);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.length > 60 ? msg.substring(0, 60) : msg)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOcc(Map<String, dynamic> h) async {
    final list = await ref.read(vocabProvider).getOccurrence(h['head'] as String);
    if (!mounted) return;
    setState(() => _occ = {'head': h['head'], 'zh': h['zh'] ?? '', 'list': list});
  }

  void _goArticle(Map<String, dynamic> o) {
    final guid = o['articleGuid'] as String?;
    if (guid == null || guid.isEmpty) return;
    setState(() => _occ = null);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleScreen(guid: guid, focusPara: (o['paraIndex'] as int?) ?? -1, focusTok: (o['tokIndex'] as int?) ?? -1),
      ),
    );
  }

  Future<void> _onAnalyze(Map<String, dynamic> s) async {
    if (s['sentence'] == null) return;
    setState(() => s['_analyzing'] = true);
    try {
      final data = await ref.read(vocabProvider).analyzeSentence(s['sentence'] as String);
      if (!mounted) return;
      setState(() => s['_analysis'] = data);
    } catch (e) {
      if (!mounted) return;
      final msg = errText(e);
      if (msg.contains('未配置')) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('未配置 LLM'),
            content: const Text('语法拆解需要模型配置，是否前往「我的」添加？'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('前往'))],
          ),
        );
        if (ok == true) ref.read(tabIndexProvider.notifier).set(4);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.length > 60 ? msg.substring(0, 60) : msg)));
      }
    } finally {
      if (mounted) setState(() => s['_analyzing'] = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除'),
        content: Text('从词汇库移除「${h['head']}」？'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定'))],
      ),
    );
    if (ok != true) return;
    await ref.read(vocabProvider).removeHead(h['head'] as String);
    setState(() {
      _heads = _heads.where((x) => x['head'] != h['head']).toList();
    });
    _dueCount = await ref.read(vocabProvider).dueCount();
    if (mounted) setState(() {});
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空词汇'),
        content: const Text('确定删除全部收藏词汇与复习进度？'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定'))],
      ),
    );
    if (ok != true) return;
    await ref.read(vocabProvider).clearVocab();
    setState(() {
      _heads = [];
      _dueCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final onThisTab = ref.watch(tabIndexProvider) == 3;
    // 只有本页可见时才响应词汇变更：阅读中每点一个词都会 bump，
    // 隐藏的 Tab 若跟着全量重载（含两次 vocab_occ 聚合）会拖慢阅读。
    if (onThisTab) {
      ref.listen(vocabRevisionProvider, (_, _) {
        _seenRev = ref.read(vocabRevisionProvider);
        _onVocabChanged();
      });
      // 切回本页时若期间有变更，补一次刷新，避免看到旧数据。
      final rev = ref.read(vocabRevisionProvider);
      if (rev != _seenRev) {
        _seenRev = rev;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onVocabChanged();
        });
      }
    }
    final empty = _view == 'vocab' ? _filtered.isEmpty : _sentences.isEmpty;
    return GoPage(
      topPad: false,
      globe: true,
      globeActive: onThisTab && empty,
      child: Stack(
        children: [
          Column(
            children: [
              _appbar(),
              _seg(),
              Expanded(
                child: _view == 'vocab' ? _vocabScroll() : SingleChildScrollView(child: _sentenceView()),
              ),
            ],
          ),
          if (_occ != null) _occSheet(),
          if (_org != null) _orgSheet(),
          if (_busy) Container(color: Go.scrim.withValues(alpha: 0.3), alignment: Alignment.center, child: const PolySpinner()),
        ],
      ),
    );
  }

  Widget _appbar() => GoAppBar(
        title: '词汇',
        style: GoAppBarStyle.floating,
        actions: [
          if (_heads.isNotEmpty)
            GestureDetector(
              onTap: _onOrganize,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Go.sp3, vertical: Go.sp1),
                decoration: BoxDecoration(border: Border.all(color: Go.primary), borderRadius: BorderRadius.circular(Go.rFull)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GoIcon('robot', size: Go.r(40), color: Go.primary),
                  const SizedBox(width: Go.sp1),
                  const Text('AI 整理', style: TextStyle(fontSize: Go.fsMeta, color: Go.primary)),
                ]),
              ),
            ),
          if (_heads.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: Go.sp3),
              child: GestureDetector(onTap: _clearAll, child: const Text('清空', style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3))),
            ),
        ],
      );

  Widget _seg() => Padding(
        padding: const EdgeInsets.fromLTRB(Go.sp6, Go.sp3, Go.sp6, Go.sp2),
        child: Row(
          children: [
            _segItem('词汇', _view == 'vocab', () => setState(() => _view = 'vocab')),
            const SizedBox(width: Go.sp2),
            _segItem('句子', _view == 'sentence', () => setState(() => _view = 'sentence')),
          ],
        ),
      );

  Widget _segItem(String label, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Go.sp2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Go.primary95 : Colors.transparent,
              borderRadius: BorderRadius.circular(Go.rMd),
              border: Border.all(color: on ? Go.primary : Go.outline, width: 0.5),
            ),
            child: Text(label, style: TextStyle(fontSize: Go.fsBody, color: on ? Go.primary : Go.onSurface3)),
          ),
        ),
      );

  /// 词卡量大（可达数千），用 SliverList 懒构建；早先把全部词卡塞进 Column，
  /// 进页面一次性构建三万个 Widget，首屏直接卡住。
  Widget _vocabScroll() {
    final items = _filtered;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _dueCard()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Go.sp6, 0, Go.sp6, Go.sp2),
            child: Text('${_heads.length} 个词族', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
          ),
        ),
        SliverToBoxAdapter(child: _modeTabs()),
        if (items.isEmpty)
          const SliverToBoxAdapter(
            child: GoEmpty(icon: 'book', title: '还没有收藏的词汇', desc: '在正文里点词即可沉淀到这里'),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Go.sp6),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => _wordCard(items[i]),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Go.sp16)),
      ],
    );
  }

  Widget _dueCard() => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewScreen())),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: Go.sp6, vertical: Go.sp4),
          padding: const EdgeInsets.symmetric(horizontal: Go.sp6, vertical: Go.sp5),
          decoration: BoxDecoration(color: Go.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Go.rLg), boxShadow: Go.elev1),
          child: Row(
            children: [
              Text('$_dueCount', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Go.primary)),
              const Padding(padding: EdgeInsets.only(left: Go.sp2), child: Text('张待复习', style: TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface))),
              const Spacer(),
              const Text('去复习 ›', style: TextStyle(fontSize: Go.fsBodySm, color: Go.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _modeTabs() => Padding(
        padding: const EdgeInsets.fromLTRB(Go.sp6, 0, Go.sp6, Go.sp3),
        child: Row(
          children: [
            for (final m in [('all', '全部'), ('word', '单词'), ('phrase', '短语')]) ...[
              GestureDetector(
                onTap: () => setState(() => _mode = m.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp1),
                  decoration: BoxDecoration(color: _mode == m.$1 ? Go.primary95 : Colors.transparent, borderRadius: BorderRadius.circular(Go.rFull), border: Border.all(color: _mode == m.$1 ? Go.primary : Go.outline, width: 0.5)),
                  child: Text(m.$2, style: TextStyle(fontSize: Go.fsMeta, color: _mode == m.$1 ? Go.primary : Go.onSurface3)),
                ),
              ),
              const SizedBox(width: Go.sp2),
            ],
          ],
        ),
      );

  Widget _wordCard(Map<String, dynamic> h) {
    return GestureDetector(
      onTap: () => _openOcc(h),
      child: Container(
        margin: const EdgeInsets.only(bottom: Go.sp3),
        padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp4),
        decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), boxShadow: Go.elev1),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${h['head']}', style: const TextStyle(fontSize: Go.fsBody, fontWeight: FontWeight.w600, color: Go.onSurface)),
                      const SizedBox(width: Go.sp3),
                      if ((h['occCount'] as int? ?? 0) > 1) _badge('×${h['occCount']}'),
                      if ((h['sourceCount'] as int? ?? 0) > 1) ...[const SizedBox(width: Go.sp2), _badge('${h['sourceCount']} 来源', src: true)],
                    ],
                  ),
                  if (h['zh'] != null && '${h['zh']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('${h['zh']}', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface))),
                  if ('${h['latestSentence'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text('${h['latestSentence']}'.length > 70 ? '${h['latestSentence']}'.substring(0, 70) : '${h['latestSentence']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
                    ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _remove(h),
              child: const Padding(padding: EdgeInsets.all(Go.sp2), child: Text('删除', style: TextStyle(fontSize: Go.fsMeta, color: Go.danger))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, {bool src = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Go.sp2, vertical: 1),
        decoration: BoxDecoration(color: src ? Go.primary95 : Go.surface2, borderRadius: BorderRadius.circular(Go.rFull)),
        child: Text(text, style: TextStyle(fontSize: Go.fsMeta, color: src ? Go.primary : Go.onSurface3)),
      );

  Widget _sentenceView() {
    if (_sentences.isEmpty) {
      return const GoEmpty(icon: 'reading', title: '还没有收藏的句子', desc: '在正文里点词，原句会自动沉淀到这里');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(Go.sp6, Go.sp2, Go.sp6, Go.sp2), child: Text('${_sentences.length} 个收藏句子', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3))),
        Padding(
          padding: const EdgeInsets.fromLTRB(Go.sp6, Go.sp2, Go.sp6, Go.sp8),
          child: Column(children: [for (final s in _sentences) _sentenceCard(s)]),
        ),
      ],
    );
  }

  Widget _sentenceCard(Map<String, dynamic> s) {
    final analysis = s['_analysis'];
    return Container(
      margin: const EdgeInsets.only(bottom: Go.sp4),
      padding: const EdgeInsets.all(Go.sp5),
      decoration: BoxDecoration(color: Go.surface2, borderRadius: BorderRadius.circular(Go.rLg), border: Border.all(color: Go.outline, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“${s['sentence']}”', style: const TextStyle(fontSize: Go.fsBody, height: 1.6, color: Go.onSurface)),
          Padding(
            padding: const EdgeInsets.only(top: Go.sp2),
            child: Text('${s['sourceLabel'] ?? '来源'} · ${s['articleTitle'] ?? ''}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Go.sp4),
            child: Row(
              children: [
                _miniBtn('回到原文', () {
                  final guid = s['articleGuid'] as String?;
                  if (guid == null || guid.isEmpty) return;
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(guid: guid, focusPara: (s['paraIndex'] as int?) ?? -1, focusTok: (s['tokIndex'] as int?) ?? -1)));
                }),
                const SizedBox(width: Go.sp3),
                _miniBtn(s['_analyzing'] == true ? '拆解中…' : (analysis != null ? '重新拆解' : 'LLM 拆解'), () => _onAnalyze(s), ai: true),
              ],
            ),
          ),
          if (analysis is Map) _analysisView(analysis),
        ],
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap, {bool ai = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp1),
          decoration: BoxDecoration(border: Border.all(color: ai ? Go.primary : Go.outline), borderRadius: BorderRadius.circular(Go.rFull)),
          child: Text(label, style: TextStyle(fontSize: Go.fsMeta, color: ai ? Go.primary : Go.onSurface2)),
        ),
      );

  Widget _analysisView(Map analysis) {
    return Container(
      margin: const EdgeInsets.only(top: Go.sp4),
      padding: const EdgeInsets.only(top: Go.sp3),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Go.outline, width: 0.5, style: BorderStyle.solid))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ('${analysis['translation'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: Go.sp3), child: Text('${analysis['translation']}', style: const TextStyle(fontSize: Go.fsBody, color: Go.onSurface))),
          if (analysis['chunks'] is List && (analysis['chunks'] as List).isNotEmpty)
            _analysisSection('语块', [
              for (final c in analysis['chunks'] as List) _analysisRow('${c['text']}', '${c['type']} · ${c['note']}'),
            ]),
          if (analysis['grammar'] is List && (analysis['grammar'] as List).isNotEmpty)
            _analysisSection('语法', [
              for (final g in analysis['grammar'] as List) _analysisRow('${g['point']}', '${g['explain']}'),
            ]),
          if (analysis['keywords'] is List && (analysis['keywords'] as List).isNotEmpty)
            _analysisSection('重点词', [
              for (final k in analysis['keywords'] as List) _analysisRow('${k['word']} ${k['pos'] ?? ''}', '${k['zh']}'),
            ]),
        ],
      ),
    );
  }

  Widget _analysisSection(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(bottom: Go.sp3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: Go.fsMeta, color: Go.primary, fontWeight: FontWeight.w600)),
            ...rows,
          ],
        ),
      );

  Widget _analysisRow(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(vertical: Go.sp2),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Go.outline, width: 0.5))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: const TextStyle(fontSize: Go.fsBody, color: Go.onSurface)),
            Text(v, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
          ],
        ),
      );

  Widget _sheetShell({required String title, String? zh, required Widget body, required Widget actions, bool tall = false}) {
    return GestureDetector(
      onTap: () => setState(() {
        _occ = null;
        _org = null;
      }),
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * (tall ? 0.84 : 0.78)),
            decoration: const BoxDecoration(color: Go.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(Go.rXl))),
            padding: const EdgeInsets.all(Go.sp6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: Go.fsTitle, fontWeight: FontWeight.w700, color: Go.onSurface)),
                if (zh != null && zh.isNotEmpty) Text(zh, style: const TextStyle(fontSize: Go.fsBody, color: Go.onSurface3)),
                Flexible(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(vertical: Go.sp4), child: body)),
                actions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _occSheet() {
    final occ = _occ!;
    final list = occ['list'] as List;
    return _sheetShell(
      title: '${occ['head']}',
      zh: occ['zh'] as String?,
      actions: GestureDetector(
        onTap: () => setState(() => _occ = null),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Go.sp3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Go.primary, borderRadius: BorderRadius.circular(Go.rFull)),
          child: const Text('关闭', style: TextStyle(fontSize: Go.fsBody, color: Colors.white)),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in list)
            GestureDetector(
              onTap: () => _goArticle(o),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Go.sp4),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Go.outline, width: 0.5))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${o['sourceLabel'] ?? '来源'} · ${o['articleTitle'] ?? ''}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.primary, fontWeight: FontWeight.w600)),
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text('“${o['sentence']}”', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface, height: 1.5))),
                    const Padding(padding: EdgeInsets.only(top: 2), child: Text('回到原文 ›', style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3))),
                  ],
                ),
              ),
            ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: Go.sp4), child: Text('暂无原文出处', style: TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3))),
        ],
      ),
    );
  }

  Widget _orgSheet() {
    final groups = (_org!['groups'] as List?) ?? [];
    return _sheetShell(
      title: 'AI 整理结果',
      tall: true,
      actions: GestureDetector(
        onTap: () => setState(() => _org = null),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Go.sp3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Go.primary, borderRadius: BorderRadius.circular(Go.rFull)),
          child: const Text('完成', style: TextStyle(fontSize: Go.fsBody, color: Colors.white)),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: Go.sp5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Go.sp3, vertical: 1),
                    decoration: BoxDecoration(color: Go.primary95, borderRadius: BorderRadius.circular(Go.rFull)),
                    child: Text('${g['theme']}', style: const TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: Go.primary)),
                  ),
                  const SizedBox(height: Go.sp2),
                  for (final it in (g['items'] as List? ?? [])) _orgItem(it),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _orgItem(dynamic it) => Container(
        padding: const EdgeInsets.symmetric(vertical: Go.sp3),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Go.outline, width: 0.5))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${it['word']}  ${it['pos'] ?? ''}', style: const TextStyle(fontSize: Go.fsBody, fontWeight: FontWeight.w600, color: Go.onSurface)),
            Text('${it['zh'] ?? ''}', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface)),
            Text('${it['en'] ?? ''}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
            Text('词族：${(it['family'] as List? ?? []).join(', ')}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.primary)),
            Text('e.g. ${it['example'] ?? ''}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3, fontStyle: FontStyle.italic)),
          ],
        ),
      );
}
