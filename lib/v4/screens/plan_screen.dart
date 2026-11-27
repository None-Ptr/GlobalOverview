// Hallmark · screen: plan · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S4 R4 V4 · weakest S — set rows now carry their size on the right edge, no chevron
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/v4/screens/export_screen.dart';
import 'package:global_overview/v4/screens/quiz_screen.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/services/article_repository.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_index_row.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4PlanScreen extends ConsumerStatefulWidget {
  const V4PlanScreen({super.key});

  @override
  ConsumerState<V4PlanScreen> createState() => _V4PlanScreenState();
}

class _V4PlanScreenState extends ConsumerState<V4PlanScreen> {
  static const _defaultConfig = {
    'types': 'choice,fill',
    'count': 5,
  };

  List<Map<String, dynamic>> _articles = const [];
  List<Map<String, dynamic>> _sets = const [];
  Map<String, dynamic>? _preset;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(dbProvider);
      final presets = await db.select('SELECT * FROM presets ORDER BY id ASC');
      final active = await db.select(
        "SELECT value FROM kv WHERE key='activePresetId'",
      );
      final activeId = active.isEmpty ? '' : '${active.first['value']}';
      final picked = presets.where((p) => '${p['id']}' == activeId).toList();
      _preset = picked.isNotEmpty
          ? picked.first
          : (presets.isNotEmpty ? presets.first : null);

      final plan = await db.select('SELECT articleId FROM plan_items');
      final ids = plan.map((p) => '${p['articleId']}').toSet().toList();
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < ids.length; i += 400) {
        final chunk = ids.sublist(i, (i + 400).clamp(0, ids.length));
        final holders = List.filled(chunk.length, '?').join(',');
        rows.addAll(
          await db.select(
            'SELECT id, guid, title, wordCount, '
            '(curated_blocks IS NOT NULL AND length(curated_blocks) > 4) AS hasCurated '
            'FROM articles WHERE id IN ($holders)',
            chunk,
          ),
        );
      }
      rows.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      final sets = await db.select(
        'SELECT s.id, s.articleId, COUNT(q.id) AS qcount FROM question_sets s '
        'LEFT JOIN questions q ON q.setId = s.id GROUP BY s.id',
      );
      if (!mounted) return;
      setState(() {
        _articles = rows;
        _sets = sets;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _setsOf(dynamic articleId) =>
      _sets.where((s) => '${s['articleId']}' == '$articleId').toList();

  List<String> _types() {
    final raw = _preset?['config'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map;
        final types = decoded['types'];
        if (types is List) {
          return types.map((e) => '$e').toList();
        }
        if (types is String) {
          return types
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    return const ['choice', 'fill'];
  }

  int _count() {
    final raw = _preset?['config'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map;
        return int.tryParse('${decoded['count']}') ?? 5;
      } catch (_) {}
    }
    return _defaultConfig['count'] as int;
  }

  Future<String> _articleText(Map<String, dynamic> article) async {
    final rows = await ref.read(dbProvider).select(
      'SELECT plainText, curated_blocks FROM articles WHERE id = ?',
      [article['id']],
    );
    if (rows.isEmpty) return '';
    final row = rows.first;
    final curated = <String>[];
    final raw = row['curated_blocks'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final block in list.whereType<Map>()) {
          if (block['type'] != 'p') continue;
          final text = '${block['text'] ?? ''}';
          if (text.isNotEmpty) curated.add(text);
        }
      } catch (_) {}
    }
    if (curated.isNotEmpty) return curated.join('\n\n');
    return row['plainText'] as String? ?? '';
  }

  Future<void> _generate(Map<String, dynamic> article) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final text = await _articleText(article);
      if (text.trim().isEmpty) {
        throw Exception('这篇文章的正文太短，先读原文再试');
      }
      final types = _types();
      final questions = await ref
          .read(quizProvider)
          .generate(text, types.isEmpty ? 'choice' : types.first, _count());
      final presetName = '${_preset?['name'] ?? ''}'.trim();
      final setId = await ref.read(dbProvider).insertReturnId(
        'INSERT INTO question_sets (articleId, presetId, title, createdAt, label) VALUES (?,?,?,?,?)',
        [
          article['id'],
          _preset?['id'],
          article['title'],
          DateTime.now().millisecondsSinceEpoch,
          presetName.isEmpty ? '计划练习' : presetName,
        ],
      );
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await ref.read(dbProvider).batch([
        for (final q in questions)
          (
            sql:
                'INSERT INTO questions (setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote, createdAt) '
                'VALUES (?,?,?,?,?,?,?,?,?)',
            params: [
              setId,
              q['type'] ?? (types.isEmpty ? 'choice' : types.first),
              q['gradeMode'] ?? 'ai',
              q['prompt'] ?? '',
              jsonEncode(q['options'] ?? []),
              jsonEncode(q['answers'] ?? []),
              q['analysis'] ?? '',
              q['sourceQuote'] ?? '',
              stamp,
            ],
          ),
      ]);
      await _load();
      if (!mounted) return;
      showV4Snack(
        context,
        '已生成 ${questions.length} 道题',
        tone: V4SnackTone.success,
      );
    } catch (e) {
      if (e is AppException && e.code == 'aiCancelled') return;
      if (!mounted) return;
      showV4Snack(context, errText(e), tone: V4SnackTone.error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> article) async {
    final db = ref.read(dbProvider);
    final id = article['id'];
    try {
      await db.execute('DELETE FROM plan_items WHERE articleId = ?', [id]);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '移出失败，请重试', tone: V4SnackTone.error);
      return;
    }
    if (!mounted) return;
    setState(() => _articles = _articles.where((a) => a['id'] != id).toList());
    showV4Snack(
      context,
      '已移出精读单',
      actionLabel: '撤销',
      duration: const Duration(seconds: 5),
      onAction: () async {
        await db.execute(
          'INSERT OR REPLACE INTO plan_items (articleId, addedAt) VALUES (?,?)',
          [id, DateTime.now().millisecondsSinceEpoch],
        );
        ref.read(planRevisionProvider.notifier).bump();
        _load();
      },
    );
    ref.read(planRevisionProvider.notifier).bump();
  }

  Future<void> _openArticle(Map<String, dynamic> article) async {
    final guid = article['guid'] as String?;
    if (guid == null || guid.isEmpty) {
      showV4Snack(context, '这篇文章没有稳定链接', tone: V4SnackTone.warning);
      return;
    }
    final id = await V4ArticleRepository(ref.read(dbProvider)).idByGuid(guid);
    if (!mounted) return;
    if (id == null) {
      showV4Snack(context, '原文还没保存到本机', tone: V4SnackTone.warning);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => V4ReaderScreen(articleId: id)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(planRevisionProvider, (_, _) => _load());
    return V4Page(
      title: '精读单',
      actions: [
        if (_articles.isNotEmpty)
          Text('${_articles.length} 篇', style: context.v4Type.caption),
        const SizedBox(width: V4Space.sm),
      ],
      body: Stack(
        children: [
          _body(),
          if (_generating) _generatingOverlay(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: V4Notice(
          title: '精读单读不出来',
          message: _error!,
          action: V4PrimaryButton(
            onPressed: _load,
            child: const Text('重试'),
          ),
        ),
      );
    }
    if (_articles.isEmpty) {
      return const Center(
        child: V4Notice(
          title: '精读单还是空的',
          message: '在阅读页把想细读的文章加入精读单，就能在这里出题。',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: context.v4.brand,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          V4Space.lg,
          V4Space.sm,
          V4Space.lg,
          V4Space.huge,
        ),
        itemCount: _articles.length,
        separatorBuilder: (_, _) => const SizedBox(height: V4Space.md),
        itemBuilder: (_, i) => _card(_articles[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> article) {
    final v4 = context.v4;
    final type = context.v4Type;
    final sets = _setsOf(article['id']);
    final curated = article['hasCurated'] == 1;
    return Container(
      padding: const EdgeInsets.all(V4Space.lg),
      decoration: BoxDecoration(
        color: v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: v4.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${article['title'] ?? ''}', style: type.itemTitle),
          const SizedBox(height: V4Space.xs),
          Text(
            '${article['wordCount'] ?? 0} 词${curated ? '，有精选版' : ''}',
            style: type.caption,
          ),
          const SizedBox(height: V4Space.md),
          if (sets.isEmpty)
            Text('还没有题集', style: type.caption)
          else
            Column(
              children: [
                for (final s in sets)
                  V4IndexRow(
                    title: '题集 ${s['id']}',
                    trailing: '${s['qcount']} 题',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => V4QuizScreen(setId: s['id'] as int),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: V4Space.md),
          Divider(height: 1, color: v4.rule),
          const SizedBox(height: V4Space.md),
          Row(
            children: [
              Expanded(
                child: V4PrimaryButton(
                  onPressed: _generating ? null : () => _generate(article),
                  child: const Text('生成题集'),
                ),
              ),
            ],
          ),
          const SizedBox(height: V4Space.xs),
          Wrap(
            spacing: V4Space.sm,
            children: [
              TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.text,
                onPressed: () => _openArticle(article),
                child: const Text('原文'),
              ),
              if (sets.isNotEmpty)
                TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.text,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => V4ExportScreen(articleId: article['id'] as int),
                    ),
                  ),
                  child: const Text('导出'),
                ),
              TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.text,
                colorPreset: TButtonColorPreset.danger,
                onPressed: () => _remove(article),
                child: const Text('移出'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _generatingOverlay() {
    final v4 = context.v4;
    return Positioned.fill(
      child: ColoredBox(
        color: v4.page.withValues(alpha: 0.82),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V4Space.xxl,
              vertical: V4Space.xl,
            ),
            decoration: BoxDecoration(
              color: v4.surface,
              borderRadius: BorderRadius.circular(V4Radius.card),
              border: Border.all(color: v4.rule),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: V4Space.md),
                Text('AI 正在出题', style: context.v4Type.label),
                const SizedBox(height: V4Space.xs),
                Text('按预设的题型和数量生成', style: context.v4Type.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
