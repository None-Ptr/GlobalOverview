import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

Future<bool> showAiCostSheet(
  BuildContext context,
  AiCostEstimate estimate, {
  String? budgetNote,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final v4 = sheetContext.v4;
      final type = sheetContext.v4Type;
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(V4Space.xl),
          decoration: BoxDecoration(
            color: v4.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(V4Radius.sheet),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('生成前确认', style: type.sectionTitle),
                const SizedBox(height: V4Space.lg),
                _row(sheetContext, '模型', estimate.model),
                const SizedBox(height: V4Space.sm),
                _row(
                  sheetContext,
                  '输入 Token',
                  '约 ' + estimate.inputTokens.toString(),
                ),
                const SizedBox(height: V4Space.sm),
                _row(
                  sheetContext,
                  '输出 Token',
                  estimate.outputMin.toString() +
                      '–' +
                      estimate.outputMax.toString(),
                ),
                const SizedBox(height: V4Space.sm),
                _row(
                  sheetContext,
                  '预计费用',
                  estimate.hasPrice
                      ? estimate.currency +
                            ' ' +
                            estimate.amountMin!.toStringAsFixed(4) +
                            '–' +
                            estimate.amountMax!.toStringAsFixed(4)
                      : '无法估算金额',
                ),
                const SizedBox(height: V4Space.lg),
                if (budgetNote != null) ...[
                  Text(
                    budgetNote,
                    style: type.label.copyWith(color: v4.warning),
                  ),
                  const SizedBox(height: V4Space.sm),
                ],
                Text(
                  estimate.hasPrice
                      ? '金额按本地价格表估算，实际以服务商账单为准。'
                      : '该模型没有本地价格，只展示 Token 估算。',
                  style: type.caption,
                ),
                const SizedBox(height: V4Space.xl),
                Row(
                  children: [
                    Expanded(
                      child: TButton(
                        size: TButtonSize.large,
                        variant: TButtonVariant.outline,
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: V4Space.md),
                    Expanded(
                      child: V4PrimaryButton(
                        key: const ValueKey('v4-cost-confirm'),
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: const Text('确认生成'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}

Widget _row(BuildContext context, String label, String value) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SizedBox(width: 96, child: Text(label, style: context.v4Type.label)),
    Expanded(child: Text(value, style: context.v4Type.body)),
  ],
);
