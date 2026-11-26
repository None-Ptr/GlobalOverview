import 'package:global_overview/v4/services/migration_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4MigrationScreen extends StatefulWidget {
  final V4MigrationStore store;
  final ValueChanged<String?> onComplete;

  const V4MigrationScreen({
    super.key,
    required this.store,
    required this.onComplete,
  });

  @override
  State<V4MigrationScreen> createState() => _V4MigrationScreenState();
}

class _V4MigrationScreenState extends State<V4MigrationScreen> {
  V4MigrationSummary? _summary;
  bool _loading = true;
  bool _migrating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _inspect());
  }

  Future<void> _inspect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await widget.store.inspect();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取旧学习记录失败，暂时不能升级。';
      });
    }
  }

  Future<void> _migrate() async {
    if (_migrating) return;
    setState(() {
      _migrating = true;
      _error = null;
    });
    try {
      final backup = await widget.store.migrate();
      if (!mounted) return;
      widget.onComplete(backup);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _migrating = false;
        _error = '迁移没有完成，旧数据未被删除，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final summary = _summary;
    return Scaffold(
      backgroundColor: v4.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(V4Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('保留你的学习记录', style: type.pageTitle),
                    const SizedBox(height: V4Space.sm),
                    Text('升级到 V4 前，先确认旧版数据会被安全保留。', style: type.label),
                    const SizedBox(height: V4Space.xxl),
                    if (_loading)
                      const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (summary != null) ...[
                      _summaryBox(summary),
                      const SizedBox(height: V4Space.xxl),
                      Text('会保留', style: type.itemTitle),
                      const SizedBox(height: V4Space.sm),
                      Text(
                        '生词、例句与复习状态\n题集、题目、作答与错题\n连续天数与每日目标',
                        style: type.body,
                      ),
                      const SizedBox(height: V4Space.xxl),
                      Text('其他本机数据', style: type.itemTitle),
                      const SizedBox(height: V4Space.sm),
                      Text(
                        '旧版文章缓存、订阅和模型配置不会在本次迁移中删除。\nM2 接入新内容加速后，再单独清理或重建。',
                        style: type.body,
                      ),
                      const SizedBox(height: V4Space.xxl),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(V4Space.lg),
                        decoration: BoxDecoration(
                          color: v4.surfaceSubtle,
                          borderRadius: BorderRadius.circular(V4Radius.card),
                        ),
                        child: Text(
                          '迁移不会删除本机旧记录；V4 只登记学习资产并创建数据库备份。',
                          style: type.caption,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: V4Space.lg),
                      Text(
                        _error!,
                        style: type.label.copyWith(color: v4.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V4Space.lg,
                V4Space.sm,
                V4Space.lg,
                V4Space.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: V4PrimaryButton(
                  key: const ValueKey('v4-migrate'),
                  onPressed: _loading || _migrating || summary == null
                      ? null
                      : _migrate,
                  child: Text(_migrating ? '正在备份' : '保留学习记录并继续'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBox(V4MigrationSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(V4Space.lg),
      decoration: BoxDecoration(
        color: context.v4.surface,
        borderRadius: BorderRadius.circular(V4Radius.card),
        border: Border.all(color: context.v4.rule),
      ),
      child: Wrap(
        spacing: V4Space.xxl,
        runSpacing: V4Space.md,
        children: [
          _count('生词', summary.vocabWords),
          _count('题集', summary.questionSets),
          _count('题目', summary.questions),
          _count('作答', summary.answers),
          _count('错题', summary.wrongAnswers),
        ],
      ),
    );
  }

  Widget _count(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value.toString(), style: context.v4Type.sectionTitle),
        Text(label, style: context.v4Type.caption),
      ],
    );
  }
}
