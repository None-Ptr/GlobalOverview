import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 导出页：1:1 对齐 legacy/src/pages/export/export.vue
class ExportScreen extends ConsumerStatefulWidget {
  final int? setId;
  final int? articleId;
  final bool wrong;
  const ExportScreen({super.key, this.setId, this.articleId, this.wrong = false});
  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

const _defaultTemplate = '''<!-- 导出模板（HTML）。可用变量：title、subtitle、date、count；questions 循环内可用
     index、type、prompt、options、answer、analysis、sourceQuote、mine，
     以及 showAnswer / showAnalysis / showMine / showQuote 四个开关。 -->
<h1>{{title}}</h1>
<p>{{subtitle}}</p>
<ol>
{{#each questions}}
  <li>
    <p>{{prompt}}</p>
    {{#if showAnswer}}<p>答案：{{answer}}</p>{{/if}}
    {{#if showAnalysis}}<p>解析：{{analysis}}</p>{{/if}}
  </li>
{{/each}}
</ol>''';

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String _mode = 'set';
  int _setId = 0;
  int _articleId = 0;
  List<Map<String, dynamic>> _setList = [];
  List<Map<String, dynamic>> _questions = [];
  final _tpl = TextEditingController();
  final _switches = {'answer': true, 'analysis': true, 'mine': false, 'quote': true, 'article': true};
  bool _busy = false;
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.wrong ? 'wrong' : 'set';
    _setId = widget.setId ?? 0;
    _articleId = widget.articleId ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _tpl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadTemplate();
    if (_articleId != 0) {
      _setList = await ref.read(dbProvider).select('SELECT id, title FROM question_sets WHERE articleId = ? ORDER BY id ASC', [_articleId]);
      if (_setList.isNotEmpty && _setId == 0) _setId = _setList.first['id'] as int;
    }
    await _refresh();
    if (mounted) setState(() => _inited = true);
  }

  Future<void> _loadTemplate() async {
    try {
      final rows = await ref.read(dbProvider).select("SELECT source FROM templates WHERE name = 'default' LIMIT 1");
      _tpl.text = rows.isNotEmpty && rows.first['source'] != null ? rows.first['source'] as String : _defaultTemplate;
    } catch (_) {
      _tpl.text = _defaultTemplate;
    }
  }

  Future<void> _refresh() async {
    try {
      if (_mode == 'wrong') {
        _questions = await _loadWrong();
      } else if (_setId != 0) {
        _questions = await ref.read(quizProvider).loadSet(_setId);
      } else {
        _questions = [];
      }
    } catch (e) {
      _questions = [];
    }
    if (mounted) setState(() {});
  }

  Future<List<Map<String, dynamic>>> _loadWrong() async {
    final db = ref.read(dbProvider);
    final questions = await db.select('SELECT * FROM questions ORDER BY id ASC');
    final answers = await db.select('SELECT * FROM answers ORDER BY gradedAt DESC');
    final latest = <int, Map<String, dynamic>>{};
    for (final a in answers) {
      latest.putIfAbsent(a['questionId'] as int, () => a);
    }
    final out = <Map<String, dynamic>>[];
    for (final q in questions) {
      final a = latest[q['id'] as int];
      if (a == null) continue;
      if ((a['wrong'] as int? ?? 0) != 1 && a['status'] != 'pending') continue;
      List<dynamic> ans = [];
      try {
        ans = jsonDecode(q['answers'] as String? ?? '[]');
      } catch (_) {}
      List<dynamic> opts = [];
      try {
        opts = jsonDecode(q['options'] as String? ?? '[]');
      } catch (_) {}
      out.add({'id': q['id'], 'prompt': q['prompt'], 'options': opts, 'answerList': ans, 'analysis': q['analysis'], 'sourceQuote': q['sourceQuote'], 'final': a['final']});
    }
    return out;
  }

  String _currentTitle() {
    if (_mode == 'wrong') return '错题本练习';
    final s = _setList.where((x) => x['id'] == _setId).toList();
    return (s.isNotEmpty && '${s.first['title'] ?? ''}'.isNotEmpty) ? '${s.first['title']}' : '题集 #$_setId';
  }

  Future<void> _doExport() async {
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可导出的题目')));
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var articleTitle = '';
      var articleBody = '';
      if (_mode == 'set' && _articleId != 0) {
        final rows = await ref.read(dbProvider).select('SELECT title, plainText FROM articles WHERE id = ?', [_articleId]);
        if (rows.isNotEmpty) {
          articleTitle = rows.first['title'] as String? ?? '';
          articleBody = rows.first['plainText'] as String? ?? '';
        }
      }
      await ref.read(exportProvider).exportQuestions(
            title: _currentTitle(),
            subtitle: _mode == 'wrong' ? '错题重练' : '',
            questions: _questions,
            withAnswer: _switches['answer'] == true,
            withAnalysis: _switches['analysis'] == true,
            withMine: _switches['mine'] == true,
            withQuote: _switches['quote'] == true,
            articleTitle: articleTitle,
            articleBody: articleBody,
            withArticle: _mode == 'set' && _switches['article'] == true,
          );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：${errText(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTpl() async {
    await ref.read(dbProvider).execute("INSERT OR REPLACE INTO templates (name, source) VALUES ('default', ?)", [_tpl.text]);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模板已保存')));
  }

  Future<void> _resetTpl() async {
    _tpl.text = _defaultTemplate;
    await ref.read(dbProvider).execute("DELETE FROM templates WHERE name = 'default'");
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GoPage(
      topPad: false,
      child: Column(
        children: [
          GoAppBar(title: '导出', style: GoAppBarStyle.floating, leading: GoBack()),
          Expanded(
            child: !_inited
                ? const Center(child: PolySpinner())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp4, Go.sp5, Go.sp6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section('导出内容', [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp2, Go.sp5, Go.sp5),
                            child: Wrap(
                              spacing: Go.sp3,
                              children: [
                                _chip('题集', _mode == 'set', () => setState(() {
                                      _mode = 'set';
                                      _refresh();
                                    })),
                                _chip('错题本', _mode == 'wrong', () => setState(() {
                                      _mode = 'wrong';
                                      _refresh();
                                    })),
                              ],
                            ),
                          ),
                          if (_mode == 'wrong')
                            const Padding(padding: EdgeInsets.fromLTRB(Go.sp5, 0, Go.sp5, Go.sp4), child: Text('合并当前全部错题为一份练习', style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3))),
                          if (_mode == 'set' && _setList.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp2, Go.sp5, Go.sp5),
                              child: Wrap(
                                spacing: Go.sp3,
                                runSpacing: Go.sp2,
                                children: [
                                  for (final s in _setList)
                                    _chip('${s['title'] ?? '题集 #${s['id']}'}', _setId == s['id'], () => setState(() {
                                          _setId = s['id'] as int;
                                          _refresh();
                                        }), primary: true),
                                ],
                              ),
                            ),
                          Padding(padding: const EdgeInsets.fromLTRB(Go.sp5, 0, Go.sp5, Go.sp4), child: Text('共 ${_questions.length} 题', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3))),
                        ]),
                        _section('包含项开关', [
                          _switchRow('含参考答案', 'answer'),
                          _switchRow('含解析', 'analysis'),
                          _switchRow('含我的作答', 'mine'),
                          _switchRow('含原文引用', 'quote'),
                          if (_mode == 'set') _switchRow('含原文', 'article', last: true),
                        ]),
                        _section('模板源码（建议勿动）', [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp2, Go.sp5, 0),
                            child: TextField(
                              controller: _tpl,
                              maxLines: 8,
                              style: const TextStyle(fontSize: Go.fsMeta, height: 1.5, color: Go.onSurface),
                              decoration: InputDecoration(
                                hintText: '模板源码',
                                filled: true,
                                fillColor: Go.surface2,
                                contentPadding: const EdgeInsets.all(Go.sp3),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Go.rMd), borderSide: const BorderSide(color: Go.outline, width: 0.5)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Go.rMd), borderSide: const BorderSide(color: Go.outline, width: 0.5)),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp3, Go.sp5, Go.sp4),
                            child: Row(
                              children: [
                                GestureDetector(onTap: _resetTpl, child: const Text('恢复默认', style: TextStyle(fontSize: Go.fsBodySm, color: Go.primary))),
                                const SizedBox(width: Go.sp6),
                                GestureDetector(onTap: _saveTpl, child: const Text('保存模板', style: TextStyle(fontSize: Go.fsBodySm, color: Go.primary))),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(Go.sp5, 0, Go.sp5, Go.sp5),
                            child: Text(
                              'tips：可用变量：title、subtitle、date、count；questions 循环内可用 index、type、prompt、options、answer、analysis、sourceQuote、mine，以及 showAnswer / showAnalysis / showMine / showQuote 四个开关（由上方开关控制是否渲染）。',
                              style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3, height: Go.lhNormal),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp4),
            decoration: BoxDecoration(color: Go.surfaceRaised.withValues(alpha: 0.86), border: const Border(top: BorderSide(color: Go.outline, width: 0.5))),
            child: Row(
              children: [
                Expanded(
                  child: GoBtn(
                    label: '预览',
                    kind: GoBtnKind.tonal,
                    block: true,
                    onTap: () {
                      if (_questions.isEmpty) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已渲染 ${_questions.length} 题，点「导出 PDF」查看完整排版。')));
                    },
                  ),
                ),
                const SizedBox(width: Go.sp4),
                Expanded(child: GoBtn(label: '导出 PDF', block: true, onTap: _doExport)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: Go.sp6),
        decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), border: Border.all(color: Go.outline, width: 0.5), boxShadow: Go.elev1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Go.sp5, Go.sp2, Go.sp5, Go.sp1),
              child: Text(title.toUpperCase(), style: const TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Go.onSurface3)),
            ),
            ...children,
          ],
        ),
      );

  Widget _chip(String label, bool on, VoidCallback onTap, {bool primary = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Go.sp6, vertical: Go.sp2),
          decoration: BoxDecoration(
            color: on ? (primary ? Go.primary95 : Go.primary) : Go.surface2,
            borderRadius: BorderRadius.circular(Go.rFull),
          ),
          child: Text(label, style: TextStyle(fontSize: Go.fsMeta, color: on ? (primary ? Go.primary : Go.onPrimary) : Go.onSurface2)),
        ),
      );

  Widget _switchRow(String label, String key, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp4),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Go.outline, width: 0.5))),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface)),
            const Spacer(),
            GoSwitch(value: _switches[key] == true, onChanged: (v) => setState(() => _switches[key] = v)),
          ],
        ),
      );
}
