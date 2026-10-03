import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/screens/article_screen.dart';
import 'package:global_overview/screens/wrong_screen.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

class QuizScreen extends ConsumerStatefulWidget {
  final int? setId;
  final List<int>? ids;
  const QuizScreen({super.key, this.setId, this.ids});
  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  List<Map<String, dynamic>> _questions = [];
  int _idx = 0;
  final Map<int, String> _drafts = {};
  final Map<int, Map<String, dynamic>> _answered = {};
  Map<int, List<Map<String, dynamic>>> _history = {};
  bool _result = false;
  bool _loading = true;
  String _error = '';
  String _articleGuid = '';
  final _pageCtrl = PageController();
  final Map<int, TextEditingController> _inputs = {};
  final Set<int> _debounce = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _gradeLabel(String? g) => {'exact': '精确', 'contains': '包含', 'ai': 'AI判', 'manual': '人工'}[g] ?? (g ?? '');

  String _draftOf(int qid) => _drafts[qid] ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final svc = ref.read(quizProvider);
      _questions = (widget.ids != null && widget.ids!.isNotEmpty) ? await svc.loadQuestionsByIds(widget.ids!) : await svc.loadSet(widget.setId ?? 0);
      final ids = _questions.map((q) => q['id'] as int).toList();
      final d = await ref.read(dbProvider).loadDrafts(ids);
      _drafts.clear();
      d.forEach((k, v) => _drafts[k] = v);
      _history = await ref.read(dbProvider).loadHistory(ids);
      try {
        final firstSetId = _questions.isNotEmpty ? _questions.first['setId'] as int? : null;
        if (firstSetId != null) {
          final setRows = await ref.read(dbProvider).select('SELECT articleId FROM question_sets WHERE id = ?', [firstSetId]);
          final articleId = setRows.isNotEmpty ? setRows.first['articleId'] as int? : null;
          if (articleId != null) {
            final artRows = await ref.read(dbProvider).select('SELECT guid FROM articles WHERE id = ?', [articleId]);
            if (artRows.isNotEmpty) _articleGuid = artRows.first['guid'] as String? ?? '';
          }
        }
      } catch (_) {}
    } catch (e) {
      _error = errText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _lastOf(int qid) {
    final h = _history[qid];
    if (h == null || h.isEmpty) return null;
    return h.last;
  }

  void _setDraft(int qid, String v) {
    _drafts[qid] = v;
    if (_debounce.contains(qid)) return;
    _debounce.add(qid);
    Future.delayed(const Duration(milliseconds: 300), () {
      _debounce.remove(qid);
      if (!mounted) return;
      ref.read(dbProvider).saveDraft(qid, _drafts[qid] ?? '');
    });
  }

  Future<void> _submit() async {
    if (_questions.isEmpty) return;
    if (_result) {
      for (final c in _inputs.values) {
        c.clear();
      }
      setState(() {
        _result = false;
        _answered.clear();
        _drafts.clear();
        _idx = 0;
      });
      _history = await ref.read(dbProvider).loadHistory(_questions.map((q) => q['id'] as int).toList());
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      return;
    }
    final unanswered = _questions.where((q) => _draftOf(q['id'] as int).trim().isEmpty).toList();
    if (unanswered.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('提示'),
          content: Text('还有 ${unanswered.length} 题未作答，仍要交卷？'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('交卷'))],
        ),
      );
      if (go != true) return;
    }
    try {
      final items = _questions.map((q) => {'questionId': q['id'], 'final': _draftOf(q['id'] as int)}).toList();
      final res = await ref.read(gradeProvider).gradeBatch(items);
      for (final r in res.results) {
        _answered[r['questionId'] as int] = {'correct': r['correct'] == true, 'comment': r['comment'], 'status': r['status']};
      }
      await ref.read(dbProvider).clearDrafts(_questions.map((q) => q['id'] as int).toList());
      final graded = res.results.where((r) => r['status'] == 'graded').toList();
      final ok = graded.where((r) => r['correct'] == true).length;
      final rec = await ref.read(habitProvider).recordCompletion(correct: ok, done: graded.length);
      ref.read(habitRevisionProvider.notifier).bump();
      if (!mounted) return;
      setState(() => _result = true);

      final wrongCount = graded.length - ok;
      var content = '正确 $ok / ${res.results.length}';
      if (res.pending > 0) content += '，${res.pending} 题判分未完成，可单独重判';
      if (wrongCount > 0) content += '，错题已入错题本';
      // 放进结果对话框而不是 SnackBar：交卷后可能立刻跳到错题本，SnackBar 会被盖掉。
      if (rec.newBadges.isNotEmpty) {
        content += '\n\n解锁成就：${rec.newBadges.map((b) => b.label).join('、')}';
      }
      final viewWrong = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('判分完成'),
          content: Text(content),
          actions: [
            if (wrongCount > 0) TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('留在本页')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(wrongCount > 0 ? '查看错题' : '好')),
          ],
        ),
      );
      if (viewWrong == true && wrongCount > 0 && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const WrongScreen()));
      }
    } catch (e) {
      if (mounted) {
        showDialog(context: context, builder: (c) => AlertDialog(title: const Text('判分失败'), content: Text(errText(e)), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定'))]));
      }
    }
  }

  Future<void> _retryGrade(int qid) async {
    final res = await ref.read(gradeProvider).gradeBatch([{'questionId': qid, 'final': _draftOf(qid)}]);
    final r = res.results.isNotEmpty ? res.results.first : null;
    if (r != null && mounted) {
      setState(() => _answered[qid] = {'correct': r['correct'] == true, 'comment': r['comment'], 'status': r['status']});
    }
  }

  void _openSource() {
    if (_articleGuid.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(guid: _articleGuid, quiz: true)));
  }

  @override
  Widget build(BuildContext context) {
    return GoPage(
      topPad: false,
      child: Column(
        children: [
          GoAppBar(
            title: _questions.isNotEmpty ? '${_idx + 1} / ${_questions.length}' : '0 / 0',
            style: GoAppBarStyle.floating,
            leading: GoBack(),
            actions: [_questions.isEmpty ? const SizedBox.shrink() : GestureDetector(onTap: _submit, child: Text(_result ? '重做' : '交卷', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.primary, fontWeight: FontWeight.w600)))],
          ),
          Expanded(child: _body()),
          if (_questions.isNotEmpty) _nav(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [PolySpinner(), SizedBox(height: Go.sp6), Text('加载中…', style: TextStyle(color: Go.onSurface3, fontSize: Go.fsBodySm))]));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error, style: const TextStyle(color: Go.danger, fontSize: Go.fsBodySm)),
          const SizedBox(height: Go.sp3),
          GestureDetector(onTap: _load, child: const Text('重试', style: TextStyle(color: Go.primary, fontSize: Go.fsBodySm))),
        ]),
      );
    }
    if (_questions.isEmpty) {
      return const Center(
        child: GoEmpty(icon: 'book', title: '这里还没有题目', desc: '去「计划」页给文章生成一份题集吧'),
      );
    }
    return PageView(
      controller: _pageCtrl,
      onPageChanged: (i) => setState(() => _idx = i),
      children: [for (final q in _questions) _questionView(q)],
    );
  }

  Widget _questionView(Map<String, dynamic> q) {
    final qid = q['id'] as int;
    final type = q['type'] as String?;
    final hist = _history[qid];
    final last = _lastOf(qid);
    final answered = _answered[qid];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Go.sp6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Go.sp2,
            runSpacing: Go.sp2,
            children: [
              _tag(QuizService.typeLabel(type)),
              _tag(_gradeLabel(q['gradeMode'] as String?), grade: true),
              if (hist != null && hist.isNotEmpty) _tag('第 ${hist.length + 1} 次作答', hist: true),
            ],
          ),
          const SizedBox(height: Go.sp4),
          Text('${q['prompt']}', style: const TextStyle(fontSize: Go.fsBody, height: Go.lhNormal, color: Go.onSurface)),
          const SizedBox(height: Go.sp6),
          GestureDetector(
            onTap: _openSource,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp2),
              decoration: BoxDecoration(color: Go.surface2, border: Border.all(color: Go.outline, width: 0.5), borderRadius: BorderRadius.circular(Go.rFull)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const GoIcon('book-open', size: 17, color: Go.primary),
                const SizedBox(width: Go.sp2),
                const Text('回到原文', style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: Go.primary)),
              ]),
            ),
          ),
          const SizedBox(height: Go.sp6),
          if (last != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp3),
              margin: const EdgeInsets.only(bottom: Go.sp5),
              decoration: BoxDecoration(color: Go.warning.withValues(alpha: 0.08), border: const Border(left: BorderSide(color: Go.warning, width: 3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('上次作答（${last['correct'] == 1 ? '正确' : '错误'}）', style: const TextStyle(fontSize: Go.fsMeta, color: Go.warning)),
                  Text((last['final'] as String?)?.isNotEmpty == true ? '${last['final']}' : '（未作答）', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3, height: Go.lhNormal)),
                  if ('${last['comment'] ?? ''}'.isNotEmpty) Text('${last['comment']}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
                ],
              ),
            ),
          if (type == 'choice')
            Column(
              children: [
                for (final o in (q['options'] as List))
                  GestureDetector(
                    onTap: () {
                      _setDraft(qid, '$o');
                      ref.read(dbProvider).saveDraft(qid, '$o');
                      setState(() {});
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: Go.sp3),
                      padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp5),
                      decoration: BoxDecoration(
                        color: _draftOf(qid) == '$o' ? Go.primary95 : Go.surface,
                        borderRadius: BorderRadius.circular(Go.rMd),
                        border: Border(
                          top: BorderSide(color: _draftOf(qid) == '$o' ? Go.primary : Go.outline, width: 0.5),
                          right: BorderSide(color: _draftOf(qid) == '$o' ? Go.primary : Go.outline, width: 0.5),
                          bottom: BorderSide(color: _draftOf(qid) == '$o' ? Go.primary : Go.outline, width: 0.5),
                          left: BorderSide(color: _draftOf(qid) == '$o' ? Go.primary : Go.outline, width: _draftOf(qid) == '$o' ? 3 : 0.5),
                        ),
                      ),
                      child: Text('$o', style: TextStyle(fontSize: Go.fsBodySm, color: _draftOf(qid) == '$o' ? Go.onPrimaryContainer : Go.onSurface, fontWeight: _draftOf(qid) == '$o' ? FontWeight.w600 : FontWeight.w400)),
                    ),
                  ),
              ],
            )
          else if (type == 'fill')
            TextField(
              controller: _inputs.putIfAbsent(qid, () => TextEditingController(text: _draftOf(qid))),
              onChanged: (v) {
                _setDraft(qid, v);
                setState(() {});
              },
              style: const TextStyle(fontSize: Go.fsBody, color: Go.onSurface),
              decoration: _inputDecoration('输入答案'),
            )
          else
            TextField(
              controller: _inputs.putIfAbsent(qid, () => TextEditingController(text: _draftOf(qid))),
              maxLines: 6,
              onChanged: (v) {
                _setDraft(qid, v);
                setState(() {});
              },
              style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface),
              decoration: _inputDecoration('输入答案'),
            ),
          if (_result && answered != null) ...[
            const SizedBox(height: Go.sp6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Go.sp5),
              decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rMd), border: Border.all(color: Go.outline, width: 0.5), boxShadow: Go.elev1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        answered['status'] == 'pending' ? '判分未完成' : (answered['correct'] == true ? '正确' : '错误'),
                        style: TextStyle(fontSize: Go.fsBodySm, fontWeight: FontWeight.w600, color: answered['status'] == 'pending' ? Go.warning : (answered['correct'] == true ? Go.success : Go.danger)),
                      ),
                      if (answered['status'] == 'pending')
                        Padding(padding: const EdgeInsets.only(left: Go.sp3), child: GestureDetector(onTap: () => _retryGrade(qid), child: const Text('重新判分', style: TextStyle(fontSize: Go.fsMeta, color: Go.primary)))),
                    ],
                  ),
                  if ('${answered['comment'] ?? ''}'.isNotEmpty) Text('${answered['comment']}', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3)),
                  Padding(
                    padding: const EdgeInsets.only(top: Go.sp2),
                    child: Text('参考答案：${(q['answerList'] as List).join(' / ')}', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.success)),
                  ),
                  if ('${q['analysis'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Go.sp1), child: Text('${q['analysis']}', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3, height: Go.lhNormal))),
                ],
              ),
            ),
          ],
          const SizedBox(height: Go.sp8),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Go.onSurfaceDisabled),
        filled: true,
        fillColor: Go.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Go.rMd), borderSide: const BorderSide(color: Go.outline, width: 0.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Go.rMd), borderSide: const BorderSide(color: Go.outline, width: 0.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Go.rMd), borderSide: const BorderSide(color: Go.primary, width: 1)),
      );

  Widget _tag(String label, {bool grade = false, bool hist = false}) {
    final Color bg = hist ? Go.warning.withValues(alpha: 0.18) : (grade ? Go.primary95 : Go.surface2);
    final Color fg = hist ? Go.warning : (grade ? Go.primary : Go.onSurface3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Go.rFull)),
      child: Text(label, style: TextStyle(fontSize: Go.fsMeta, color: fg)),
    );
  }

  Widget _nav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp3),
      decoration: const BoxDecoration(color: Go.bg, border: Border(top: BorderSide(color: Go.outline, width: 0.5))),
      child: SizedBox(
        height: Go.r(56),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < _questions.length; i++) _navDot(_questions[i], i),
          ],
        ),
      ),
    );
  }

  Widget _navDot(Map<String, dynamic> q, int i) {
    final a = _answered[q['id'] as int];
    final cur = i == _idx;
    final done = _draftOf(q['id'] as int).isNotEmpty;
    Color bg = Go.surface2;
    Color fg = Go.onSurface3;
    if (cur) {
      bg = Go.primary;
      fg = Go.onPrimary;
    } else if (_result && a != null) {
      if (a['status'] == 'pending') {
        bg = Go.warning;
        fg = Go.onWarning;
      } else if (a['correct'] == true) {
        bg = Go.success;
        fg = Go.onSuccess;
      } else {
        bg = Go.danger;
        fg = Go.onDanger;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(right: Go.sp2),
      child: GestureDetector(
        onTap: () {
          setState(() => _idx = i);
          if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(i);
        },
        child: Container(
          width: Go.r(56),
          height: Go.r(56),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Go.rSm),
            border: !cur && done ? Border.all(color: Go.outlineStrong, width: 1) : null,
          ),
          child: Text('${i + 1}', style: TextStyle(fontSize: Go.fsMeta, color: fg)),
        ),
      ),
    );
  }
}
