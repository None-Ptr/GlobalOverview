// Hallmark · screen: quiz · genre: editorial · theme: custom (observation station) · scope: app
// critique: P4 H5 E5 S4 R4 V4 · weakest S — the verdict is a record, not a scoreboard; the receipt carries the facts
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/screens/wrong_screen.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4QuizScreen extends ConsumerStatefulWidget {
  final int? setId;
  final List<int>? ids;

  const V4QuizScreen({super.key, this.setId, this.ids});

  @override
  ConsumerState<V4QuizScreen> createState() => _V4QuizScreenState();
}

class _V4QuizScreenState extends ConsumerState<V4QuizScreen> {
  List<Map<String, dynamic>> _questions = const [];
  final Map<int, String> _drafts = {};
  final Map<int, Map<String, dynamic>> _answered = {};
  final Map<int, TextEditingController> _inputs = {};
  final Set<int> _saving = {};
  final PageController _pages = PageController();

  Map<int, List<Map<String, dynamic>>> _history = const {};
  int _idx = 0;
  int _articleId = 0;
  bool _result = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _draftOf(int id) => _drafts[id] ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(quizProvider);
      final ids = widget.ids;
      final questions = (ids != null && ids.isNotEmpty)
          ? await svc.loadQuestionsByIds(ids)
          : await svc.loadSet(widget.setId ?? 0);
      final qids = questions.map((q) => q['id'] as int).toList();
      final drafts = await ref.read(dbProvider).loadDrafts(qids);
      final history = await ref.read(dbProvider).loadHistory(qids);
      final articleId = await _articleOf(questions);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _drafts
          ..clear()
          ..addAll(drafts);
        _history = history;
        _articleId = articleId;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<int> _articleOf(List<Map<String, dynamic>> questions) async {
    if (questions.isEmpty) return 0;
    final setId = questions.first['setId'] as int?;
    if (setId == null) return 0;
    final sets = await ref
        .read(dbProvider)
        .select('SELECT articleId FROM question_sets WHERE id = ?', [setId]);
    if (sets.isEmpty) return 0;
    return (sets.first['articleId'] as num?)?.toInt() ?? 0;
  }

  void _setDraft(int id, String value) {
    _drafts[id] = value;
    if (_saving.contains(id)) return;
    _saving.add(id);
    Future.delayed(const Duration(milliseconds: 300), () {
      _saving.remove(id);
      if (!mounted) return;
      ref.read(dbProvider).saveDraft(id, _drafts[id] ?? '');
    });
  }

  Future<void> _submit() async {
    if (_questions.isEmpty) return;
    if (_result) {
      for (final c in _inputs.values) {
        c.clear();
      }
      final history = await ref
          .read(dbProvider)
          .loadHistory(_questions.map((q) => q['id'] as int).toList());
      if (!mounted) return;
      setState(() {
        _result = false;
        _answered.clear();
        _drafts.clear();
        _history = history;
        _idx = 0;
      });
      if (_pages.hasClients) _pages.jumpToPage(0);
      return;
    }
    final blank = _questions
        .where((q) => _draftOf(q['id'] as int).trim().isEmpty)
        .length;
    if (blank > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('还有题没答'),
          content: Text('还剩 $blank 题没写答案，仍然交卷？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('继续作答'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('交卷'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    try {
      final items = _questions
          .map((q) => {'questionId': q['id'], 'final': _draftOf(q['id'] as int)})
          .toList();
      final res = await ref.read(gradeProvider).gradeBatch(items);
      for (final r in res.results) {
        _answered[r['questionId'] as int] = {
          'correct': r['correct'] == true,
          'comment': r['comment'],
          'status': r['status'],
        };
      }
      await ref
          .read(dbProvider)
          .clearDrafts(_questions.map((q) => q['id'] as int).toList());
      final graded = res.results.where((r) => r['status'] == 'graded').toList();
      final ok = graded.where((r) => r['correct'] == true).length;
      final rec = await ref
          .read(habitProvider)
          .recordCompletion(correct: ok, done: graded.length);
      ref.read(habitRevisionProvider.notifier).bump();
      if (!mounted) return;
      setState(() => _result = true);
      await _showResult(
        pending: res.pending,
        total: res.results.length,
        ok: ok,
        wrong: graded.length - ok,
        xp: rec.xpGained,
        streak: rec.streak,
        levelUp: rec.levelUp,
        level: rec.level,
        badges: rec.newBadges.map((b) => b.label).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('判分没成功'),
          content: Text(errText(e)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showResult({
    required int pending,
    required int total,
    required int ok,
    required int wrong,
    required int xp,
    required int streak,
    required bool levelUp,
    required int level,
    required List<String> badges,
  }) async {
    final v4 = context.v4;
    final type = context.v4Type;
    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: V4Space.md),
          child: Row(
            children: [
              Expanded(child: Text(label, style: type.caption)),
              Text(value, style: type.label.copyWith(color: v4.ink)),
            ],
          ),
        );

    final viewWrong = await showDialog<bool>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: v4.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V4Radius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(V4Space.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '交卷记录',
                  style: type.caption.copyWith(color: v4.inkMuted),
                ),
                const SizedBox(height: V4Space.sm),
                Text('答对 $ok / $total', style: type.displayNumber),
                const SizedBox(height: V4Space.lg),
                Container(height: 1, color: v4.rule),
                const SizedBox(height: V4Space.lg),
                fact('待判', '$pending 题'),
                fact('错题', '$wrong 题'),
                if (xp > 0) fact('见闻', '+$xp'),
                if (streak > 0) fact('连续', '$streak 天'),
                if (levelUp)
                  fact('等级', 'Lv.$level'),
                if (badges.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: V4Space.xs),
                    child: Text(
                      '解锁成就 ${badges.join('、')}',
                      style: type.caption,
                    ),
                  ),
                const SizedBox(height: V4Space.lg),
                Row(
                  children: [
                    if (wrong > 0)
                      Expanded(
                        child: TButton(
                          size: TButtonSize.large,
                          variant: TButtonVariant.outline,
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('留在本页'),
                        ),
                      ),
                    if (wrong > 0) const SizedBox(width: V4Space.md),
                    Expanded(
                      child: V4PrimaryButton(
                        onPressed: () => Navigator.pop(c, wrong > 0),
                        child: Text(wrong > 0 ? '查看错题' : '好'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (viewWrong == true && wrong > 0 && mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const V4WrongScreen()));
    }
  }

  Future<void> _retry(int id) async {
    final res = await ref.read(gradeProvider).gradeBatch([
      {'questionId': id, 'final': _draftOf(id)},
    ]);
    if (res.results.isEmpty || !mounted) return;
    final r = res.results.first;
    setState(() {
      _answered[id] = {
        'correct': r['correct'] == true,
        'comment': r['comment'],
        'status': r['status'],
      };
    });
  }

  Future<void> _manualGrade(int id, bool correct) async {
    try {
      await ref.read(gradeProvider).gradeManually(id, correct);
      if (!mounted) return;
      setState(() {
        _answered[id] = {
          'correct': correct,
          'comment': correct ? '人工判为正确' : '人工判为错误',
          'status': 'graded',
        };
      });
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '没记上，请重试', tone: V4SnackTone.error);
    }
  }

  void _openSource() {
    if (_articleId == 0) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => V4ReaderScreen(articleId: _articleId)));
  }

  @override
  Widget build(BuildContext context) {
    final total = _questions.length;
    return V4Page(
      title: total == 0 ? '题目' : '${_idx + 1} / $total',
      actions: [
        if (total > 0)
          TButton(
            size: TButtonSize.large,
            variant: TButtonVariant.text,
            onPressed: _submit,
            child: Text(_result ? '重做' : '交卷'),
          ),
        const SizedBox(width: V4Space.sm),
      ],
      bottomBar: total == 0 ? null : _indexStrip(),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: V4Notice(
          title: '题目读不出来',
          message: _error!,
          action: V4PrimaryButton(
            onPressed: _load,
            child: const Text('重试'),
          ),
        ),
      );
    }
    if (_questions.isEmpty) {
      return Center(
        child: V4Notice(
          title: '这里还没有题目',
          message: '去精读单给文章生成一份题集，题目会出现在这里。',
        ),
      );
    }
    // Build pages on demand: 20 questions mean 20 text fields, and building
    // every one up front is work the reader never sees.
    return PageView.builder(
      controller: _pages,
      itemCount: _questions.length,
      onPageChanged: (i) => setState(() => _idx = i),
      itemBuilder: (_, i) => _question(_questions[i]),
    );
  }

  Widget _question(Map<String, dynamic> q) {
    final v4 = context.v4;
    final type = context.v4Type;
    final id = q['id'] as int;
    final kind = q['type'] as String?;
    final history = _history[id] ?? const [];
    final last = history.isEmpty ? null : history.last;
    final answered = _answered[id];
    final picked = _draftOf(id);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        V4Space.lg,
        V4Space.sm,
        V4Space.lg,
        V4Space.huge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: V4Space.sm,
            runSpacing: V4Space.sm,
            children: [
              _tag(QuizService.typeLabel(kind), v4.inkMuted),
              _tag(_gradeLabel(q['gradeMode'] as String?), v4.brand),
              if (history.isNotEmpty) _tag('第 ${history.length + 1} 次', v4.warning),
            ],
          ),
          const SizedBox(height: V4Space.lg),
          Text('${q['prompt']}', style: type.body),
          if (_articleId != 0) ...[
            const SizedBox(height: V4Space.md),
            TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.text,
              onPressed: _openSource,
              child: const Text('回到原文'),
            ),
          ],
          if (last != null) ...[
            const SizedBox(height: V4Space.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(V4Space.md),
              decoration: BoxDecoration(
                color: v4.surfaceSubtle,
                borderRadius: BorderRadius.circular(V4Radius.control),
                border: Border(left: BorderSide(color: v4.warning, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '上次作答  ${last['correct'] == 1 ? '正确' : '错误'}',
                    style: type.caption.copyWith(color: v4.warning),
                  ),
                  const SizedBox(height: V4Space.xs),
                  Text(
                    '${last['final'] ?? ''}'.isEmpty
                        ? '（未作答）'
                        : '${last['final']}',
                    style: type.label,
                  ),
                  if ('${last['comment'] ?? ''}'.isNotEmpty)
                    Text('${last['comment']}', style: type.caption),
                ],
              ),
            ),
          ],
          const SizedBox(height: V4Space.lg),
          if (kind == 'choice')
            for (final option in (q['options'] as List))
              _option('$option', picked == '$option', () {
                _setDraft(id, '$option');
                ref.read(dbProvider).saveDraft(id, '$option');
                setState(() {});
              })
          else
            TextField(
              controller: _inputs.putIfAbsent(
                id,
                () => TextEditingController(text: picked),
              ),
              maxLines: kind == 'fill' ? 1 : 6,
              minLines: 1,
              onChanged: (v) {
                _setDraft(id, v);
                setState(() {});
              },
              style: type.body,
              decoration: InputDecoration(
                hintText: '在这里写答案',
                hintStyle: type.caption,
                filled: true,
                fillColor: v4.surface,
                contentPadding: const EdgeInsets.all(V4Space.md),
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
          if (_result && answered != null) ...[
            const SizedBox(height: V4Space.lg),
            _verdict(q, answered),
          ],
        ],
      ),
    );
  }

  Widget _option(String label, bool picked, VoidCallback onTap) {
    final v4 = context.v4;
    return Padding(
      padding: const EdgeInsets.only(bottom: V4Space.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V4Radius.control),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: V4Space.md,
            vertical: V4Space.md,
          ),
          decoration: BoxDecoration(
            color: picked ? v4.surfaceSubtle : v4.surface,
            borderRadius: BorderRadius.circular(V4Radius.control),
            border: Border.all(
              color: picked ? v4.brand : v4.rule,
              width: picked ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: context.v4Type.label.copyWith(
              color: picked ? v4.ink : v4.inkSecondary,
              fontWeight: picked ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _verdict(Map<String, dynamic> q, Map<String, dynamic> answered) {
    final v4 = context.v4;
    final type = context.v4Type;
    final pending = answered['status'] == 'pending';
    final correct = answered['correct'] == true;
    final color = pending ? v4.warning : (correct ? v4.success : v4.error);
    final manual = q['gradeMode'] == 'manual';
    final quote = '${q['sourceQuote'] ?? ''}'.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(V4Space.lg),
      decoration: BoxDecoration(
        color: v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: v4.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                pending
                    ? (manual ? '待人工判分' : '待判分')
                    : (correct ? '答对了' : '答错了'),
                style: type.itemTitle.copyWith(color: color),
              ),
              if (pending && !manual) ...[
                const SizedBox(width: V4Space.sm),
                TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.text,
                  onPressed: () => _retry(q['id'] as int),
                  child: const Text('重新判分'),
                ),
              ],
            ],
          ),
          if ('${answered['comment'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: V4Space.xs),
            Text('${answered['comment']}', style: type.label),
          ],
          if (manual && pending) ...[
            const SizedBox(height: V4Space.md),
            Text(
              '人工判定',
              style: type.caption.copyWith(color: v4.inkMuted),
            ),
            const SizedBox(height: V4Space.xs),
            Row(
              children: [
                Expanded(
                  child: TButton(
                    size: TButtonSize.large,
                    variant: TButtonVariant.outline,
                    onPressed: () => _manualGrade(q['id'] as int, true),
                    child: const Text('判为正确'),
                  ),
                ),
                const SizedBox(width: V4Space.sm),
                Expanded(
                  child: TButton(
                    size: TButtonSize.large,
                    variant: TButtonVariant.outline,
                    onPressed: () => _manualGrade(q['id'] as int, false),
                    child: const Text('判为错误'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: V4Space.sm),
          Text(
            '参考答案 ${(q['answerList'] as List).join(' / ')}',
            style: type.label.copyWith(color: v4.success),
          ),
          if ('${q['analysis'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: V4Space.sm),
            Text('${q['analysis']}', style: type.caption),
          ],
          // The sentence the answer rests on, so the verdict can be checked
          // against the article instead of trusted.
          if (quote.isNotEmpty) ...[
            const SizedBox(height: V4Space.md),
            Container(height: 1, color: v4.rule),
            const SizedBox(height: V4Space.md),
            Text('原文出处', style: type.caption.copyWith(color: v4.inkMuted)),
            const SizedBox(height: V4Space.xs),
            Text(
              '“$quote”',
              style: type.label.copyWith(color: v4.inkSecondary, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String label, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: V4Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: context.v4.surfaceSubtle,
        borderRadius: BorderRadius.circular(V4Radius.control),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, height: 1.4, color: fg),
      ),
    );
  }

  Widget _indexStrip() {
    final v4 = context.v4;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _questions.length,
        separatorBuilder: (_, _) => const SizedBox(width: V4Space.sm),
        itemBuilder: (_, i) {
          final id = _questions[i]['id'] as int;
          final answered = _answered[id];
          final current = i == _idx;
          var bg = v4.surfaceSubtle;
          var fg = v4.inkMuted;
          if (current) {
            bg = v4.brand;
            fg = v4.onBrand;
          } else if (_result && answered != null) {
            if (answered['status'] == 'pending') {
              bg = v4.warning;
              fg = v4.onBrand;
            } else if (answered['correct'] == true) {
              bg = v4.success;
              fg = v4.onBrand;
            } else {
              bg = v4.error;
              fg = v4.onBrand;
            }
          } else if (_draftOf(id).isNotEmpty) {
            bg = v4.surfaceSubtle;
            fg = v4.ink;
          }
          return InkWell(
            onTap: () {
              setState(() => _idx = i);
              if (_pages.hasClients) _pages.jumpToPage(i);
            },
            borderRadius: BorderRadius.circular(V4Radius.control),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(V4Radius.control),
                border: Border.all(
                  color: current ? v4.brand : v4.rule,
                ),
              ),
              child: Text(
                '${i + 1}',
                style: TextStyle(fontSize: 14, height: 1.4, color: fg),
              ),
            ),
          );
        },
      ),
    );
  }

  String _gradeLabel(String? mode) =>
      {'exact': '精确判分', 'contains': '包含判分', 'ai': 'AI 判分', 'manual': '人工判分'}[mode] ??
      'AI 判分';
}
