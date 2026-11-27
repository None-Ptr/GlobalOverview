import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/quiz_service.dart';
import 'package:global_overview/v4/screens/export_screen.dart';
import 'package:global_overview/v4/screens/quiz_screen.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4WrongScreen extends ConsumerStatefulWidget {
  const V4WrongScreen({super.key});

  @override
  ConsumerState<V4WrongScreen> createState() => _V4WrongScreenState();
}

class _V4WrongScreenState extends ConsumerState<V4WrongScreen> {
  List<Map<String, dynamic>> _list = const [];
  bool _loading = true;
  String? _error;

  int get _pending => _list.where((w) => w['status'] == 'pending').length;

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
      final out = await ref.read(quizProvider).loadWrongList();
      out.sort(
        (a, b) => (b['gradedAt'] as int? ?? 0).compareTo(
          a['gradedAt'] as int? ?? 0,
        ),
      );
      if (!mounted) return;
      setState(() => _list = out);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _redoOne(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => V4QuizScreen(ids: [id])),
    );
  }

  void _redoAll() {
    final ids = _list.map((w) => w['id'] as int).toList();
    if (ids.isEmpty) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => V4QuizScreen(ids: ids)));
  }

  Future<void> _regradeOne(int id, String? finalAnswer) async {
    await ref.read(gradeProvider).gradeBatch([
      {'questionId': id, 'final': finalAnswer ?? ''},
    ]);
    await _load();
  }

  Future<void> _regradeAll() async {
    final items = _list
        .where((w) => w['status'] == 'pending')
        .map((w) => {'questionId': w['id'], 'final': w['final'] ?? ''})
        .toList();
    if (items.isEmpty) return;
    final res = await ref.read(gradeProvider).gradeBatch(items);
    await _load();
    if (!mounted) return;
    showV4Snack(
      context,
      res.pending > 0 ? '仍有 ${res.pending} 题没判完' : '已全部重判',
      tone: res.pending > 0 ? V4SnackTone.warning : V4SnackTone.success,
    );
  }

  Future<void> _remove(int id) async {
    final db = ref.read(dbProvider);
    List<Map<String, dynamic>> snapshot;
    try {
      snapshot = await db.select('SELECT * FROM answers WHERE questionId = ?', [
        id,
      ]);
      await db.execute('DELETE FROM answers WHERE questionId = ?', [id]);
    } catch (_) {
      if (!mounted) return;
      showV4Snack(context, '移出失败，请重试', tone: V4SnackTone.error);
      return;
    }
    if (!mounted) return;
    setState(() => _list = _list.where((w) => w['id'] != id).toList());
    showV4Snack(
      context,
      '已移出错题本',
      actionLabel: '撤销',
      duration: const Duration(seconds: 5),
      onAction: () {
        for (final row in snapshot) {
          db.execute(
            'INSERT OR REPLACE INTO answers(id, questionId, draft, final, correct, wrong, status, comment, gradedAt) '
            'VALUES (?,?,?,?,?,?,?,?,?)',
            [
              row['id'],
              row['questionId'],
              row['draft'],
              row['final'],
              row['correct'],
              row['wrong'],
              row['status'],
              row['comment'],
              row['gradedAt'],
            ],
          );
        }
        _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return V4Page(
      title: '错题本',
      actions: [
        PopupMenuButton<String>(
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz),
          enabled: _list.isNotEmpty,
          onSelected: (value) {
            if (value == 'redo') _redoAll();
            if (value == 'regrade') _regradeAll();
            if (value == 'export') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const V4ExportScreen(wrong: true)),
              );
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'redo', child: Text('全部重做')),
            PopupMenuItem(
              value: 'regrade',
              enabled: _pending > 0,
              child: Text(_pending > 0 ? '重判 $_pending 题' : '没有待判分'),
            ),
            const PopupMenuItem(value: 'export', child: Text('导出错题')),
          ],
        ),
      ],
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
          title: '错题读不出来',
          message: _error!,
          action: V4PrimaryButton(
            onPressed: _load,
            child: const Text('重试'),
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return Center(
        child: V4Notice(
          title: '还没有错题',
          message: '做完题集后，答错和没判完的题会收进这里。',
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
        itemCount: _list.length,
        separatorBuilder: (_, _) => const SizedBox(height: V4Space.md),
        itemBuilder: (_, i) => _card(_list[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> w) {
    final v4 = context.v4;
    final type = context.v4Type;
    final pending = w['status'] == 'pending';
    final mine = '${w['final'] ?? ''}';
    final answer = (w['answerList'] as List).join(' / ');
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
          Wrap(
            spacing: V4Space.sm,
            runSpacing: V4Space.sm,
            children: [
              _tag(QuizService.typeLabel(w['type'] as String?), v4.inkMuted, v4.surfaceSubtle),
              if (pending) _tag('待判分', v4.warning, v4.surfaceSubtle),
            ],
          ),
          const SizedBox(height: V4Space.md),
          Text('${w['prompt']}', style: type.body),
          const SizedBox(height: V4Space.md),
          _line('你的答案', mine.isEmpty ? '（空）' : mine, v4.error),
          const SizedBox(height: V4Space.xs),
          _line('参考答案', answer, v4.success),
          if ('${w['comment'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: V4Space.xs),
            _line('评语', '${w['comment']}', v4.inkMuted),
          ],
          if ('${w['analysis'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: V4Space.sm),
            Text('${w['analysis']}', style: type.caption),
          ],
          const SizedBox(height: V4Space.md),
          Divider(height: 1, color: v4.rule),
          const SizedBox(height: V4Space.sm),
          Wrap(
            spacing: V4Space.sm,
            runSpacing: V4Space.sm,
            children: [
              TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.text,
                onPressed: () => _redoOne(w['id'] as int),
                child: const Text('重做'),
              ),
              if (pending)
                TButton(
                  size: TButtonSize.large,
                  variant: TButtonVariant.text,
                  onPressed: () =>
                      _regradeOne(w['id'] as int, w['final'] as String?),
                  child: const Text('重新判分'),
                ),
              TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.text,
                colorPreset: TButtonColorPreset.danger,
                onPressed: () => _remove(w['id'] as int),
                child: const Text('移出'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: V4Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(V4Radius.control),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, height: 1.4, color: fg),
      ),
    );
  }

  Widget _line(String label, String value, Color color) {
    return Text(
      '$label  $value',
      style: context.v4Type.label.copyWith(color: color),
    );
  }
}
