import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_page.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class V4UsageLedgerScreen extends ConsumerStatefulWidget {
  const V4UsageLedgerScreen({super.key});

  @override
  ConsumerState<V4UsageLedgerScreen> createState() =>
      _V4UsageLedgerScreenState();
}

class _V4UsageLedgerScreenState extends ConsumerState<V4UsageLedgerScreen> {
  List<AiUsageRecord> _records = const [];
  bool _loading = true;
  double _budget = 0;
  double _spent = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ledger = AiUsageLedger();
    final records = await ledger.list();
    final spent = await ledger.spentToday();
    if (!mounted) return;
    setState(() {
      _records = records;
      _spent = spent;
      _budget = ref.read(appConfigProvider).aiDailyBudget;
      _loading = false;
    });
  }

  /// `11-25 14:32`, local time; the year only when it is not this one.
  String _stamp(int at) {
    if (at <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final day = '${two(t.month)}-${two(t.day)}';
    final time = '${two(t.hour)}:${two(t.minute)}';
    return t.year == now.year ? '$day $time' : '${t.year}-$day $time';
  }

  String _money(double value) => '¥' + value.toStringAsFixed(4);

  Future<void> _editBudget() async {
    final controller = TextEditingController(
      text: _budget <= 0 ? '' : _budget.toStringAsFixed(2),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('每日 AI 上限'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: '留空或 0 表示不限制',
            prefixText: '¥ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await ref.read(appConfigProvider).setAiDailyBudget(
          double.tryParse(value.trim()) ?? 0,
        );
    await _load();
  }

  Widget _budgetCard(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final over = _budget > 0 && _spent >= _budget;
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
          Row(
            children: [
              Expanded(child: Text('每日 AI 上限', style: type.itemTitle)),
              TextButton(
                key: const ValueKey('v4-usage-budget'),
                onPressed: _editBudget,
                child: Text(_budget <= 0 ? '设置' : '修改'),
              ),
            ],
          ),
          const SizedBox(height: V4Space.xs),
          Text(
            '今日已用 ${_money(_spent)}  ' +
                (_budget <= 0 ? '不限制' : '上限 ${_money(_budget)}'),
            style: type.caption.copyWith(color: over ? v4.warning : null),
          ),
          if (over) ...[
            const SizedBox(height: V4Space.xs),
            Text(
              '已达到上限，下一次 AI 调用会先给出警告。',
              style: type.caption.copyWith(color: v4.warning),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    return Scaffold(
      backgroundColor: v4.page,
      appBar: AppBar(
        backgroundColor: v4.page,
        title: const Text('AI 用量'),
        elevation: 0,
      ),
      body: V4Column(
        child: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(V4Space.lg),
              children: [
                _budgetCard(context),
                const SizedBox(height: V4Space.xxl),
                if (_records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: V4Space.huge),
                    child: Column(
                      children: [
                        Text('还没有 AI 调用记录', style: type.sectionTitle),
                        const SizedBox(height: V4Space.sm),
                        Text('生成练习或判分后，这里会显示本机用量。', style: type.label),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < _records.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: v4.rule),
                    _recordRow(_records[i]),
                  ],
              ],
            ),
      ),
    );
  }

  Widget _recordRow(AiUsageRecord record) {
    final type = context.v4Type;
    final stamp = _stamp(record.at);
    final tokens =
        '输入 ${record.inputTokens} / 输出 ${record.outputTokens}';
    final parts = <String>[
      if (stamp.isNotEmpty) stamp,
      record.model,
      tokens,
      if (record.durationMs > 0)
        (record.durationMs / 1000).toStringAsFixed(1) + ' 秒',
      if (record.status != 'ok') '未成功',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V4Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(record.operation, style: type.itemTitle),
          const SizedBox(height: V4Space.xs),
          Text(parts.join('  '), style: type.caption),
          if (record.amount != null)
            Text(
              record.currency + ' ' + record.amount!.toStringAsFixed(4),
              style: type.caption,
            )
          else if (record.estimatedMin != null && record.estimatedMax != null)
            Text(
              '未提供价格，估算 ' +
                  record.estimatedMin!.toStringAsFixed(4) +
                  '–' +
                  record.estimatedMax!.toStringAsFixed(4),
              style: type.caption,
            ),
        ],
      ),
    );
  }
}
