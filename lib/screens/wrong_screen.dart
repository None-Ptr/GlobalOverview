import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/screens/quiz_screen.dart';
import 'package:global_overview/screens/export_screen.dart';
import 'package:global_overview/theme/go_tokens.dart';
import 'package:global_overview/widgets/go_ui.dart';

/// 错题本页：1:1 对齐 legacy/src/pages/wrong/wrong.vue
class WrongScreen extends ConsumerStatefulWidget {
  const WrongScreen({super.key});
  @override
  ConsumerState<WrongScreen> createState() => _WrongScreenState();
}

class _WrongScreenState extends ConsumerState<WrongScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String _error = '';

  int get _pendingCount => _list.where((w) => w['status'] == 'pending').length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      // 复用受限查询（每题最新作答，仅错题/待判），不再全表拉 questions + answers。
      final out = await ref.read(quizProvider).loadWrongList();
      out.sort((a, b) => (b['gradedAt'] as int? ?? 0).compareTo(a['gradedAt'] as int? ?? 0));
      if (mounted) setState(() => _list = out);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _redo(int qid) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(ids: [qid])));
  }

  void _redoAll() {
    final ids = _list.map((w) => w['id'] as int).toList();
    if (ids.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(ids: ids)));
  }

  Future<void> _regradeOne(int qid, String? finalAns) async {
    await ref.read(gradeProvider).gradeBatch([{'questionId': qid, 'final': finalAns ?? ''}]);
    await _load();
  }

  Future<void> _regradeAll() async {
    final items = _list.where((w) => w['status'] == 'pending').map((w) => {'questionId': w['id'], 'final': w['final'] ?? ''}).toList();
    if (items.isEmpty) return;
    final res = await ref.read(gradeProvider).gradeBatch(items);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.pending > 0 ? '仍有 ${res.pending} 题失败' : '全部重判完成')));
  }

  Future<void> _removeOne(int qid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('移出错题本'),
        content: const Text('将清除该题的作答记录，题目本身保留。'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定'))],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).execute('DELETE FROM answers WHERE questionId = ?', [qid]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return GoPage(
      topPad: false,
      globe: true,
      globeActive: !_loading && _list.isEmpty,
      child: Column(
        children: [
          GoAppBar(
            title: '错题本（${_list.length}）',
            style: GoAppBarStyle.floating,
            leading: GoBack(),
            actions: [
              if (_pendingCount > 0) _opLink('重判 $_pendingCount', _regradeAll, warn: true),
              if (_list.isNotEmpty) _opLink('全部重做', _redoAll),
              _opLink('导出', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportScreen(wrong: true)))),
            ],
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _opLink(String label, VoidCallback onTap, {bool warn = false}) => Padding(
        padding: const EdgeInsets.only(left: Go.sp6),
        child: GestureDetector(onTap: onTap, child: Text(label, style: TextStyle(fontSize: Go.fsBodySm, color: warn ? Go.warning : Go.primary))),
      );

  Widget _body() {
    if (_loading) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [PolySpinner(), SizedBox(height: Go.sp4), Text('加载中…', style: TextStyle(color: Go.onSurface3, fontSize: Go.fsBodySm))]));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error, style: const TextStyle(color: Go.danger)),
          const SizedBox(height: Go.sp3),
          GestureDetector(onTap: _load, child: const Text('重试', style: TextStyle(color: Go.primary, fontSize: Go.fsBodySm))),
        ]),
      );
    }
    if (_list.isEmpty) {
      return const Center(
        child: GoEmpty(icon: 'check', title: '还没有错题', desc: '做完测验后，答错的题会自动收进这里'),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp4),
      children: [for (final w in _list) _item(w)],
    );
  }

  Widget _item(Map<String, dynamic> w) {
    final pending = w['status'] == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: Go.sp4),
      padding: const EdgeInsets.all(Go.sp5),
      decoration: BoxDecoration(color: Go.surface, borderRadius: BorderRadius.circular(Go.rLg), border: Border.all(color: Go.outline, width: 0.5), boxShadow: Go.elev1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tag(QuizService.typeLabel(w['type'] as String?)),
              if (pending) ...[const SizedBox(width: Go.sp2), _tag('判分未完成', pend: true)],
            ],
          ),
          const SizedBox(height: Go.sp3),
          Text('${w['prompt']}', style: const TextStyle(fontSize: Go.fsBody, color: Go.onSurface, height: Go.lhNormal)),
          Padding(
            padding: const EdgeInsets.only(top: Go.sp3),
            child: Text('你的答案：${(w['final'] as String?)?.isNotEmpty == true ? w['final'] : '（空）'}', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.danger)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Go.sp2),
            child: Text('正确：${(w['answerList'] as List).join('；')}', style: const TextStyle(fontSize: Go.fsBodySm, color: Go.success)),
          ),
          if ('${w['comment'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Go.sp2), child: Text('${w['comment']}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3))),
          if ('${w['analysis'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Go.sp2), child: Text('${w['analysis']}', style: const TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3, height: Go.lhNormal))),
          const SizedBox(height: Go.sp4),
          const Divider(height: 0.5, thickness: 0.5, color: Go.outline),
          const SizedBox(height: Go.sp4),
          Row(
            children: [
              _op('重做', () => _redo(w['id'] as int)),
              if (pending) ...[const SizedBox(width: Go.sp3), _op('重新判分', () => _regradeOne(w['id'] as int, w['final'] as String?), warn: true)],
              const SizedBox(width: Go.sp3),
              _op('移出', () => _removeOne(w['id'] as int), ghost: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, {bool pend = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Go.sp4, vertical: Go.sp1),
        decoration: BoxDecoration(color: pend ? Go.warning.withValues(alpha: 0.18) : Go.surface2, borderRadius: BorderRadius.circular(Go.rFull)),
        child: Text(label, style: TextStyle(fontSize: Go.fsMeta, color: pend ? Go.warning : Go.onSurface3)),
      );

  Widget _op(String label, VoidCallback onTap, {bool warn = false, bool ghost = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Go.sp5, vertical: Go.sp2),
          decoration: BoxDecoration(
            color: warn ? Go.warning.withValues(alpha: 0.16) : (ghost ? Go.surface2 : Go.primary95),
            borderRadius: BorderRadius.circular(Go.rFull),
          ),
          child: Text(label, style: TextStyle(fontSize: Go.fsMeta, color: warn ? Go.warning : (ghost ? Go.onSurface3 : Go.primary))),
        ),
      );
}
