import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/share_service.dart';
import 'package:global_overview/v4/services/export_template.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4ExportScreen extends ConsumerStatefulWidget {
  final int? setId;
  final int? articleId;
  final bool wrong;

  const V4ExportScreen({
    super.key,
    this.setId,
    this.articleId,
    this.wrong = false,
  });

  @override
  ConsumerState<V4ExportScreen> createState() => _V4ExportScreenState();
}

class _V4ExportScreenState extends ConsumerState<V4ExportScreen> {
  final _template = TextEditingController();
  final Map<String, bool> _switches = {
    'answer': true,
    'analysis': true,
    'mine': false,
    'quote': true,
    'article': true,
  };
  List<Map<String, dynamic>> _sets = const [];
  List<Map<String, dynamic>> _questions = const [];
  String _mode = 'set';
  int _setId = 0;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.wrong ? 'wrong' : 'set';
    _setId = widget.setId ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _template.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadTemplate();
    final articleId = widget.articleId ?? 0;
    if (articleId != 0) {
      _sets = await ref.read(dbProvider).select(
        'SELECT id, title FROM question_sets WHERE articleId = ? ORDER BY id ASC',
        [articleId],
      );
      if (_sets.isNotEmpty && _setId == 0) _setId = _sets.first['id'] as int;
    }
    await _refresh();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _loadTemplate() async {
    try {
      final rows = await ref.read(dbProvider).select(
        "SELECT source FROM templates WHERE name = 'default' LIMIT 1",
      );
      final saved = rows.isEmpty ? null : rows.first['source'] as String?;
      _template.text = (saved == null || saved.trim().isEmpty)
          ? defaultQuestionTemplate
          : saved;
    } catch (_) {
      _template.text = defaultQuestionTemplate;
    }
  }

  Future<void> _refresh() async {
    try {
      if (_mode == 'wrong') {
        _questions = await ref.read(quizProvider).loadWrongList();
      } else if (_setId != 0) {
        _questions = await ref.read(quizProvider).loadSet(_setId);
      } else {
        _questions = const [];
      }
    } catch (_) {
      _questions = const [];
    }
    if (mounted) setState(() {});
  }

  String get _title {
    if (_mode == 'wrong') return '错题本练习';
    final hit = _sets.where((s) => s['id'] == _setId).toList();
    final name = hit.isEmpty ? '' : '${hit.first['title'] ?? ''}';
    return name.isEmpty ? '题集 #$_setId' : name;
  }

  String get _subtitle => _mode == 'wrong' ? '错题重练' : '';

  /// The template output. The preview and 分享 both read it, so what the reader
  /// checks is exactly what leaves the app.
  String _renderedText() => ref
      .read(exportProvider)
      .buildQuestionsText(
        template: _template.text,
        title: _title,
        subtitle: _subtitle,
        questions: _questions,
        withAnswer: _switches['answer'] == true,
        withAnalysis: _switches['analysis'] == true,
        withMine: _switches['mine'] == true,
        withQuote: _switches['quote'] == true,
      );

  Future<void> _share() async {
    if (_questions.isEmpty) {
      showV4Snack(context, '没有可分享的题目', tone: V4SnackTone.warning);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await const ShareService().shareText(
        text: _renderedText(),
        subject: _title,
      );
      if (!mounted) return;
      if (outcome == ShareOutcome.copied) {
        showV4Snack(context, '这台设备没有分享面板，已复制全文');
      } else if (outcome == ShareOutcome.failed) {
        showV4Snack(
          context,
          '没能分享，可以先用「预览」复制全文',
          tone: V4SnackTone.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_questions.isEmpty) {
      showV4Snack(context, '没有可导出的题目', tone: V4SnackTone.warning);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var articleTitle = '';
      var articleBody = '';
      final articleId = widget.articleId ?? 0;
      if (_mode == 'set' && articleId != 0) {
        final rows = await ref.read(dbProvider).select(
          'SELECT title, plainText FROM articles WHERE id = ?',
          [articleId],
        );
        if (rows.isNotEmpty) {
          articleTitle = rows.first['title'] as String? ?? '';
          articleBody = rows.first['plainText'] as String? ?? '';
        }
      }
      await ref
          .read(exportProvider)
          .exportQuestions(
            title: _title,
            subtitle: _subtitle,
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
      if (mounted) {
        showV4Snack(
          context,
          '导出失败：${errText(e)}',
          tone: V4SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTemplate() async {
    if (!templateLooksValid(_template.text)) {
      showV4Snack(
        context,
        '模板里的 {{#if}} / {{#each}} 没有配对，先补齐再保存',
        tone: V4SnackTone.warning,
      );
      return;
    }
    await ref.read(dbProvider).execute(
      "INSERT OR REPLACE INTO templates (name, source) VALUES ('default', ?)",
      [_template.text],
    );
    if (mounted) {
      showV4Snack(context, '模板已保存', tone: V4SnackTone.success);
    }
  }

  Future<void> _resetTemplate() async {
    _template.text = defaultQuestionTemplate;
    await ref.read(dbProvider).execute(
      "DELETE FROM templates WHERE name = 'default'",
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return V4Page(
      title: '导出',
      bottomBar: Row(
        children: [
          TButton(
            size: TButtonSize.large,
            variant: TButtonVariant.text,
            onPressed: _questions.isEmpty ? null : _preview,
            child: const Text('预览'),
          ),
          const SizedBox(width: V4Space.sm),
          Expanded(
            child: TButton(
              size: TButtonSize.large,
              variant: TButtonVariant.outline,
              onPressed: _busy ? null : _share,
              child: const Text('分享'),
            ),
          ),
          const SizedBox(width: V4Space.md),
          Expanded(
            child: V4PrimaryButton(
              onPressed: _busy ? null : _export,
              child: const Text('导出 PDF'),
            ),
          ),
        ],
      ),
      body: _ready
          ? ListView(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                V4Space.sm,
                V4Space.lg,
                V4Space.xxl,
              ),
              children: [
                _scope(),
                const SizedBox(height: V4Space.xxl),
                _switchesSection(),
                const SizedBox(height: V4Space.xxl),
                _templateSection(),
              ],
            )
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  void _preview() {
    if (_questions.isEmpty) return;
    final v4 = context.v4;
    final type = context.v4Type;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: v4.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(V4Radius.sheet)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  V4Space.xl,
                  V4Space.lg,
                  V4Space.lg,
                  V4Space.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '预览 · ${_questions.length} 题',
                        style: type.itemTitle,
                      ),
                    ),
                    Text('分享发送这段文字', style: type.caption),
                  ],
                ),
              ),
              Divider(height: 1, color: v4.rule),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(V4Space.xl),
                  child: SelectableText(
                    _renderedText(),
                    style: type.body.copyWith(height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scope() {
    final v4 = context.v4;
    final type = context.v4Type;
    final sets = widget.wrong
        ? const <Widget>[]
        : [
            _chip('题集', _mode == 'set', () {
              setState(() => _mode = 'set');
              _refresh();
            }),
            _chip('错题本', _mode == 'wrong', () {
              setState(() => _mode = 'wrong');
              _refresh();
            }),
          ];
    return V4Section(
      title: '导出内容',
      hint: widget.wrong ? '合并当前全部错题' : null,
      children: [
        Padding(
          padding: const EdgeInsets.all(V4Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sets.isNotEmpty)
                Wrap(spacing: V4Space.sm, runSpacing: V4Space.sm, children: sets),
              if (sets.isNotEmpty && _mode == 'set' && _sets.isNotEmpty) ...[
                const SizedBox(height: V4Space.md),
                Wrap(
                  spacing: V4Space.sm,
                  runSpacing: V4Space.sm,
                  children: [
                    for (final s in _sets)
                      _chip(
                        '${s['title'] ?? '题集 #${s['id']}'}',
                        _setId == s['id'],
                        () {
                          setState(() => _setId = s['id'] as int);
                          _refresh();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: V4Space.md),
              Text('共 ${_questions.length} 题', style: type.caption),
              if (_questions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: V4Space.xs),
                  child: Text(
                    '这个范围里还没有题目',
                    style: type.caption.copyWith(color: v4.warning),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switchesSection() {
    return V4Section(
      title: '包含项',
      children: [
        _switchRow('参考答案', 'answer'),
        _switchRow('解析', 'analysis'),
        _switchRow('我的作答', 'mine'),
        _switchRow('原文引用', 'quote'),
        if (_mode == 'set') _switchRow('原文正文', 'article'),
      ],
    );
  }

  Widget _templateSection() {
    final v4 = context.v4;
    final type = context.v4Type;
    return V4Section(
      title: '分享模板',
      hint: '变量：$templateVariables',
      children: [
        Padding(
          padding: const EdgeInsets.all(V4Space.lg),
          child: TextField(
            controller: _template,
            minLines: 8,
            maxLines: 14,
            style: type.caption,
            decoration: InputDecoration(
              hintText: '模板源码',
              filled: true,
              fillColor: v4.surfaceSubtle,
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            V4Space.lg,
            0,
            V4Space.lg,
            V4Space.sm,
          ),
          child: Row(
            children: [
              TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.text,
                onPressed: _resetTemplate,
                child: const Text('恢复默认'),
              ),
              TButton(
                size: TButtonSize.large,
                variant: TButtonVariant.text,
                onPressed: _saveTemplate,
                child: const Text('保存模板'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switchRow(String label, String key) {
    return MergeSemantics(
      child: V4Tile(
        title: label,
        trailing: Switch(
          value: _switches[key] == true,
          onChanged: (v) => setState(() => _switches[key] = v),
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return V4Chip(label: label, selected: on, onTap: onTap);
  }
}
