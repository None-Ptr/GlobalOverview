import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/screens/quiz_screen.dart';
import 'package:global_overview/screens/export_screen.dart';
import 'package:global_overview/screens/article_screen.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_icon.dart';
import 'package:global_overview/widgets/go_ui.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});
  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _sets = [];
  List<Map<String, dynamic>> _presets = [];
  Map<String, dynamic>? _activePreset;
  bool _genning = false;
  bool _showPreset = false;
  bool _loading = true;
  String _globalGoal = 'CET6';

  static const _defaultForm = {'name': '', 'exam': 'CET6', 'types': 'choice,fill', 'focus': '词汇、句意理解', 'analysisLang': 'zh', 'count': 5};
  final _form = <String, dynamic>{..._defaultForm};
  final _examKeys = QuizService.examLevels.keys.toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _loadGoal() async {
    final goalRows = await ref.read(dbProvider).select("SELECT value FROM kv WHERE key='targetLevel'");
    if (goalRows.isEmpty) return;
    var v = goalRows.first['value'] as String? ?? 'CET6';
    if (v == '考研') v = 'NCEE';
    if (!QuizService.examLevels.containsKey(v)) return;
    if (mounted) {
      setState(() => _globalGoal = v);
    } else {
      _globalGoal = v;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = ref.read(dbProvider);
      await _loadGoal();
      _presets = await db.select('SELECT * FROM presets ORDER BY id ASC');
      if (_presets.isNotEmpty && _activePreset == null) _activePreset = _presets.first;

      // 只取计划里用到的文章：原来全表扫 articles 再在 Dart 里过滤；按 id 分批规避绑定变量上限。
      final plan = await db.select('SELECT articleId FROM plan_items');
      final ids = plan.map((p) => '${p['articleId']}').toSet().toList();
      final acc = <Map<String, dynamic>>[];
      for (final chunk in chunked(ids)) {
        final ph = List.filled(chunk.length, '?').join(',');
        acc.addAll(await db.select(
            'SELECT id, guid, title, wordCount, (curated_blocks IS NOT NULL AND length(curated_blocks) > 4) AS hasCurated FROM articles WHERE id IN ($ph)',
            chunk));
      }
      acc.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      _articles = acc;
      await _loadSets();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSets() async {
    _sets = await ref.read(dbProvider).select(
        'SELECT s.id, s.articleId, COUNT(q.id) AS qcount FROM question_sets s LEFT JOIN questions q ON q.setId = s.id GROUP BY s.id');
  }

  List<Map<String, dynamic>> _setsByArticle(dynamic id) => _sets.where((s) => '${s['articleId']}' == '$id').toList();

  Map<String, dynamic> _cfgOf(Map<String, dynamic> p) {
    final raw = p['config'] as String?;
    if (raw != null) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {..._defaultForm, 'types': (_defaultForm['types'] as String).split(',')};
  }

  List<String> _curatedParas(dynamic curated) {
    final raw = curated as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map>().where((b) => b['type'] == 'p').map((b) => (b['text'] ?? '') as String).where((t) => t.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _setGoal(String v) async {
    setState(() => _globalGoal = v);
    await ref.read(dbProvider).execute('INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)', ['targetLevel', v]);
    ref.read(targetLevelRevisionProvider.notifier).bump();
  }

  Future<void> _genSet(Map<String, dynamic> a) async {
    setState(() => _genning = true);
    try {
      final cfg = _activePreset != null ? _cfgOf(_activePreset!) : {..._defaultForm, 'types': ['choice', 'fill']};
      final types = (cfg['types'] is List ? (cfg['types'] as List).map((e) => '$e').toList() : '${cfg['types']}'.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
      final type = types.isNotEmpty ? types.first : 'choice';
      final count = int.tryParse('${cfg['count']}') ?? 5;
      final full = await ref.read(dbProvider).select('SELECT plainText, curated_blocks FROM articles WHERE id = ?', [a['id']]);
      final fa = full.isNotEmpty ? full.first : const <String, dynamic>{};
      var text = fa['plainText'] as String? ?? '';
      final curated = _curatedParas(fa['curated_blocks']);
      if (curated.isNotEmpty) text = curated.join('\n\n');
      if (text.trim().isEmpty) {
        throw Exception('精选版正文过短，请删除精选版后重试');
      }
      final questions = await ref.read(quizProvider).generate(text, type, count);
      final setId = await ref.read(dbProvider).insertReturnId(
          'INSERT INTO question_sets (articleId, presetId, title, createdAt) VALUES (?,?,?,?)',
          [a['id'], _activePreset?['id'], a['title'], DateTime.now().millisecondsSinceEpoch]);
      for (final q in questions) {
        await ref.read(dbProvider).execute(
            'INSERT INTO questions (setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote, createdAt) VALUES (?,?,?,?,?,?,?,?,?)',
            [setId, q['type'] ?? type, q['gradeMode'] ?? 'ai', q['prompt'] ?? '', jsonEncode(q['options'] ?? []), jsonEncode(q['answers'] ?? []), q['analysis'] ?? '', q['sourceQuote'] ?? '', DateTime.now().millisecondsSinceEpoch]);
      }
      await _loadSets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成 ${questions.length} 题${curated.isNotEmpty ? '（基于精选版）' : ''}')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        showDialog(context: context, builder: (c) => AlertDialog(title: const Text('生成失败'), content: Text(errText(e)), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('确定'))]));
      }
    } finally {
      if (mounted) setState(() => _genning = false);
    }
  }

  Future<void> _removeFromPlan(dynamic id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('移出计划'),
        content: const Text('题集与错题记录会保留。'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定'))],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).execute('DELETE FROM plan_items WHERE articleId = ?', [id]);
    ref.read(planRevisionProvider.notifier).bump();
  }

  Future<void> _savePreset() async {
    if ((_form['name'] as String).trim().isEmpty) return;
    final config = jsonEncode({
      'exam': _form['exam'],
      'types': (_form['types'] as String).split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      'focus': _form['focus'],
      'analysisLang': _form['analysisLang'],
      'count': int.tryParse('${_form['count']}') ?? 5,
    });
    final id = await ref.read(dbProvider).insertReturnId('INSERT INTO presets (name, config) VALUES (?,?)', [(_form['name'] as String).trim(), config]);
    _presets = await ref.read(dbProvider).select('SELECT * FROM presets ORDER BY id ASC');
    _activePreset = _presets.firstWhere((p) => '${p['id']}' == '$id', orElse: () => _presets.first);
    setState(() {
      _showPreset = false;
      _form..clear()..addAll(_defaultForm);
    });
  }

  Future<void> _deletePreset() async {
    if (_activePreset == null) return;
    await ref.read(dbProvider).execute('DELETE FROM presets WHERE id = ?', [_activePreset!['id']]);
    _presets = await ref.read(dbProvider).select('SELECT * FROM presets ORDER BY id ASC');
    setState(() {
      _activePreset = _presets.isNotEmpty ? _presets.first : null;
      _showPreset = false;
    });
  }

  void _openPresetForm() {
    setState(() {
      _form..clear()..addAll(_defaultForm);
      _form['exam'] = _globalGoal;
      _showPreset = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(planRevisionProvider, (_, _) => _load());
    ref.listen(targetLevelRevisionProvider, (_, _) => _loadGoal());
    final cfg = ref.watch(appConfigProvider);
    final profiles = cfg.profiles;
    return GoPage(
      topPad: false,
      child: Stack(
        children: [
          Column(
            children: [
              const GoAppBar(title: '出题计划', style: GoAppBarStyle.floating),
              _controls(profiles),
              Expanded(
                child: _loading
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [PolySpinner(), SizedBox(height: Go.sp4), Text('加载中…', style: TextStyle(color: Go.onSurface3, fontSize: Go.fsBodySm))]))
                    : _list(),
              ),
            ],
          ),
          if (_genning)
            Container(
              color: Go.scrim,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Go.sp10, vertical: Go.sp8),
                decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), boxShadow: Go.elev2),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PolySpinner(),
                    SizedBox(height: Go.sp4),
                    Text('AI 正在出题…', style: TextStyle(fontSize: Go.fsBody, color: Go.onSurface)),
                  ],
                ),
              ),
            ),
          if (_showPreset) _presetSheet(),
        ],
      ),
    );
  }

  Widget _presetSheet() {
    return GestureDetector(
      onTap: () => setState(() => _showPreset = false),
      child: Container(
        color: Go.scrim,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(color: Go.surfaceRaised, borderRadius: BorderRadius.vertical(top: Radius.circular(Go.rXl))),
            padding: EdgeInsets.only(left: Go.sp6, right: Go.sp6, top: Go.sp6, bottom: MediaQuery.of(context).padding.bottom + Go.sp6),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('新建出题预设', textAlign: TextAlign.center, style: TextStyle(fontSize: Go.fsH1, fontWeight: FontWeight.w600, color: Go.onSurface)),
                  const SizedBox(height: Go.sp6),
                  GoField(controller: TextEditingController(text: _form['name'] as String), hint: '预设名称', onChanged: (v) => _form['name'] = v),
                  const _Lbl('对标考试'),
                  _picker(_form['exam'] as String, _examKeys, (v) => setState(() => _form['exam'] = v)),
                  const _Lbl('题型（逗号分隔）'),
                  GoField(controller: TextEditingController(text: _form['types'] as String), hint: 'choice,fill,shortAnswer', onChanged: (v) => _form['types'] = v),
                  const _Lbl('考察重点'),
                  GoField(controller: TextEditingController(text: _form['focus'] as String), hint: '词汇、推理', onChanged: (v) => _form['focus'] = v),
                  const _Lbl('解析语言'),
                  _picker(_form['analysisLang'] == 'en' ? 'English' : '中文', const ['中文', 'English'], (v) => setState(() => _form['analysisLang'] = v == 'English' ? 'en' : 'zh')),
                  const _Lbl('题目数量'),
                  GoField(controller: TextEditingController(text: '${_form['count']}'), hint: '', keyboardType: TextInputType.number, onChanged: (v) => _form['count'] = v),
                  const SizedBox(height: Go.sp6),
                  Row(
                    children: [
                      if (_activePreset != null) GestureDetector(onTap: _deletePreset, child: const Text('删除当前', style: TextStyle(color: Go.danger, fontSize: Go.fsBodySm))),
                      const Spacer(),
                      GestureDetector(onTap: () => setState(() => _showPreset = false), child: const Text('取消', style: TextStyle(color: Go.onSurface3, fontSize: Go.fsBody))),
                      const SizedBox(width: Go.sp6),
                      GoBtn(label: '保存', icon: const GoIcon('check', size: 16, color: Go.onPrimary), onTap: _savePreset),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _picker(String value, List<String> options, ValueChanged<String> onPick) {
    return PopupMenuButton<String>(
      onSelected: onPick,
      itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o, child: Text(o))],
      child: Container(
        margin: const EdgeInsets.only(top: Go.sp2),
        padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp3),
        decoration: BoxDecoration(color: Go.surface2, border: Border.all(color: Go.outline, width: 0.5), borderRadius: BorderRadius.circular(Go.rMd)),
        child: Text(value, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface)),
      ),
    );
  }

  Widget _controls(List<dynamic> profiles) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Go.sp5, Go.sp2, Go.sp5, Go.sp2),
      padding: const EdgeInsets.all(Go.sp4),
      decoration: BoxDecoration(
        color: Go.surfaceRaised,
        borderRadius: BorderRadius.circular(Go.rLg),
        border: Border.all(color: Go.outline, width: 0.5),
        boxShadow: Go.elev1,
      ),
      child: Column(
        children: [
          _segRow('预设', [
            for (final p in _presets) _segItem('${p['name']}', _activePreset != null && _activePreset!['id'] == p['id'], () => setState(() => _activePreset = p)),
            _segItem('＋ 新建', false, _openPresetForm),
          ]),
          const SizedBox(height: Go.sp3),
          _segRow('模型', [
            for (final p in profiles)
              _segItem('${p.name}', ref.watch(appConfigProvider).currentProfileId == p.id, () => ref.read(appConfigProvider).setCurrentProfile(p.id)),
          ]),
          const SizedBox(height: Go.sp3),
          Row(
            children: [
              SizedBox(width: Go.r(64), child: const Text('全局目标', maxLines: 1, style: TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3))),
              PopupMenuButton<String>(
                onSelected: _setGoal,
                itemBuilder: (_) => [for (final k in _examKeys) PopupMenuItem(value: k, child: Text(k))],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp2),
                  decoration: BoxDecoration(color: Go.primary95, borderRadius: BorderRadius.circular(Go.rFull)),
                  child: Text(_globalGoal, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.primary, fontWeight: FontWeight.w600)),
                ),
              ),
              const Spacer(),
              const Flexible(
                child: Text('未指定考试时按此难度出题', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segRow(String label, List<Widget> items) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(width: Go.r(64), child: Text(label, maxLines: 1, style: const TextStyle(fontSize: Go.fsBodySm, color: Go.onSurface3))),
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, children: items),
          ),
        ],
      ),
    );
  }

  Widget _segItem(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: Go.sp2),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp2),
            decoration: BoxDecoration(
              color: active ? Go.primary95 : Colors.transparent,
              borderRadius: BorderRadius.circular(Go.rFull),
              border: Border.all(color: active ? Go.primary.withValues(alpha: 0.4) : Colors.transparent, width: 1),
            ),
            child: Text(label, style: TextStyle(fontSize: Go.fsMeta, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? Go.primary : Go.onSurface3)),
          ),
        ),
      );

  Widget _list() {
    if (_articles.isEmpty) {
      return const Center(
        child: GoEmpty(
          icon: 'book',
          title: '计划里还没有文章',
          desc: '阅读页点「加入计划」可在此生成题目',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp4),
      children: [
        for (final a in _articles) _articleCard(a),
      ],
    );
  }

  Widget _articleCard(Map<String, dynamic> a) {
    final sets = _setsByArticle(a['id']);
    final curated = a['hasCurated'] == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: Go.sp4),
      padding: const EdgeInsets.all(Go.sp5),
      decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), border: Border.all(color: Go.outline, width: 0.5), boxShadow: Go.elev1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(a['title'] as String? ?? '', style: const TextStyle(fontSize: Go.fsBody, fontWeight: FontWeight.w600, color: Go.onSurface, height: Go.lhSnug))),
              GestureDetector(
                onTap: () => _genSet(a),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp2),
                  decoration: BoxDecoration(color: Go.primary, borderRadius: BorderRadius.circular(Go.rFull)),
                  child: const Text('生成题集', style: TextStyle(fontSize: Go.fsMeta, color: Go.onPrimary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: Go.sp2),
          Row(
            children: [
              Text('${a['wordCount'] ?? 0} 词', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
              if (curated)
                Container(
                  margin: const EdgeInsets.only(left: Go.sp2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Go.primary95, borderRadius: BorderRadius.circular(Go.rFull)),
                  child: const Text('已精选', style: TextStyle(fontSize: Go.fsCap, color: Go.primary)),
                ),
            ],
          ),
          const SizedBox(height: Go.sp4),
          Wrap(
            spacing: Go.sp3,
            runSpacing: Go.sp2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in sets)
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(setId: s['id'] as int))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp2),
                    decoration: BoxDecoration(color: Go.surface2, borderRadius: BorderRadius.circular(Go.rFull)),
                    child: Text('题集 #${s['id']} · ${s['qcount']}题', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface2)),
                  ),
                ),
              if (sets.isEmpty) const Text('尚无题集', style: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
            ],
          ),
          const SizedBox(height: Go.sp4),
          const Divider(height: 0.5, thickness: 0.5, color: Go.outline),
          const SizedBox(height: Go.sp3),
          Row(
            children: [
              _actionChip('查看原文', () {
                final guid = a['guid'] as String?;
                if (guid == null || guid.isEmpty) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(guid: guid)));
              }),
              const SizedBox(width: Go.sp2),
              if (sets.isNotEmpty) ...[
                _actionChip('导出', () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExportScreen(articleId: a['id'] as int)))),
                const SizedBox(width: Go.sp2),
              ],
              const Spacer(),
              _actionChip('移出计划', () => _removeFromPlan(a['id']), tone: _ActionTone.muted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip(String label, VoidCallback onTap, {_ActionTone tone = _ActionTone.primary}) {
    final color = tone == _ActionTone.primary ? Go.primary : Go.onSurface3;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp2),
        decoration: BoxDecoration(
          color: tone == _ActionTone.primary ? Go.primary95 : Colors.transparent,
          borderRadius: BorderRadius.circular(Go.rFull),
        ),
        child: Text(label, style: TextStyle(fontSize: Go.fsMeta, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }
}

enum _ActionTone { primary, muted }

class _Lbl extends StatelessWidget {
  final String text;
  const _Lbl(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Go.sp3),
        child: Text(text, style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3)),
      );
}
